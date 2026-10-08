/**
 * Mint tools: the only things the assistant can do. The LLM picks a tool + args;
 * these definitions validate args, build a confirmation preview, and execute through
 * the same services as the REST API (so audit, RBAC and plan limits all apply).
 */
import { z } from 'zod';
import { DateTime } from 'luxon';
import type { Ctx } from '../../lib/context.js';
import { formatMoney } from '../../lib/money.js';
import { monthLabel, monthOf, previousMonth, todayIn } from '../../lib/dates.js';
import { AppError } from '../../lib/errors.js';
import { Company, Employee, Leave, PayrollRun, Payslip } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import { env } from '../../config/env.js';
import type { LlmTool } from '../../providers/types.js';
import { overrideDay, dayView } from '../attendance/service.js';
import { createAdvance, createAdjustment, advanceBalanceFor } from '../advances/service.js';
import { createEmployee } from '../employees/service.js';
import { addHoliday } from '../company/service.js';
import { buildEngineInputs } from '../payroll/inputs.js';
import { computePayslip } from '../payroll/engine.js';
import { estimateFor } from '../payroll/service.js';
import { renderReport, type ReportKind } from '../reports/service.js';
import { sendPayslips, explain } from '../payslips/service.js';
import { decideLeave, applyLeave } from '../leave/service.js';

export type Lang = 'en' | 'hi';
export const L = (lang: Lang, en: string, hi: string) => (lang === 'hi' ? hi : en);

export interface ToolResult {
  text: string;
  data?: unknown;
  attachment?: { url: string; filename: string };
}

export interface ToolDef<A = any> {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
  kind: 'read' | 'write';
  roles: ('owner' | 'manager' | 'employee')[];
  feature?: string;
  /** Arg holding a spoken employee name that must be resolved to `employeeId`. */
  employeeArg?: string;
  schema: z.ZodType<A>;
  /** Fill defaults that depend on context (dates, months). */
  normalize?: (args: A, ctx: Ctx, today: string) => A;
  preview?: (ctx: Ctx, args: A & { employeeId?: string; employeeLabel?: string }) => Promise<{ title: string; rows: { label: string; value: string }[] }>;
  execute: (ctx: Ctx, args: A & { employeeId?: string; employeeLabel?: string }, meta: { text: string }) => Promise<ToolResult>;
}

const dateS = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const monthS = z.string().regex(/^\d{4}-\d{2}$/);
const optStr = z.string().trim().min(1).optional();
const rupeesToPaise = (r: number) => Math.round(r * 100);
const nice = (d: string, lang: Lang) => DateTime.fromISO(d).setLocale(lang === 'hi' ? 'hi-IN' : 'en-IN').toFormat('d LLL');

const STATUS_LABEL: Record<string, { en: string; hi: string }> = {
  present: { en: 'Present', hi: 'Present (hajir)' },
  absent: { en: 'Absent', hi: 'Absent (gairhajir)' },
  half_day: { en: 'Half Day', hi: 'Half Day' },
  leave: { en: 'Leave', hi: 'Chutti' },
};

async function companyOf(ctx: Ctx) {
  return (await Company.findById(ctx.companyId).lean())!;
}

