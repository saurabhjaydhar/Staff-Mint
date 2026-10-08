import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { todayIn } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Advance, Attendance, Branch, Company, Employee, ImportSession, LeaveBalance, User } from '../../models/index.js';
import { audit } from '../audit/service.js';
import { provider } from '../../providers/registry.js';
import { ensureStaffCapacity, createEmployee } from '../employees/service.js';
import { createAdvance } from '../advances/service.js';
import { readPastedText, readTable } from './parse.js';
import { autoMap, cleanRows, dayColumns, parseAttendanceCode, STAFF_FIELDS, type Mapping, type StaffField } from './mapping.js';
import { normalizePhone } from '../../lib/phone.js';
import { logger } from '../../lib/logger.js';

const UNDO_SEC = 30;
const ROLLBACK_HOURS = 24;
const MAX_ROWS = 2000;

/** Ask the LLM to map headers that synonyms/sniffing could not (PRD F2 step 4). */
async function llmMapFallback(headers: string[], rows: Record<string, unknown>[], mapping: Mapping) {
  const missing = (['name', 'phone', 'ratePaise'] as StaffField[]).filter((f) => !Object.values(mapping).includes(f));
  const unmapped = headers.filter((h) => !mapping[h]);
  if (!missing.length || !unmapped.length) return {};
  const llm = await provider('llm');
  if (llm.name === 'rules') return {};
  try {
    const sample = rows.slice(0, 5).map((r) => Object.fromEntries(unmapped.map((h) => [h, r[h]])));
    const r = await llm.extract({
      text: `Map these spreadsheet columns to staff fields. Columns with sample values: ${JSON.stringify(sample)}`,
      tools: [
        {
          name: 'map_columns',
          description: 'Return the column header for each staff field (or omit if not present).',
          parameters: { type: 'object', properties: Object.fromEntries(missing.map((f) => [f, { type: 'string', enum: unmapped }])) },
        },
      ],
      context: { today: new Date().toISOString().slice(0, 10), language: 'en', employeeNames: [], role: 'owner' },
    });
    const out: Record<string, StaffField> = {};
    for (const [field, header] of Object.entries(r.args ?? {})) if (typeof header === 'string' && unmapped.includes(header) && missing.includes(field as StaffField)) out[header] = field as StaffField;
    return out;
  } catch (err) {
    logger.warn({ err }, 'LLM column mapping failed');
    return {};
  }
}

export async function createImport(ctx: Ctx, input: { file?: { buffer: Buffer; originalname: string; mimetype: string }; text?: string; kind: 'staff' | 'attendance'; month?: string; source: string }) {
  if (!input.file && !input.text) throw new AppError('VALIDATION_ERROR', 'Upload a file or paste text');
  if (input.kind === 'attendance' && !input.month) throw new AppError('VALIDATION_ERROR', 'month is required for attendance import');
  const table = input.file ? await readTable(input.file.buffer, input.file.originalname) : readPastedText(input.text!);
  if (!table.rows.length) throw new AppError('VALIDATION_ERROR', 'No rows found in the file');
  if (table.rows.length > MAX_ROWS) throw new AppError('VALIDATION_ERROR', `Too many rows (max ${MAX_ROWS})`);

  let fileKey: string | undefined;
  if (input.file) {
    fileKey = `imports/${ctx.companyId}/${Date.now()}-${input.file.originalname.replace(/[^\w.-]/g, '_')}`;
    await (await provider('storage')).put(fileKey, input.file.buffer, input.file.mimetype || 'application/octet-stream');
  }
  const { mapping, method, template } = autoMap(table.headers, table.rows);
  if (input.source !== 'auto' && input.source !== 'generic' && template && template !== input.source) logger.info({ template, source: input.source }, 'import template mismatch');
  const llmMap = await llmMapFallback(table.headers, table.rows, mapping);
  for (const [h, f] of Object.entries(llmMap)) {
    mapping[h] = f;
    method[h] = 'llm';
  }

  const session = await ImportSession.create({
    companyId: ctx.companyId,
    kind: input.kind,
    source: input.source,
    detectedSource: template ?? (input.text ? 'pasted_text' : 'generic'),
    fileKey,
    fileName: input.file?.originalname,
    month: input.month,
    headers: table.headers,
    mapping,
    mappingMethod: method,
    rawRows: table.rows,
    createdBy: ctx.userId,
  });
  return session;
}

async function existingPhones(companyId: Types.ObjectId) {
  return new Set((await Employee.find({ companyId, deletedAt: null }).select('phone').lean()).map((e) => e.phone));
}

