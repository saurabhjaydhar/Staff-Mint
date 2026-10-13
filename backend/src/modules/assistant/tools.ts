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
import { loadWeek, sendWeek, setCells, weekStartOf, weekView, type CellInput } from '../roster/service.js';
import { Shift } from '../../models/index.js';
import { Types } from 'mongoose';

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
  present: { en: 'Present', hi: 'हाज़िर' },
  absent: { en: 'Absent', hi: 'ग़ैरहाज़िर' },
  half_day: { en: 'Half Day', hi: 'आधा दिन' },
  leave: { en: 'Leave', hi: 'छुट्टी' },
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
    title: L(ctx.language, 'Mark attendance?', 'हाज़िरी लगाऊँ?'),
    rows: [
      { label: L(ctx.language, 'Staff', 'स्टाफ़'), value: a.employeeLabel! },
      { label: L(ctx.language, 'Date', 'तारीख़'), value: nice(a.date!, ctx.language) },
      { label: L(ctx.language, 'Status', 'स्थिति'), value: STATUS_LABEL[a.status][ctx.language] + (a.status === 'leave' ? ` (${a.leaveType ?? 'paid'})` : '') },
    ],
  }),
  execute: async (ctx, a, meta) => {
    await overrideDay(ctx, { employeeId: a.employeeId!, date: a.date!, status: a.status, leaveType: a.leaveType, reason: `Mint: "${meta.text.slice(0, 120)}"` });
    return { text: L(ctx.language, `Done. ${a.employeeLabel} marked ${STATUS_LABEL[a.status].en} for ${nice(a.date!, 'en')}.`, `हो गया। ${a.employeeLabel} की ${nice(a.date!, 'hi')} की हाज़िरी: ${STATUS_LABEL[a.status].hi}।`) };
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
    const label = { late: ['late', 'लेट आए'], absent: ['absent', 'ग़ैरहाज़िर थे'], present: ['present', 'हाज़िर थे'], on_leave: ['on leave', 'छुट्टी पर थे'], not_marked: ['not marked yet', 'की हाज़िरी अभी नहीं लगी'] }[a.query];
    const d = nice(a.date!, ctx.language);
    if (!match.length) return { text: L(ctx.language, `Nobody was ${label[0]} on ${d}.`, `${d} को कोई ${label[1].replace(/ थे$/, '')} नहीं।`), data: [] };
    const list = match.map((r) => (a.query === 'late' && r.record ? `${r.employee.name} (${r.record.lateMinutes} ${L(ctx.language, 'min', 'मिनट')})` : r.employee.name)).join(', ');
    return { text: L(ctx.language, `${match.length} ${label[0]} on ${d}: ${list}`, `${d} को ${match.length} लोग ${label[1]}: ${list}`), data: match.map((r) => r.employee) };
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
    title: L(ctx.language, 'Record advance?', 'एडवांस लिख दूँ?'),
    rows: [
      { label: L(ctx.language, 'Staff', 'स्टाफ़'), value: a.employeeLabel! },
      { label: L(ctx.language, 'Amount', 'रक़म'), value: formatMoney(rupeesToPaise(a.amount)) },
      { label: L(ctx.language, 'Date', 'तारीख़'), value: nice(a.date!, ctx.language) },
      { label: L(ctx.language, 'Recovery', 'वापसी'), value: a.installments && a.installments > 1 ? L(ctx.language, `${a.installments} monthly installments`, `${a.installments} किश्तों में`) : L(ctx.language, 'Full, from next salary', 'अगली सैलरी से पूरा') },
    ],
  }),
  execute: async (ctx, a) => {
    await createAdvance(ctx, { employeeId: a.employeeId!, amountPaise: rupeesToPaise(a.amount), date: a.date!, mode: a.installments && a.installments > 1 ? 'installments' : 'full_next', installments: a.installments, note: 'Via Mint' });
    const bal = await advanceBalanceFor(ctx.companyId, (await Employee.findOne({ _id: a.employeeId, companyId: ctx.companyId }).lean())!._id);
    return { text: L(ctx.language, `Recorded ${formatMoney(rupeesToPaise(a.amount))} advance for ${a.employeeLabel}. Total pending: ${formatMoney(bal)}.`, `${a.employeeLabel} का ${formatMoney(rupeesToPaise(a.amount))} एडवांस लिख दिया। कुल बाकी: ${formatMoney(bal)}।`) };
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
    title: a.type === 'bonus' ? L(ctx.language, 'Add bonus?', 'बोनस जोड़ दूँ?') : L(ctx.language, 'Add deduction?', 'कटौती लगा दूँ?'),
    rows: [
      { label: L(ctx.language, 'Staff', 'स्टाफ़'), value: a.employeeLabel! },
      { label: L(ctx.language, 'Amount', 'रक़म'), value: formatMoney(rupeesToPaise(a.amount)) },
      { label: L(ctx.language, 'Salary month', 'सैलरी का महीना'), value: monthLabel(a.month!, ctx.language) },
    ],
  }),
  execute: async (ctx, a) => {
    await createAdjustment(ctx, { employeeId: a.employeeId!, month: a.month!, type: a.type, amountPaise: rupeesToPaise(a.amount), note: a.note });
    return {
      text: L(
        ctx.language,
        `${a.type === 'bonus' ? 'Bonus' : 'Deduction'} of ${formatMoney(rupeesToPaise(a.amount))} added for ${a.employeeLabel} (${monthLabel(a.month!, 'en')}).`,
        `${a.employeeLabel} की ${monthLabel(a.month!, 'hi')} की सैलरी में ${formatMoney(rupeesToPaise(a.amount))} ${a.type === 'bonus' ? 'बोनस जोड़ दिया' : 'कटौती लगा दी'}।`,
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
    title: L(ctx.language, 'Add new staff?', 'नया स्टाफ़ जोड़ दूँ?'),
    rows: [
      { label: L(ctx.language, 'Name', 'नाम'), value: a.name },
      { label: L(ctx.language, 'Phone', 'फ़ोन'), value: a.phone },
      { label: L(ctx.language, 'Salary', 'सैलरी'), value: a.salary ? `${formatMoney(rupeesToPaise(a.salary))} / ${a.wageType === 'daily' ? L(ctx.language, 'day', 'दिन') : L(ctx.language, 'month', 'महीना')}` : '-' },
    ],
  }),
  execute: async (ctx, a) => {
    const e = await createEmployee(ctx, { name: a.name, phone: a.phone, ratePaise: a.salary ? rupeesToPaise(a.salary) : 0, wageType: a.wageType ?? 'monthly' }, { invite: true });
    return { text: L(ctx.language, `${e.name} added. They can now log in to the StaffMint app with ${e.phone}.`, `${e.name} जुड़ गए। वे ${e.phone} से StaffMint ऐप में लॉगिन कर सकते हैं।`), data: { employeeId: String(e._id) } };
  },
};