const markAttendance: ToolDef<{ employeeName: string; date?: string; status: 'present' | 'absent' | 'half_day' | 'leave'; leaveType?: 'paid' | 'sick' | 'unpaid' }> = {
  name: 'mark_attendance',
  description: 'Mark or correct one employee\'s attendance for a day. e.g. "Ramesh ko aaj half day laga do", "Suresh aaj nahi aaya".',
  parameters: {
    type: 'object',
    properties: {
      employeeName: { type: 'string', description: 'Employee name as spoken' },
      date: { type: 'string', description: 'YYYY-MM-DD, default today' },
      status: { type: 'string', enum: ['present', 'absent', 'half_day', 'leave'] },
      leaveType: { type: 'string', enum: ['paid', 'sick', 'unpaid'] },
    },
    required: ['employeeName', 'status'],
  },
  kind: 'write',
  roles: ['owner', 'manager'],
  employeeArg: 'employeeName',
  schema: z.object({ employeeName: z.string().min(1), date: dateS.optional(), status: z.enum(['present', 'absent', 'half_day', 'leave']), leaveType: z.enum(['paid', 'sick', 'unpaid']).optional() }),
  normalize: (a, _c, today) => ({ ...a, date: a.date ?? today }),
  preview: async (ctx, a) => ({
    title: L(ctx.language, 'Mark attendance?', 'Hajiri laga doon?'),
    rows: [
      { label: L(ctx.language, 'Staff', 'Staff'), value: a.employeeLabel! },
      { label: L(ctx.language, 'Date', 'Tarikh'), value: nice(a.date!, ctx.language) },
      { label: L(ctx.language, 'Status', 'Status'), value: STATUS_LABEL[a.status][ctx.language] + (a.status === 'leave' ? ` (${a.leaveType ?? 'paid'})` : '') },
    ],
  }),
  execute: async (ctx, a, meta) => {
    await overrideDay(ctx, { employeeId: a.employeeId!, date: a.date!, status: a.status, leaveType: a.leaveType, reason: `Mint: "${meta.text.slice(0, 120)}"` });
    return { text: L(ctx.language, `Done. ${a.employeeLabel} marked ${STATUS_LABEL[a.status].en} for ${nice(a.date!, 'en')}.`, `Ho gaya. ${a.employeeLabel} ka ${nice(a.date!, 'hi')} ko ${STATUS_LABEL[a.status].hi} laga diya.`) };
  },
};

const whoIs: ToolDef<{ query: 'late' | 'absent' | 'present' | 'on_leave' | 'not_marked'; date?: string }> = {
  name: 'who_is',
  description: 'List who was late / absent / present / on leave / not marked on a day. e.g. "Kaun late aaya?", "Kal kaun absent tha?"',
  parameters: { type: 'object', properties: { query: { type: 'string', enum: ['late', 'absent', 'present', 'on_leave', 'not_marked'] }, date: { type: 'string', description: 'YYYY-MM-DD, default today' } }, required: ['query'] },
  kind: 'read',
  roles: ['owner', 'manager'],
  schema: z.object({ query: z.enum(['late', 'absent', 'present', 'on_leave', 'not_marked']), date: dateS.optional() }),
  normalize: (a, _c, today) => ({ ...a, date: a.date ?? today }),
  execute: async (ctx, a) => {
    const rows = await dayView(ctx, a.date!);
    const today = todayIn((await companyOf(ctx)).timezone);
    const match = rows.filter((r) => {
      switch (a.query) {
        case 'late':
          return r.displayStatus === 'late';
        case 'absent':
          return r.displayStatus === 'absent' || (a.date! < today && r.displayStatus === 'not_marked');
        case 'present':
          return ['present', 'late', 'checked_in', 'half_day'].includes(r.displayStatus);
        case 'on_leave':
          return r.displayStatus === 'leave';
        case 'not_marked':
          return r.displayStatus === 'not_marked';
      }
    });
    const label = { late: ['late', 'late aaye'], absent: ['absent', 'absent the'], present: ['present', 'present the'], on_leave: ['on leave', 'chutti par the'], not_marked: ['not marked yet', 'ki hajiri abhi nahi lagi'] }[a.query];
    const d = nice(a.date!, ctx.language);
    if (!match.length) return { text: L(ctx.language, `Nobody was ${label[0]} on ${d}.`, `${d} ko koi ${label[1].replace(/ the$/, '')} nahi.`), data: [] };
    const list = match.map((r) => (a.query === 'late' && r.record ? `${r.employee.name} (${r.record.lateMinutes} min)` : r.employee.name)).join(', ');
    return { text: L(ctx.language, `${match.length} ${label[0]} on ${d}: ${list}`, `${d} ko ${match.length} log ${label[1]}: ${list}`), data: match.map((r) => r.employee) };
  },
};