export async function sessionView(ctx: Ctx, s: any) {
  const company = await Company.findById(ctx.companyId).lean();
  if (s.kind === 'attendance') return attendanceSessionView(ctx, s);
  const rows = cleanRows(s.rawRows, s.mapping, s.fixes ?? [], company!.country, await existingPhones(ctx.companyId)).map((r) => ({ ...r, skipped: (s.skipRows ?? []).includes(r.index) }));
  const flagged = rows.filter((r) => r.issues.length && !r.skipped);
  return {
    id: String(s._id),
    kind: s.kind,
    source: s.source,
    detectedSource: s.detectedSource,
    status: s.status,
    headers: s.headers,
    mapping: s.mapping,
    mappingMethod: s.mappingMethod,
    fields: STAFF_FIELDS,
    rows,
    flaggedCount: flagged.length,
    errorCount: rows.filter((r) => !r.skipped && r.issues.some((i) => i.severity === 'error')).length,
    totalRows: rows.length,
    result: s.result ?? null,
    undoUntil: s.undoUntil ?? null,
    rollbackUntil: s.rollbackUntil ?? null,
  };
}

async function attendanceRows(ctx: Ctx, s: any) {
  const cols = dayColumns(s.headers, s.month);
  const company = await Company.findById(ctx.companyId).lean();
  const emps = await Employee.find({ companyId: ctx.companyId, deletedAt: null }).lean();
  const nameCol = Object.keys(s.mapping).find((h) => s.mapping[h] === 'name');
  const phoneCol = Object.keys(s.mapping).find((h) => s.mapping[h] === 'phone');
  const fixMap = new Map((s.fixes ?? []).map((f: any) => [`${f.row}:${f.field}`, f.value]));
  return s.rawRows.map((raw: any, index: number) => {
    const issues: { field: string; message: string; severity: 'error' | 'warning' }[] = [];
    const phone = phoneCol ? normalizePhone(raw[phoneCol], company!.country) : null;
    const name = nameCol ? String(raw[nameCol] ?? '').trim() : '';
    const emp = (phone && emps.find((e) => e.phone === phone)) || emps.find((e) => name && e.name.toLowerCase() === name.toLowerCase());
    if (!emp) issues.push({ field: 'name', message: `No staff found for "${name || phone}"`, severity: 'error' });
    const days: Record<string, { status: string; leaveType?: string } | null> = {};
    for (const [h, date] of Object.entries(cols)) {
      const v = fixMap.has(`${index}:${date}`) ? fixMap.get(`${index}:${date}`) : raw[h];
      const c = parseAttendanceCode(v);
      if (c === undefined) issues.push({ field: date, message: `Unknown code "${v}" (use P/A/HD/L/WO/H)`, severity: 'error' });
      days[date] = c ?? null;
    }
    return { index, values: { name, phone, employeeId: emp ? String(emp._id) : null, days }, issues, skipped: (s.skipRows ?? []).includes(index) };
  });
}

async function attendanceSessionView(ctx: Ctx, s: any) {
  const rows = await attendanceRows(ctx, s);
  return {
    id: String(s._id),
    kind: s.kind,
    month: s.month,
    source: s.source,
    status: s.status,
    headers: s.headers,
    mapping: s.mapping,
    dayColumns: dayColumns(s.headers, s.month),
    rows,
    flaggedCount: rows.filter((r: any) => r.issues.length && !r.skipped).length,
    errorCount: rows.filter((r: any) => !r.skipped && r.issues.some((i: any) => i.severity === 'error')).length,
    totalRows: rows.length,
    result: s.result ?? null,
    undoUntil: s.undoUntil ?? null,
    rollbackUntil: s.rollbackUntil ?? null,
  };
}

export async function getImport(ctx: Ctx, id: string) {
  const s = await ImportSession.findOne({ _id: id, companyId: ctx.companyId });
  if (!s) throw notFound('Import');
  return s;
}