const declareHoliday: ToolDef<{ date: string; name?: string }> = {
  name: 'declare_holiday',
  description: 'Declare a holiday for everyone on a date. e.g. "Kal sabki chutti hai".',
  parameters: { type: 'object', properties: { date: { type: 'string', description: 'YYYY-MM-DD' }, name: { type: 'string' } }, required: ['date'] },
  kind: 'write',
  roles: ['owner'],
  schema: z.object({ date: dateS, name: z.string().max(80).optional() }),
  preview: async (ctx, a) => ({ title: L(ctx.language, 'Declare holiday for everyone?', 'सबकी छुट्टी घोषित कर दूँ?'), rows: [{ label: L(ctx.language, 'Date', 'तारीख़'), value: nice(a.date, ctx.language) }, { label: L(ctx.language, 'Name', 'नाम'), value: a.name ?? 'Holiday' }] }),
  execute: async (ctx, a) => {
    await addHoliday(ctx, a.date, a.name ?? 'Holiday');
    return { text: L(ctx.language, `Holiday added for ${nice(a.date, 'en')}. Nobody will be marked absent that day.`, `${nice(a.date, 'hi')} की छुट्टी लगा दी। उस दिन किसी को ग़ैरहाज़िर नहीं लगेगा।`) };
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
    const asOfText = asOf ? L(ctx.language, ` (till ${nice(asOf, 'en')})`, ` (${nice(asOf, 'hi')} तक)`) : '';
    if (a.employeeId && results[0]) {
      const r = results[0].r;
      return { text: L(ctx.language, `${results[0].name}: ${formatMoney(r.netPaise)} for ${monthLabel(a.month!, 'en')}${asOfText}. ${r.lines[0].explanation.en}`, `${results[0].name}: ${monthLabel(a.month!, 'hi')} की ${formatMoney(r.netPaise)}${asOfText}। ${r.lines[0].explanation.hi}`) };
    }
    const top = results.sort((x, y) => y.r.netPaise - x.r.netPaise).slice(0, 5).map((x) => `${x.name} ${formatMoney(x.r.netPaise)}`).join(', ');
    return {
      text: L(ctx.language, `${monthLabel(a.month!, 'en')} salary for ${results.length} staff: ${formatMoney(total)}${asOfText}. ${top}`, `${monthLabel(a.month!, 'hi')} में ${results.length} स्टाफ़ की सैलरी: ${formatMoney(total)}${asOfText}। ${top}`),
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
    return { text: L(ctx.language, `Here is the ${a.kind} report for ${monthLabel(a.month!, 'en')}.`, `${monthLabel(a.month!, 'hi')} की ${a.kind} रिपोर्ट यह रही।`), attachment: { url, filename: file.filename } };
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
    if (!run) throw new AppError('CONFLICT', L(ctx.language, 'No approved salary to send. Open Salary and approve it first.', 'कोई मंज़ूर सैलरी नहीं है। पहले सैलरी स्क्रीन में मंज़ूर करें।'));
    const count = await Payslip.countDocuments({ companyId: ctx.companyId, runId: run._id });
    return {
      title: L(ctx.language, 'Send payslips?', 'पेस्लिप भेज दूँ?'),
      rows: [
        { label: L(ctx.language, 'Month', 'महीना'), value: monthLabel(run.month, ctx.language) },
        { label: L(ctx.language, 'Staff', 'स्टाफ़'), value: String(count) },
        { label: L(ctx.language, 'Total net pay', 'कुल सैलरी'), value: formatMoney(run.totals?.netPaise ?? 0) },
      ],
    };
  },
  execute: async (ctx, a) => {
    const run = await runForPayslips(ctx, a.month);
    if (!run) throw new AppError('CONFLICT', 'No approved salary to send');
    const r = await sendPayslips(ctx, String(run._id));
    return { text: L(ctx.language, `Sent ${r.queued} payslips for ${monthLabel(run.month, 'en')}${r.viaWhatsApp ? ' (app + WhatsApp)' : ' (app)'}.`, `${monthLabel(run.month, 'hi')} की ${r.queued} पेस्लिप भेज दी${r.viaWhatsApp ? ' (ऐप + WhatsApp)' : ' (ऐप पर)'}।`) };
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
    if (!leave) throw new AppError('NOT_FOUND', L(ctx.language, `${a.employeeLabel} has no pending leave request.`, `${a.employeeLabel} की कोई बाकी छुट्टी की अर्ज़ी नहीं है।`));
    return {
      title: a.decision === 'approved' ? L(ctx.language, 'Approve leave?', 'छुट्टी मंज़ूर करूँ?') : L(ctx.language, 'Reject leave?', 'छुट्टी नामंज़ूर करूँ?'),
      rows: [
        { label: L(ctx.language, 'Staff', 'स्टाफ़'), value: a.employeeLabel! },
        { label: L(ctx.language, 'Dates', 'तारीख़'), value: leave.from === leave.to ? nice(leave.from, ctx.language) : `${nice(leave.from, ctx.language)} – ${nice(leave.to, ctx.language)}` },
        { label: L(ctx.language, 'Type', 'प्रकार'), value: `${leave.type} (${leave.days})` },
      ],
    };
  },
  execute: async (ctx, a) => {
    const leave = await Leave.findOne({ companyId: ctx.companyId, employeeId: a.employeeId, status: 'pending', deletedAt: null }).sort({ createdAt: -1 }).lean();
    if (!leave) throw new AppError('NOT_FOUND', 'No pending leave');
    await decideLeave(ctx, String(leave._id), a.decision);
    return { text: L(ctx.language, `Leave ${a.decision} for ${a.employeeLabel}.`, `${a.employeeLabel} की छुट्टी ${a.decision === 'approved' ? 'मंज़ूर' : 'नामंज़ूर'} कर दी।`) };
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
        text: L(ctx.language, 'You can ask: "My salary?", "Why is my salary less?", "I need leave tomorrow".', 'आप पूछ सकते हैं: "Meri salary kitni bani?", "Meri salary kam kyun?", "Kal chutti chahiye"।'),
      };
    return {
      text: L(
        ctx.language,
        'Try: "Ramesh half day today", "Who came late?", "Raju evening shift this week", "Who is working on Sunday?", "Amit 5000 advance", "Raju 500 bonus", "New staff Pooja 9876543210 12000", "Holiday tomorrow", "Salary this month?", "October salary report", "Send all payslips". I always ask before saving anything.',
        'ऐसे बोलिए: "Ramesh ko aaj half day laga do", "Kaun late aaya?", "Raju ko is hafte evening shift do", "Sunday ko kaun aa raha hai?", "Amit ko 5000 advance diya", "Raju ko 500 bonus", "Naya banda Pooja 9876543210 12000", "Kal sabki chutti hai", "Is month salary kitni banegi?", "October ka salary report bhejo", "Sab ki payslip bhej do". कुछ भी सेव करने से पहले मैं पूछूँगा।',
      ),
    };
  },
};