const recordAdvance: ToolDef<{ employeeName: string; amount: number; date?: string; installments?: number }> = {
  name: 'record_advance',
  description: 'Record a salary advance (udhaar) given to an employee. e.g. "Amit ko 5000 advance diya".',
  parameters: {
    type: 'object',
    properties: { employeeName: { type: 'string' }, amount: { type: 'number', description: 'Rupees' }, date: { type: 'string', description: 'YYYY-MM-DD, default today' }, installments: { type: 'integer', description: 'Monthly installments; omit = full from next salary' } },
    required: ['employeeName', 'amount'],
  },
  kind: 'write',
  roles: ['owner'],
  feature: 'advances',
  employeeArg: 'employeeName',
  schema: z.object({ employeeName: z.string().min(1), amount: z.coerce.number().positive().max(10_000_000), date: dateS.optional(), installments: z.coerce.number().int().min(1).max(36).optional() }),
  normalize: (a, _c, today) => ({ ...a, date: a.date ?? today }),
  preview: async (ctx, a) => ({
    title: L(ctx.language, 'Record advance?', 'Advance likh doon?'),
    rows: [
      { label: 'Staff', value: a.employeeLabel! },
      { label: L(ctx.language, 'Amount', 'Rakam'), value: formatMoney(rupeesToPaise(a.amount)) },
      { label: L(ctx.language, 'Date', 'Tarikh'), value: nice(a.date!, ctx.language) },
      { label: L(ctx.language, 'Recovery', 'Wapasi'), value: a.installments && a.installments > 1 ? L(ctx.language, `${a.installments} monthly installments`, `${a.installments} kisht mein`) : L(ctx.language, 'Full, from next salary', 'Agli salary se poora') },
    ],
  }),
  execute: async (ctx, a) => {
    await createAdvance(ctx, { employeeId: a.employeeId!, amountPaise: rupeesToPaise(a.amount), date: a.date!, mode: a.installments && a.installments > 1 ? 'installments' : 'full_next', installments: a.installments, note: 'Via Mint' });
    const bal = await advanceBalanceFor(ctx.companyId, (await Employee.findOne({ _id: a.employeeId, companyId: ctx.companyId }).lean())!._id);
    return { text: L(ctx.language, `Recorded ${formatMoney(rupeesToPaise(a.amount))} advance for ${a.employeeLabel}. Total pending: ${formatMoney(bal)}.`, `${a.employeeLabel} ka ${formatMoney(rupeesToPaise(a.amount))} advance likh diya. Kul baaki: ${formatMoney(bal)}.`) };
  },
};

const addAdjustment: ToolDef<{ employeeName: string; type: 'bonus' | 'deduction'; amount: number; month?: string; note?: string }> = {
  name: 'add_adjustment',
  description: 'Add a one-time bonus/incentive or deduction/fine to an employee\'s salary for a month. e.g. "Raju ko 500 bonus".',
  parameters: {
    type: 'object',
    properties: { employeeName: { type: 'string' }, type: { type: 'string', enum: ['bonus', 'deduction'] }, amount: { type: 'number', description: 'Rupees' }, month: { type: 'string', description: 'YYYY-MM, default current month' }, note: { type: 'string' } },
    required: ['employeeName', 'type', 'amount'],
  },
  kind: 'write',
  roles: ['owner'],
  feature: 'payroll',
  employeeArg: 'employeeName',
  schema: z.object({ employeeName: z.string().min(1), type: z.enum(['bonus', 'deduction']), amount: z.coerce.number().positive().max(10_000_000), month: monthS.optional(), note: z.string().max(200).optional() }),
  normalize: (a, _c, today) => ({ ...a, month: a.month ?? monthOf(today) }),
  preview: async (ctx, a) => ({
    title: a.type === 'bonus' ? L(ctx.language, 'Add bonus?', 'Bonus jod doon?') : L(ctx.language, 'Add deduction?', 'Katauti laga doon?'),
    rows: [
      { label: 'Staff', value: a.employeeLabel! },
      { label: L(ctx.language, 'Amount', 'Rakam'), value: formatMoney(rupeesToPaise(a.amount)) },
      { label: L(ctx.language, 'Salary month', 'Salary mahina'), value: monthLabel(a.month!, ctx.language) },
    ],
  }),
  execute: async (ctx, a) => {
    await createAdjustment(ctx, { employeeId: a.employeeId!, month: a.month!, type: a.type, amountPaise: rupeesToPaise(a.amount), note: a.note });
    return {
      text: L(
        ctx.language,
        `${a.type === 'bonus' ? 'Bonus' : 'Deduction'} of ${formatMoney(rupeesToPaise(a.amount))} added for ${a.employeeLabel} (${monthLabel(a.month!, 'en')}).`,
        `${a.employeeLabel} ki ${monthLabel(a.month!, 'hi')} salary mein ${formatMoney(rupeesToPaise(a.amount))} ${a.type === 'bonus' ? 'bonus jod diya' : 'katauti laga di'}.`,
      ),
    };
  },
};