export async function patchImport(ctx: Ctx, id: string, patch: { mapping?: Record<string, string | null>; fixes?: { row: number; field: string; value: unknown }[]; skipRows?: number[] }) {
  const s = await getImport(ctx, id);
  if (s.status !== 'review') throw new AppError('CONFLICT', 'Import already committed');
  if (patch.mapping) {
    const m = { ...(s.mapping as any) };
    const method = { ...(s.mappingMethod as any) };
    for (const [h, f] of Object.entries(patch.mapping)) {
      if (!s.headers.includes(h)) throw new AppError('VALIDATION_ERROR', `Unknown column "${h}"`);
      if (f && !(STAFF_FIELDS as readonly string[]).includes(f)) throw new AppError('VALIDATION_ERROR', `Unknown field "${f}"`);
      // A field maps to one column: remapping applies to all rows (PRD F2).
      if (f) for (const k of Object.keys(m)) if (m[k] === f) m[k] = null;
      m[h] = f;
      method[h] = 'manual';
    }
    s.mapping = m;
    s.mappingMethod = method;
    s.markModified('mapping');
    s.markModified('mappingMethod');
  }
  if (patch.fixes) {
    const fixes = [...(s.fixes as any[])].filter((f) => !patch.fixes!.some((p) => p.row === f.row && p.field === f.field));
    s.fixes = [...fixes, ...patch.fixes] as any;
  }
  if (patch.skipRows) s.skipRows = patch.skipRows;
  await s.save();
  return s;
}

export async function commitImport(ctx: Ctx, id: string, opts: { overwriteExisting?: boolean }) {
  const s = await getImport(ctx, id);
  if (s.status !== 'review') throw new AppError('CONFLICT', 'Import already committed');
  const result = s.kind === 'attendance' ? await commitAttendance(ctx, s, !!opts.overwriteExisting) : await commitStaff(ctx, s, !!opts.overwriteExisting);
  s.status = 'committed';
  s.result = result.summary;
  s.createdEntities = result.created;
  s.undoUntil = new Date(Date.now() + UNDO_SEC * 1000);
  s.rollbackUntil = new Date(Date.now() + ROLLBACK_HOURS * 3600_000);
  await s.save();
  await audit({ ...ctx, channel: 'import' }, { action: `import.${s.kind}.commit`, entity: 'import', entityId: s._id, after: result.summary });
  return { ...result.summary, undoUntil: s.undoUntil, rollbackUntil: s.rollbackUntil };
}

async function commitStaff(ctx: Ctx, s: any, overwrite: boolean) {
  const company = await Company.findById(ctx.companyId).lean();
  const phones = await existingPhones(ctx.companyId);
  const rows = cleanRows(s.rawRows, s.mapping, s.fixes ?? [], company!.country, phones).filter((r) => !(s.skipRows ?? []).includes(r.index));
  const blocking = rows.filter((r) => r.issues.some((i) => i.severity === 'error'));
  if (blocking.length) throw new AppError('VALIDATION_ERROR', `${blocking.length} row(s) still have errors. Fix or skip them.`, { rows: blocking.map((r) => r.index) });
  const fresh = rows.filter((r) => !phones.has(r.values.phone));
  await ensureStaffCapacity(ctx.companyId, fresh.length);
  const branches = await Branch.find({ companyId: ctx.companyId, deletedAt: null }).lean();
  const ictx: Ctx = { ...ctx, channel: 'import' };
  const created = { employees: [] as string[], advances: [] as string[], leaveBalances: [] as string[], updated: [] as { id: string; before: any }[] };
  let updatedCount = 0;
  let skipped = 0;
  const year = Number(todayIn(company!.timezone).slice(0, 4));
  for (const r of rows) {
    const v = r.values;
    const branchId = v.branch ? branches.find((b) => b.name.toLowerCase() === String(v.branch).toLowerCase())?._id : undefined;
    let emp: any = await Employee.findOne({ companyId: ctx.companyId, phone: v.phone, deletedAt: null });
    if (emp) {
      if (!overwrite) {
        skipped++;
        continue;
      }
      created.updated.push({ id: String(emp._id), before: emp.toObject() });
      const before = emp.toObject();
      emp.name = v.name;
      if (v.ratePaise) emp.ratePaise = v.ratePaise;
      if (v.wageType) emp.wageType = v.wageType;
      if (v.designation) emp.designation = v.designation;
      if (v.joiningDate) emp.joiningDate = v.joiningDate;
      if (branchId) emp.branchId = branchId;
      await emp.save();
      await audit(ictx, { action: 'employee.update', entity: 'employee', entityId: emp._id, before, after: emp });
      updatedCount++;
    } else {
      emp = await createEmployee(
        ictx,
        { name: v.name, phone: v.phone, ratePaise: v.ratePaise, wageType: v.wageType, designation: v.designation, joiningDate: v.joiningDate, branchId: branchId ? String(branchId) : undefined },
        { skipCapacityCheck: true, importSessionId: s._id },
      );
      if (v.lastSalaryPaise) await Employee.updateOne({ _id: emp._id, companyId: ctx.companyId }, { openingLastNetPaise: v.lastSalaryPaise });
      created.employees.push(String(emp._id));
    }
    if (v.advanceBalancePaise) {
      const a = await createAdvance(ictx, { employeeId: String(emp._id), amountPaise: v.advanceBalancePaise, date: todayIn(company!.timezone), mode: 'full_next', note: 'Opening balance (imported)', importSessionId: s._id });
      created.advances.push(a.id);
    }
    if (v.paidLeaveBalance !== undefined || v.sickLeaveBalance !== undefined) {
      const lb = await LeaveBalance.findOneAndUpdate(
        { companyId: ctx.companyId, employeeId: emp._id, year },
        { $set: { ...(v.paidLeaveBalance !== undefined ? { paid: v.paidLeaveBalance } : {}), ...(v.sickLeaveBalance !== undefined ? { sick: v.sickLeaveBalance } : {}) } },
        { upsert: true, new: true },
      );
      created.leaveBalances.push(String(lb!._id));
    }
  }
  return { summary: { created: created.employees.length, updated: updatedCount, skipped }, created };
}