// ---------- Roster ----------
const MAX_SHIFT_DAYS = 31;
const days = (from: string, to: string) => {
  const out: string[] = [];
  for (let d = DateTime.fromISO(from); d <= DateTime.fromISO(to) && out.length < MAX_SHIFT_DAYS; d = d.plus({ days: 1 })) out.push(d.toISODate()!);
  return out;
};
const dayName = (d: string, lang: Lang) => DateTime.fromISO(d).setLocale(lang === 'hi' ? 'hi-IN' : 'en-IN').toFormat('ccc d');

async function shiftNamed(ctx: Ctx, name: string) {
  if (name === 'off') return null;
  const shifts = await Shift.find({ companyId: ctx.companyId, deletedAt: null }).lean();
  const n = name.toLowerCase().trim();
  const s = shifts.find((x) => x.name.toLowerCase() === n) ?? shifts.find((x) => x.name.toLowerCase().includes(n) || n.includes(x.name.toLowerCase()));
  if (!s) throw new AppError('NOT_FOUND', L(ctx.language, `No shift called "${name}". Shifts: ${shifts.map((x) => x.name).join(', ')}.`, `"${name}" नाम की कोई शिफ़्ट नहीं। शिफ़्ट: ${shifts.map((x) => x.name).join(', ')}।`));
  return s;
}