const addEmployeeTool: ToolDef<{ name: string; phone: string; salary?: number; wageType?: 'monthly' | 'daily' }> = {
  name: 'add_employee',
  description: 'Add a new staff member. e.g. "Naya banda Pooja 9876543210 12000".',
  parameters: { type: 'object', properties: { name: { type: 'string' }, phone: { type: 'string' }, salary: { type: 'number', description: 'Rupees per month (or per day if daily)' }, wageType: { type: 'string', enum: ['monthly', 'daily'] } }, required: ['name', 'phone'] },
  kind: 'write',
  roles: ['owner', 'manager'],
  schema: z.object({ name: z.string().trim().min(2).max(80), phone: z.string().min(8), salary: z.coerce.number().min(0).max(10_000_000).optional(), wageType: z.enum(['monthly', 'daily']).optional() }),
  preview: async (ctx, a) => ({
    title: L(ctx.language, 'Add new staff?', 'Naya staff jod doon?'),
    rows: [
      { label: L(ctx.language, 'Name', 'Naam'), value: a.name },
      { label: 'Phone', value: a.phone },
      { label: L(ctx.language, 'Salary', 'Salary'), value: a.salary ? `${formatMoney(rupeesToPaise(a.salary))} / ${a.wageType === 'daily' ? L(ctx.language, 'day', 'din') : L(ctx.language, 'month', 'mahina')}` : '-' },
    ],
  }),
  execute: async (ctx, a) => {
    const e = await createEmployee(ctx, { name: a.name, phone: a.phone, ratePaise: a.salary ? rupeesToPaise(a.salary) : 0, wageType: a.wageType ?? 'monthly' });
    return { text: L(ctx.language, `${e.name} added. They can now log in to the StaffMint app with ${e.phone}.`, `${e.name} jud gaye. Woh ${e.phone} se StaffMint app mein login kar sakte hain.`), data: { employeeId: String(e._id) } };
  },
};

const declareHoliday: ToolDef<{ date: string; name?: string }> = {
  name: 'declare_holiday',
  description: 'Declare a holiday for everyone on a date. e.g. "Kal sabki chutti hai".',
  parameters: { type: 'object', properties: { date: { type: 'string', description: 'YYYY-MM-DD' }, name: { type: 'string' } }, required: ['date'] },
  kind: 'write',
  roles: ['owner'],
  schema: z.object({ date: dateS, name: z.string().max(80).optional() }),
  preview: async (ctx, a) => ({ title: L(ctx.language, 'Declare holiday for everyone?', 'Sabki chutti declare kar doon?'), rows: [{ label: L(ctx.language, 'Date', 'Tarikh'), value: nice(a.date, ctx.language) }, { label: L(ctx.language, 'Name', 'Naam'), value: a.name ?? 'Holiday' }] }),
  execute: async (ctx, a) => {
    await addHoliday(ctx, a.date, a.name ?? 'Holiday');
    return { text: L(ctx.language, `Holiday added for ${nice(a.date, 'en')}. Nobody will be marked absent that day.`, `${nice(a.date, 'hi')} ki chutti laga di. Us din kisi ko absent nahi lagega.`) };
  },
};

