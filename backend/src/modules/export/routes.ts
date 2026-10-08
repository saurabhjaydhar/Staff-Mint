import { Router } from 'express';
import { ZipArchive } from 'archiver';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { Advance, Attendance, AuditLog, Company, Employee, Leave, PayrollRun, Payslip } from '../../models/index.js';
import { toXlsx } from '../reports/service.js';
import { outstandingOf } from '../advances/service.js';
import { provider } from '../../providers/registry.js';
import { audit } from '../audit/service.js';
import { logger } from '../../lib/logger.js';
import { env } from '../../config/env.js';

/** One-click full export (PRD F13). Always free; works after cancellation (no plan check). */
export const exportRouter = Router();

exportRouter.get('/', authenticate, requireRole('owner', 'ca'), async (req, res) => {
  const ctx = ctxOf(req);
  const c = ctx.companyId;
  const company = await Company.findById(c).lean();
  const [emps, att, leaves, advs, runs, slips, logs] = await Promise.all([
    Employee.find({ companyId: c }).lean(),
    Attendance.find({ companyId: c }).sort({ date: 1 }).lean(),
    Leave.find({ companyId: c }).lean(),
    Advance.find({ companyId: c, deletedAt: null }).lean(),
    PayrollRun.find({ companyId: c }).sort({ month: 1, revision: 1 }).lean(),
    Payslip.find({ companyId: c }).sort({ month: 1 }).lean(),
    AuditLog.find({ companyId: c }).sort({ at: 1 }).limit(50000).lean(),
  ]);
  const name = new Map(emps.map((e) => [String(e._id), e.name]));
  const rupees = (p?: number | null) => (p ?? 0) / 100;
  const xlsx = await toXlsx([
    { name: 'Employees', headers: ['Name', 'Phone', 'Wage type', 'Rate (₹)', 'Designation', 'Joining date', 'Status'], rows: emps.map((e) => [e.name, e.phone, e.wageType, rupees(e.ratePaise), e.designation ?? '', e.joiningDate ?? '', e.status]) },
    {
      name: 'Attendance',
      headers: ['Date', 'Name', 'Status', 'Leave type', 'Late (min)', 'Worked (min)', 'Punches', 'Overridden', 'Reason'],
      rows: att.map((a) => [a.date, name.get(String(a.employeeId)) ?? '', a.status ?? '', a.leaveType ?? '', a.lateMinutes, a.workedMinutes, a.punches.map((p: any) => `${p.type}@${new Date(p.clientTime).toISOString()}`).join(' '), a.overridden ? 'yes' : '', a.overrideReason ?? '']),
    },
    { name: 'Leaves', headers: ['Name', 'Type', 'From', 'To', 'Days', 'Status', 'Reason'], rows: leaves.map((l) => [name.get(String(l.employeeId)) ?? '', l.type, l.from, l.to, l.days, l.status, l.reason ?? '']) },
    { name: 'Advances', headers: ['Name', 'Date', 'Amount (₹)', 'Mode', 'Balance (₹)', 'Status'], rows: advs.map((a) => [name.get(String(a.employeeId)) ?? '', a.date, rupees(a.amountPaise), a.mode, rupees(outstandingOf(a)), a.status]) },
    { name: 'Payroll runs', headers: ['Month', 'Revision', 'Status', 'Gross (₹)', 'Deductions (₹)', 'Net (₹)', 'Engine'], rows: runs.map((r) => [r.month, r.revision, r.status, rupees(r.totals?.grossPaise), rupees(r.totals?.deductionsPaise), rupees(r.totals?.netPaise), r.engineVersion]) },
    { name: 'Payslips', headers: ['Month', 'Revision', 'Name', 'Payable days', 'Gross (₹)', 'Deductions (₹)', 'Net (₹)', 'Status'], rows: slips.map((s) => [s.month, s.revision, s.employeeName ?? '', s.payableDays ?? 0, rupees(s.grossPaise), rupees(s.deductionsPaise), rupees(s.netPaise), s.status]) },
    { name: 'Audit log', headers: ['At', 'Actor', 'Channel', 'Action', 'Entity', 'Entity ID'], rows: logs.map((l) => [new Date(l.at).toISOString(), l.actorName ?? '', l.channel, l.action, l.entity, l.entityId ? String(l.entityId) : '']) },
  ]);
  await audit(ctx, { action: 'company.export', entity: 'company', entityId: c });
  const safe = (company?.name ?? 'staffmint').replace(/[^\w-]+/g, '_');
  const filename = `${safe}-export.zip`;
  const zip = new ZipArchive({ zlib: { level: 6 } });
  zip.on('error', (err: Error) => logger.error({ err }, 'export zip failed'));
  const asUrl = req.query.delivery === 'url';
  const chunks: Buffer[] = [];
  const ended = new Promise((r) => zip.on('end', r));
  if (asUrl) zip.on('data', (c: Buffer) => chunks.push(c));
  else {
    res.setHeader('Content-Type', 'application/zip');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    zip.pipe(res);
  }
  zip.append(xlsx, { name: 'staffmint-data.xlsx' });
  const storage = await provider('storage');
  for (const s of slips.filter((x) => x.pdfKey)) {
    try {
      zip.append(await storage.get(s.pdfKey!), { name: `payslips/${s.month}/r${s.revision}-${(s.employeeName ?? String(s.employeeId)).replace(/[^\w-]+/g, '_')}.pdf` });
    } catch {
      /* missing file: skip */
    }
  }
  await zip.finalize();
  if (asUrl) {
    await ended;
    const key = `exports/${c}/${Date.now()}-${filename}`;
    await storage.put(key, Buffer.concat(chunks), 'application/zip');
    res.json({ data: { url: await storage.signedUrl(key, env.SIGNED_URL_TTL_SEC, { filename }), filename } });
  }
});