async function commitAttendance(ctx: Ctx, s: any, overwrite: boolean) {
  const rows = (await attendanceRows(ctx, s)).filter((r: any) => !r.skipped);
  const blocking = rows.filter((r: any) => r.issues.some((i: any) => i.severity === 'error'));
  if (blocking.length) throw new AppError('VALIDATION_ERROR', `${blocking.length} row(s) still have errors. Fix or skip them.`, { rows: blocking.map((r: any) => r.index) });
  const createdIds: string[] = [];
  const updated: { id: string; before: any }[] = [];
  let skipped = 0;
  for (const r of rows) {
    for (const [date, c] of Object.entries(r.values.days as Record<string, { status: string; leaveType?: string } | null>)) {
      if (!c) continue;
      const existing = await Attendance.findOne({ companyId: ctx.companyId, employeeId: r.values.employeeId, date });
      if (existing) {
        if (!overwrite || existing.punches.length) {
          skipped++;
          continue;
        }
        updated.push({ id: String(existing._id), before: existing.toObject() });
        existing.status = c.status as any;
        existing.leaveType = (c.leaveType as any) ?? null;
        existing.overridden = true;
        existing.overrideReason = 'Imported history';
        await existing.save();
      } else {
        const a = await Attendance.create({ companyId: ctx.companyId, employeeId: r.values.employeeId, date, status: c.status as any, leaveType: (c.leaveType as any) ?? null, overridden: true, overrideReason: 'Imported history', importSessionId: s._id });
        createdIds.push(String(a._id));
      }
    }
  }
  return { summary: { created: createdIds.length, updated: updated.length, skipped }, created: { attendance: createdIds, updatedAttendance: updated } };
}

export async function rollbackImport(ctx: Ctx, id: string) {
  const s = await getImport(ctx, id);
  if (s.status !== 'committed') throw new AppError('CONFLICT', 'Nothing to roll back');
  if (!s.rollbackUntil || s.rollbackUntil < new Date()) throw new AppError('CONFLICT', 'Rollback window (24 hours) has passed');
  const c: any = s.createdEntities ?? {};
  let removed = 0;
  if (s.kind === 'staff') {
    const empIds = (c.employees ?? []).map((x: string) => new Types.ObjectId(x));
    if (empIds.length) {
      const users = await Employee.find({ companyId: ctx.companyId, _id: { $in: empIds } }).select('userId').lean();
      await User.updateMany({ _id: { $in: users.map((u) => u.userId).filter(Boolean) } }, { deletedAt: new Date() });
      const r = await Employee.updateMany({ companyId: ctx.companyId, _id: { $in: empIds } }, { deletedAt: new Date(), status: 'inactive' });
      removed += r.modifiedCount;
    }
    await Advance.updateMany({ companyId: ctx.companyId, importSessionId: s._id }, { deletedAt: new Date() });
    for (const u of c.updated ?? []) {
      const { _id, __v, createdAt, updatedAt, ...before } = u.before;
      await Employee.updateOne({ companyId: ctx.companyId, _id: u.id }, { $set: before });
    }
  } else {
    const r = await Attendance.deleteMany({ companyId: ctx.companyId, importSessionId: s._id });
    removed += r.deletedCount;
    for (const u of c.updatedAttendance ?? []) {
      const { _id, __v, createdAt, updatedAt, ...before } = u.before;
      await Attendance.updateOne({ companyId: ctx.companyId, _id: u.id }, { $set: before });
    }
  }
  s.status = 'rolled_back';
  await s.save();
  await audit({ ...ctx, channel: 'import' }, { action: `import.${s.kind}.rollback`, entity: 'import', entityId: s._id, after: { removed } });
  return { removed };
}