const salaryPreview: ToolDef<{ month?: string; employeeName?: string }> = {
  name: 'salary_preview',
  description: 'Estimate total salary (or one employee\'s salary) for a month. e.g. "Is month salary kitni banegi?"',
  parameters: { type: 'object', properties: { month: { type: 'string', description: 'YYYY-MM, default current month' }, employeeName: { type: 'string' } } },
  kind: 'read',
  roles: ['owner'],
  feature: 'payroll',
  employeeArg: 'employeeName',
  schema: z.object({ month: monthS.optional(), employeeName: optStr }),
  normalize: (a, _c, today) => ({ ...a, month: a.month ?? monthOf(today) }),
  execute: async (ctx, a) => {
    const company = await companyOf(ctx);
    const today = todayIn(company.timezone);
    const asOf = a.month === monthOf(today) ? today : undefined;
    const inputs = await buildEngineInputs(ctx.companyId, a.month!, { asOfDate: asOf, employeeIds: a.employeeId ? [new (await import('mongoose')).Types.ObjectId(a.employeeId)] : undefined });
    const results = inputs.map((i) => ({ name: i.employee.name, r: computePayslip(i) }));
    const total = results.reduce((s, x) => s + x.r.netPaise, 0);
    const asOfText = asOf ? L(ctx.language, ` (till ${nice(asOf, 'en')})`, ` (${nice(asOf, 'hi')} tak)`) : '';
    if (a.employeeId && results[0]) {
      const r = results[0].r;
      return { text: L(ctx.language, `${results[0].name}: ${formatMoney(r.netPaise)} for ${monthLabel(a.month!, 'en')}${asOfText}. ${r.lines[0].explanation.en}`, `${results[0].name}: ${monthLabel(a.month!, 'hi')} ki ${formatMoney(r.netPaise)}${asOfText}. ${r.lines[0].explanation.hi}`) };
    }
    const top = results.sort((x, y) => y.r.netPaise - x.r.netPaise).slice(0, 5).map((x) => `${x.name} ${formatMoney(x.r.netPaise)}`).join(', ');
    return {
      text: L(ctx.language, `${monthLabel(a.month!, 'en')} salary for ${results.length} staff: ${formatMoney(total)}${asOfText}. ${top}`, `${monthLabel(a.month!, 'hi')} mein ${results.length} staff ki salary: ${formatMoney(total)}${asOfText}. ${top}`),
      data: { totalPaise: total, employees: results.length },
    };
  },
};

const report: ToolDef<{ kind: ReportKind; month?: string; format?: 'pdf' | 'xlsx' }> = {
  name: 'report',
  description: 'Get a report file: salary register, attendance sheet, advances or late list. e.g. "October ka salary report bhejo".',
  parameters: { type: 'object', properties: { kind: { type: 'string', enum: ['salary', 'attendance', 'advances', 'late'] }, month: { type: 'string', description: 'YYYY-MM' }, format: { type: 'string', enum: ['pdf', 'xlsx'] } }, required: ['kind'] },
  kind: 'read',
  roles: ['owner', 'manager'],
  feature: 'reports',
  schema: z.object({ kind: z.enum(['salary', 'attendance', 'advances', 'late']), month: monthS.optional(), format: z.enum(['pdf', 'xlsx']).optional() }),
  normalize: (a, _c, today) => ({ ...a, month: a.month ?? (a.kind === 'salary' ? previousMonth(monthOf(today)) : monthOf(today)), format: a.format ?? 'pdf' }),
  execute: async (ctx, a) => {
    const file = await renderReport(ctx, a.kind, a.month!, a.format!);
    const storage = await provider('storage');
    const key = `reports/${ctx.companyId}/${Date.now()}-${file.filename}`;
    await storage.put(key, file.data, file.contentType);
    const url = await storage.signedUrl(key, env.SIGNED_URL_TTL_SEC * 6, { filename: file.filename });
    return { text: L(ctx.language, `Here is the ${a.kind} report for ${monthLabel(a.month!, 'en')}.`, `${monthLabel(a.month!, 'hi')} ki ${a.kind} report yeh rahi.`), attachment: { url, filename: file.filename } };
  },
};