/** Days the command changes: a range keeps the person's days off; one day is changed as asked. */
async function shiftDays(ctx: Ctx, employeeId: string, from: string, to: string, off: boolean) {
  const list = days(from, to);
  const emp = new Types.ObjectId(employeeId);
  const out: string[] = [];
  for (const week of [...new Set(list.map(weekStartOf))]) {
    const w = await loadWeek(ctx, week, { employeeIds: [emp] });
    const e = w.emps[0];
    if (!e) continue;
    for (const d of list.filter((x) => weekStartOf(x) === week)) {
      if (list.length > 1 && !off && w.draftPlan(e, d).kind === 'off') continue;
      out.push(d);
    }
  }
  return out;
}

const setShiftTool: ToolDef<{ employeeName: string; shift: string; from?: string; to?: string }> = {
  name: 'set_shift',
  description: 'Put one employee on a shift (or a day off) for a day or a range of days and tell them. e.g. "Raju ko is hafte evening shift do", "Pooja ko Sunday off do". shift = the shift name, or "off".',
  parameters: {
    type: 'object',
    properties: {
      employeeName: { type: 'string' },
      shift: { type: 'string', description: 'Shift name as the shop calls it, or "off"' },
      from: { type: 'string', description: 'YYYY-MM-DD, default today' },
      to: { type: 'string', description: 'YYYY-MM-DD, default same as from. "This week" = today to Sunday.' },
    },
    required: ['employeeName', 'shift'],
  },
  kind: 'write',
  roles: ['owner', 'manager'],
  feature: 'roster',
  employeeArg: 'employeeName',
  schema: z.object({ employeeName: z.string().min(1), shift: z.string().min(1), from: dateS.optional(), to: dateS.optional() }),
  normalize: (a, _c, today) => {
    const from = a.from ?? today;
    const to = a.to && a.to >= from ? a.to : from;
    return { ...a, from, to };
  },
  preview: async (ctx, a) => {
    const sh = await shiftNamed(ctx, a.shift);
    const list = await shiftDays(ctx, a.employeeId!, a.from!, a.to!, !sh);
    if (!list.length) throw new AppError('VALIDATION_ERROR', L(ctx.language, 'Those are all days off. Name a day to change it.', 'वे सब छुट्टी के दिन हैं। बदलने के लिए दिन बताइए।'));
    return {
      title: L(ctx.language, 'Change shift and tell them?', 'शिफ़्ट बदलकर बता दूँ?'),
      rows: [
        { label: L(ctx.language, 'Staff', 'स्टाफ़'), value: a.employeeLabel! },
        { label: L(ctx.language, 'Shift', 'शिफ़्ट'), value: sh ? `${sh.name} ${sh.start}–${sh.end}` : L(ctx.language, 'Day off', 'छुट्टी') },
        { label: L(ctx.language, 'Days', 'दिन'), value: list.map((d) => dayName(d, ctx.language)).join(', ') },
      ],
    };
  },
  execute: async (ctx, a) => {
    const sh = await shiftNamed(ctx, a.shift);
    const list = await shiftDays(ctx, a.employeeId!, a.from!, a.to!, !sh);
    const cells: CellInput[] = list.map((d) => ({ employeeId: a.employeeId!, date: d, kind: sh ? 'shift' : 'off', shiftId: sh ? String(sh._id) : null }));
    await setCells(ctx, cells);
    for (const week of [...new Set(list.map(weekStartOf))]) await sendWeek(ctx, week, undefined, { employeeIds: [new Types.ObjectId(a.employeeId!)] });
    const what = sh ? sh.name : L(ctx.language, 'day off', 'छुट्टी');
    return {
      text: L(ctx.language, `Done. ${a.employeeLabel}: ${what} on ${list.map((d) => dayName(d, 'en')).join(', ')}. They've been told.`, `हो गया। ${a.employeeLabel}: ${list.map((d) => dayName(d, 'hi')).join(', ')} को ${what}। उन्हें बता दिया।`),
    };
  },
};