async function runForPayslips(ctx: Ctx, month?: string) {
  const company = await companyOf(ctx);
  const thisMonth = monthOf(todayIn(company.timezone));
  const months = month ? [month] : [previousMonth(thisMonth), thisMonth];
  for (const m of months) {
    const run = await PayrollRun.findOne({ companyId: ctx.companyId, month: m, status: { $in: ['approved', 'paid'] } }).sort({ revision: -1 }).lean();
    if (run) return run;
  }
  return null;
}

const sendPayslipsTool: ToolDef<{ month?: string }> = {
  name: 'send_payslips',
  description: 'Send payslips to all staff for an approved salary month. e.g. "Sab ki payslip bhej do".',
  parameters: { type: 'object', properties: { month: { type: 'string', description: 'YYYY-MM; default last approved month' } } },
  kind: 'write',
  roles: ['owner'],
  feature: 'payslips',
  schema: z.object({ month: monthS.optional() }),
  preview: async (ctx, a) => {
    const run = await runForPayslips(ctx, a.month);
    if (!run) throw new AppError('CONFLICT', L(ctx.language, 'No approved salary to send. Open Salary and approve it first.', 'Koi approved salary nahi hai. Pehle Salary screen mein approve karein.'));
    const count = await Payslip.countDocuments({ companyId: ctx.companyId, runId: run._id });
    return {
      title: L(ctx.language, 'Send payslips?', 'Payslip bhej doon?'),
      rows: [
        { label: L(ctx.language, 'Month', 'Mahina'), value: monthLabel(run.month, ctx.language) },
        { label: 'Staff', value: String(count) },
        { label: L(ctx.language, 'Total net pay', 'Kul salary'), value: formatMoney(run.totals?.netPaise ?? 0) },
      ],
    };
  },
  execute: async (ctx, a) => {
    const run = await runForPayslips(ctx, a.month);
    if (!run) throw new AppError('CONFLICT', 'No approved salary to send');
    const r = await sendPayslips(ctx, String(run._id));
    return { text: L(ctx.language, `Sent ${r.queued} payslips for ${monthLabel(run.month, 'en')}${r.viaWhatsApp ? ' (app + WhatsApp)' : ' (app)'}.`, `${monthLabel(run.month, 'hi')} ki ${r.queued} payslip bhej di${r.viaWhatsApp ? ' (app + WhatsApp)' : ' (app par)'}.`) };
  },
};

const decideLeaveTool: ToolDef<{ employeeName: string; decision: 'approved' | 'rejected' }> = {
  name: 'decide_leave',
  description: 'Approve or reject an employee\'s pending leave request. e.g. "Ramesh ki chutti approve kar do".',
  parameters: { type: 'object', properties: { employeeName: { type: 'string' }, decision: { type: 'string', enum: ['approved', 'rejected'] } }, required: ['employeeName', 'decision'] },
  kind: 'write',
  roles: ['owner', 'manager'],
  employeeArg: 'employeeName',
  schema: z.object({ employeeName: z.string().min(1), decision: z.enum(['approved', 'rejected']) }),
  preview: async (ctx, a) => {
    const leave = await Leave.findOne({ companyId: ctx.companyId, employeeId: a.employeeId, status: 'pending', deletedAt: null }).sort({ createdAt: -1 }).lean();
    if (!leave) throw new AppError('NOT_FOUND', L(ctx.language, `${a.employeeLabel} has no pending leave request.`, `${a.employeeLabel} ki koi pending chutti nahi hai.`));
    return {
      title: a.decision === 'approved' ? L(ctx.language, 'Approve leave?', 'Chutti manzoor karoon?') : L(ctx.language, 'Reject leave?', 'Chutti mana karoon?'),
      rows: [
        { label: 'Staff', value: a.employeeLabel! },
        { label: L(ctx.language, 'Dates', 'Tarikh'), value: leave.from === leave.to ? nice(leave.from, ctx.language) : `${nice(leave.from, ctx.language)} – ${nice(leave.to, ctx.language)}` },
        { label: L(ctx.language, 'Type', 'Type'), value: `${leave.type} (${leave.days})` },
      ],
    };
  },
  execute: async (ctx, a) => {
    const leave = await Leave.findOne({ companyId: ctx.companyId, employeeId: a.employeeId, status: 'pending', deletedAt: null }).sort({ createdAt: -1 }).lean();
    if (!leave) throw new AppError('NOT_FOUND', 'No pending leave');
    await decideLeave(ctx, String(leave._id), a.decision);
    return { text: L(ctx.language, `Leave ${a.decision} for ${a.employeeLabel}.`, `${a.employeeLabel} ki chutti ${a.decision === 'approved' ? 'manzoor' : 'na-manzoor'} kar di.`) };
  },
};

const help: ToolDef<Record<string, never>> = {
  name: 'help',
  description: 'Explain what Mint can do.',
  parameters: { type: 'object', properties: {} },
  kind: 'read',
  roles: ['owner', 'manager', 'employee'],
  schema: z.object({}).passthrough() as any,
  execute: async (ctx) => {
    if (ctx.role === 'employee')
      return {
        text: L(ctx.language, 'You can ask: "My salary?", "Why is my salary less?", "I need leave tomorrow".', 'Aap pooch sakte hain: "Meri salary kitni bani?", "Meri salary kam kyun?", "Kal chutti chahiye".'),
      };
    return {
      text: L(
        ctx.language,
        'Try: "Ramesh half day today", "Who came late?", "Amit 5000 advance", "Raju 500 bonus", "New staff Pooja 9876543210 12000", "Holiday tomorrow", "Salary this month?", "October salary report", "Send all payslips". I always ask before saving anything.',
        'Aise boliye: "Ramesh ko aaj half day laga do", "Kaun late aaya?", "Amit ko 5000 advance diya", "Raju ko 500 bonus", "Naya banda Pooja 9876543210 12000", "Kal sabki chutti hai", "Is month salary kitni banegi?", "October ka salary report bhejo", "Sab ki payslip bhej do". Kuch bhi save karne se pehle main poochunga.',
      ),
    };
  },
};

// ---------- Employee tools ----------
const mySalary: ToolDef<{ month?: string }> = {
  name: 'my_salary',
  description: 'Employee asks how much salary they have earned. e.g. "Meri salary kitni bani?"',
  parameters: { type: 'object', properties: { month: { type: 'string', description: 'YYYY-MM' } } },
  kind: 'read',
  roles: ['employee'],
  schema: z.object({ month: monthS.optional() }),
  execute: async (ctx, a) => {
    const est = await estimateFor(ctx.companyId, ctx.employeeId!, a.month);
    if (!est) return { text: L(ctx.language, 'No salary data yet.', 'Abhi salary ka data nahi hai.') };
    const bal = await advanceBalanceFor(ctx.companyId, ctx.employeeId!);
    const r = est.result;
    const till = est.asOfDate ? L(ctx.language, ` till ${nice(est.asOfDate, 'en')}`, ` ${nice(est.asOfDate, 'hi')} tak`) : '';
    return {
      text: L(
        ctx.language,
        `Your ${monthLabel(est.month, 'en')} salary${till}: ${formatMoney(r.netPaise)} (${r.payableDays} payable days).${bal ? ` Advance pending: ${formatMoney(bal)}.` : ''}`,
        `Aapki ${monthLabel(est.month, 'hi')} ki salary${till}: ${formatMoney(r.netPaise)} (${r.payableDays} din).${bal ? ` Baaki advance: ${formatMoney(bal)}.` : ''}`,
      ),
    };
  },
};