const whoWorks: ToolDef<{ date?: string }> = {
  name: 'who_works',
  description: 'Who works which shift on a day, from the roster. e.g. "Sunday ko kaun aa raha hai?", "Kal kaun kaam par hai?"',
  parameters: { type: 'object', properties: { date: { type: 'string', description: 'YYYY-MM-DD, default today' } } },
  kind: 'read',
  roles: ['owner', 'manager'],
  feature: 'roster',
  schema: z.object({ date: dateS.optional() }),
  normalize: (a, _c, today) => ({ ...a, date: a.date ?? today }),
  execute: async (ctx, a) => {
    const w = await weekView(ctx, a.date!);
    const day = w.days.find((d) => d.date === a.date)!;
    const groups = new Map<string, string[]>();
    const off: string[] = [];
    const leave: string[] = [];
    let unsent = 0;
    for (const p of w.staff) {
      const c = p.cells.find((x) => x.date === a.date)!;
      if (!c.employed) continue;
      if (c.changed) unsent++;
      if (c.leave) leave.push(p.name);
      else if (c.kind === 'off' || !c.shiftId) off.push(p.name);
      else groups.set(c.shiftId, [...(groups.get(c.shiftId) ?? []), p.name]);
    }
    const parts = [
      ...w.shifts.filter((s) => groups.has(s.id)).map((s) => `${s.name} ${s.start}–${s.end}: ${groups.get(s.id)!.join(', ')}`),
      ...(leave.length ? [`${L(ctx.language, 'On leave', 'छुट्टी पर')}: ${leave.join(', ')}`] : []),
      ...(off.length ? [`${L(ctx.language, 'Off', 'छुट्टी')}: ${off.join(', ')}`] : []),
    ];
    const head = `${dayName(a.date!, ctx.language)}${day.holiday ? ` (${day.holiday})` : ''}`;
    const note = unsent ? L(ctx.language, ` (${unsent} change${unsent === 1 ? '' : 's'} not sent to staff yet)`, ` (${unsent} बदलाव अभी स्टाफ़ को नहीं भेजे)`) : '';
    const working = [...groups.values()].reduce((n, x) => n + x.length, 0);
    return {
      text: `${L(ctx.language, `${head}: ${working} working${note}.`, `${head}: ${working} लोग काम पर${note}।`)}\n${parts.join('\n')}`,
      data: { date: a.date, working },
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
    if (!est) return { text: L(ctx.language, 'No salary data yet.', 'अभी सैलरी का डेटा नहीं है।') };
    const bal = await advanceBalanceFor(ctx.companyId, ctx.employeeId!);
    const r = est.result;
    const till = est.asOfDate ? L(ctx.language, ` till ${nice(est.asOfDate, 'en')}`, ` ${nice(est.asOfDate, 'hi')} तक`) : '';
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
    if (!est) return { text: L(ctx.language, 'No salary data yet.', 'अभी सैलरी का डेटा नहीं है।') };
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
    title: L(ctx.language, 'Apply for leave?', 'छुट्टी की अर्ज़ी भेज दूँ?'),
    rows: [
      { label: L(ctx.language, 'Dates', 'तारीख़'), value: a.from === a.to ? nice(a.from, ctx.language) : `${nice(a.from, ctx.language)} – ${nice(a.to!, ctx.language)}` },
      { label: L(ctx.language, 'Type', 'प्रकार'), value: a.type! },
    ],
  }),
  execute: async (ctx, a) => {
    await applyLeave(ctx, { type: a.type!, from: a.from, to: a.to!, reason: a.reason });
    return { text: L(ctx.language, 'Leave request sent to your employer.', 'छुट्टी की अर्ज़ी मालिक को भेज दी।') };
  },
};

export const TOOLS: ToolDef[] = [markAttendance, whoIs, setShiftTool, whoWorks, recordAdvance, addAdjustment, addEmployeeTool, declareHoliday, salaryPreview, report, sendPayslipsTool, decideLeaveTool, help, mySalary, whySalaryLow, applyLeaveTool];
export const toolByName = new Map(TOOLS.map((t) => [t.name, t]));

export function toolsForRole(role: string): LlmTool[] {
  const r = role === 'system' ? 'owner' : role;
  return TOOLS.filter((t) => t.roles.includes(r as any)).map((t) => ({ name: t.name, description: t.description, parameters: t.parameters }));
}