const whySalaryLow: ToolDef<{ month?: string }> = {
  name: 'why_salary_low',
  description: 'Employee asks why their salary is less; explain the breakdown. e.g. "Meri salary kam kyun?"',
  parameters: { type: 'object', properties: { month: { type: 'string', description: 'YYYY-MM' } } },
  kind: 'read',
  roles: ['employee'],
  schema: z.object({ month: monthS.optional() }),
  execute: async (ctx, a) => {
    const f: any = { companyId: ctx.companyId, employeeId: ctx.employeeId, status: { $in: ['final', 'sent'] } };
    if (a.month) f.month = a.month;
    const slip = await Payslip.findOne(f).sort({ month: -1, revision: -1 }).lean();
    if (slip) {
      const e = explain(slip, ctx.language);
      return { text: `${e.text}\n${e.lines.join('\n')}` };
    }
    const est = await estimateFor(ctx.companyId, ctx.employeeId!, a.month);
    if (!est) return { text: L(ctx.language, 'No salary data yet.', 'Abhi salary ka data nahi hai.') };
    const e = explain({ ...est.result, employeeName: est.input.employee.name, month: est.month }, ctx.language);
    return { text: `${e.text}\n${e.lines.join('\n')}` };
  },
};

const applyLeaveTool: ToolDef<{ from: string; to?: string; type?: 'paid' | 'sick' | 'unpaid'; reason?: string }> = {
  name: 'apply_leave',
  description: 'Employee applies for leave. e.g. "Kal chutti chahiye".',
  parameters: { type: 'object', properties: { from: { type: 'string', description: 'YYYY-MM-DD' }, to: { type: 'string', description: 'YYYY-MM-DD' }, type: { type: 'string', enum: ['paid', 'sick', 'unpaid'] }, reason: { type: 'string' } }, required: ['from'] },
  kind: 'write',
  roles: ['employee'],
  schema: z.object({ from: dateS, to: dateS.optional(), type: z.enum(['paid', 'sick', 'unpaid']).optional(), reason: z.string().max(300).optional() }),
  normalize: (a) => ({ ...a, to: a.to ?? a.from, type: a.type ?? 'paid' }),
  preview: async (ctx, a) => ({
    title: L(ctx.language, 'Apply for leave?', 'Chutti ki arzi bhej doon?'),
    rows: [
      { label: L(ctx.language, 'Dates', 'Tarikh'), value: a.from === a.to ? nice(a.from, ctx.language) : `${nice(a.from, ctx.language)} – ${nice(a.to!, ctx.language)}` },
      { label: L(ctx.language, 'Type', 'Type'), value: a.type! },
    ],
  }),
  execute: async (ctx, a) => {
    await applyLeave(ctx, { type: a.type!, from: a.from, to: a.to!, reason: a.reason });
    return { text: L(ctx.language, 'Leave request sent to your employer.', 'Chutti ki arzi maalik ko bhej di.') };
  },
};

export const TOOLS: ToolDef[] = [markAttendance, whoIs, recordAdvance, addAdjustment, addEmployeeTool, declareHoliday, salaryPreview, report, sendPayslipsTool, decideLeaveTool, help, mySalary, whySalaryLow, applyLeaveTool];
export const toolByName = new Map(TOOLS.map((t) => [t.name, t]));

export function toolsForRole(role: string): LlmTool[] {
  const r = role === 'system' ? 'owner' : role;
  return TOOLS.filter((t) => t.roles.includes(r as any)).map((t) => ({ name: t.name, description: t.description, parameters: t.parameters }));
}
