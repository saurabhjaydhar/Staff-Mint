import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { todayIn, monthOf } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Company, Employee, PayrollRun, Payslip } from '../../models/index.js';
import { audit } from '../audit/service.js';
import { computePayslip, ENGINE_VERSION, type EngineResult } from './engine.js';
import { buildEngineInputs, payrollSettingsOf } from './inputs.js';
import { recordRepayments } from '../advances/service.js';
import { enqueue } from '../../jobs/queue.js';
import { notifyOwners } from '../notifications/service.js';
import { payslipView } from '../payslips/views.js';

const LOCKED = ['approved', 'paid'];

function toPayslipDoc(companyId: Types.ObjectId, runId: Types.ObjectId, revision: number, month: string, r: EngineResult, input: any, emp: any) {
  return {
    companyId,
    runId,
    employeeId: emp._id,
    employeeName: emp.name,
    employeePhone: emp.phone,
    month,
    revision,
    wageType: r.wageType,
    ratePaise: r.ratePaise,
    payableDays: r.payableDays,
    daysInMonth: r.daysInMonth,
    divisor: r.divisor,
    summary: r.summary,
    lines: r.lines,
    grossPaise: r.grossPaise,
    deductionsPaise: r.deductionsPaise,
    netPaise: r.netPaise,
    inputs: { ...input, advanceDeductions: r.advanceDeductions },
    status: 'draft',
  };
}

export async function runView(run: any, withPayslips = true, lang: 'en' | 'hi' = 'en') {
  const slips = withPayslips ? await Payslip.find({ companyId: run.companyId, runId: run._id }).sort({ employeeName: 1 }).lean() : [];
  return {
    id: String(run._id),
    month: run.month,
    revision: run.revision,
    status: run.status,
    engineVersion: run.engineVersion,
    totals: run.totals,
    anomalies: (run.anomalies ?? []).map((a: any) => ({ employeeId: String(a.employeeId), employeeName: a.employeeName, code: a.code, message: lang === 'hi' ? (a.messageHi ?? a.message) : a.message })),
    approvedAt: run.approvedAt ?? null,
    paidAt: run.paidAt ?? null,
    createdAt: run.createdAt,
    ...(withPayslips ? { payslips: await Promise.all(slips.map((s) => payslipView(s, lang))) } : {}),
  };
}

async function computeInto(ctx: Ctx, run: any) {
  const inputs = await buildEngineInputs(ctx.companyId, run.month);
  const emps = await Employee.find({ companyId: ctx.companyId, _id: { $in: inputs.map((i) => i.employee.employeeId) } }).lean();
  const byId = new Map(emps.map((e) => [String(e._id), e]));
  await Payslip.deleteMany({ companyId: ctx.companyId, runId: run._id, status: 'draft' });
  const docs = [];
  const anomalies = [];
  let gross = 0;
  let ded = 0;
  let net = 0;
  for (const input of inputs) {
    const r = computePayslip(input);
    const emp = byId.get(input.employee.employeeId)!;
    docs.push(toPayslipDoc(ctx.companyId, run._id, run.revision, run.month, r, input, emp));
    for (const a of r.anomalies) anomalies.push({ employeeId: emp._id, employeeName: emp.name, code: a.code, message: a.message.en, messageHi: a.message.hi });
    gross += r.grossPaise;
    ded += r.deductionsPaise;
    net += r.netPaise;
  }
  if (docs.length) await Payslip.insertMany(docs);
  const company = await Company.findById(ctx.companyId).lean();
  run.engineVersion = ENGINE_VERSION;
  run.settingsSnapshot = payrollSettingsOf(company);
  run.totals = { grossPaise: gross, deductionsPaise: ded, netPaise: net, employees: docs.length };
  run.anomalies = anomalies;
  await run.save();
  return run;
}

export async function listRuns(ctx: Ctx, month?: string) {
  const f: any = { companyId: ctx.companyId, deletedAt: null };
  if (month) f.month = month;
  const runs = await PayrollRun.find(f).sort({ month: -1, revision: -1 }).limit(48).lean();
  return Promise.all(runs.map((r) => runView(r, false, ctx.language)));
}

export async function getRun(ctx: Ctx, id: string) {
  const run = await PayrollRun.findOne({ _id: id, companyId: ctx.companyId, deletedAt: null });
  if (!run) throw notFound('Payroll run');
  return run;
}

/** Create the month's draft, or recompute it if it is still a draft. */
export async function createOrRecomputeDraft(ctx: Ctx, month: string) {
  const company = await Company.findById(ctx.companyId).lean();
  if (month > monthOf(todayIn(company!.timezone))) throw new AppError('VALIDATION_ERROR', 'Cannot run payroll for a future month');
  const latest = await PayrollRun.findOne({ companyId: ctx.companyId, month, deletedAt: null }).sort({ revision: -1 });
  if (latest && LOCKED.includes(latest.status)) throw new AppError('CONFLICT', `Salary for ${month} is already ${latest.status}. Use "revise" to make corrections.`, { runId: String(latest._id) });
  const run = latest ?? new PayrollRun({ companyId: ctx.companyId, month, revision: 1, engineVersion: ENGINE_VERSION });
  await computeInto(ctx, run);
  await audit(ctx, { action: latest ? 'payroll.recompute' : 'payroll.draft', entity: 'payroll_run', entityId: run._id, after: { month, totals: run.totals } });
  return run;
}

export async function recompute(ctx: Ctx, id: string) {
  const run = await getRun(ctx, id);
  if (run.status !== 'draft') throw new AppError('CONFLICT', 'Only draft runs can be recomputed');
  await computeInto(ctx, run);
  await audit(ctx, { action: 'payroll.recompute', entity: 'payroll_run', entityId: run._id, after: { totals: run.totals } });
  return run;
}

export async function approve(ctx: Ctx, id: string) {
  const run = await getRun(ctx, id);
  if (run.status !== 'draft') throw new AppError('CONFLICT', `Run is ${run.status}`);
  // Recompute right before approval so the snapshot reflects the latest attendance.
  await computeInto(ctx, run);
  const slips = await Payslip.find({ companyId: ctx.companyId, runId: run._id }).lean();
  const deductions = slips.flatMap((s: any) => s.inputs?.advanceDeductions ?? []);
  await recordRepayments(ctx.companyId, run._id, run.month, deductions);
  await Payslip.updateMany({ companyId: ctx.companyId, runId: run._id }, { $set: { status: 'final' } });
  if (run.previousRunId) await PayrollRun.updateOne({ companyId: ctx.companyId, _id: run.previousRunId }, { status: 'superseded' });
  run.status = 'approved';
  run.approvedAt = new Date();
  run.approvedBy = ctx.userId ?? undefined;
  await run.save();
  await audit(ctx, { action: 'payroll.approve', entity: 'payroll_run', entityId: run._id, after: { month: run.month, revision: run.revision, totals: run.totals } });
  await enqueue('payslips.pdf', { companyId: String(ctx.companyId), runId: String(run._id) });
  return run;
}

export async function markPaid(ctx: Ctx, id: string) {
  const run = await getRun(ctx, id);
  if (run.status !== 'approved') throw new AppError('CONFLICT', 'Approve the salary first');
  run.status = 'paid';
  run.paidAt = new Date();
  await run.save();
  await audit(ctx, { action: 'payroll.paid', entity: 'payroll_run', entityId: run._id, after: { month: run.month } });
  return run;
}

export async function revise(ctx: Ctx, id: string) {
  const run = await getRun(ctx, id);
  if (!LOCKED.includes(run.status)) throw new AppError('CONFLICT', 'Only approved or paid runs can be revised');
  const newer = await PayrollRun.findOne({ companyId: ctx.companyId, month: run.month, revision: { $gt: run.revision } });
  if (newer) throw new AppError('CONFLICT', 'A newer revision already exists', { runId: String(newer._id) });
  const draft = new PayrollRun({ companyId: ctx.companyId, month: run.month, revision: run.revision + 1, previousRunId: run._id, engineVersion: ENGINE_VERSION });
  await computeInto(ctx, draft);
  await audit(ctx, { action: 'payroll.revise', entity: 'payroll_run', entityId: draft._id, after: { month: run.month, revision: draft.revision } });
  return draft;
}

/** Running estimate for an employee (not persisted). */
export async function estimateFor(companyId: Types.ObjectId, employeeId: Types.ObjectId, month?: string) {
  const company = await Company.findById(companyId).lean();
  const today = todayIn(company!.timezone);
  const m = month ?? monthOf(today);
  const asOf = m === monthOf(today) ? today : undefined;
  const [input] = await buildEngineInputs(companyId, m, { employeeIds: [employeeId], asOfDate: asOf });
  if (!input) return null;
  return { input, result: computePayslip(input), asOfDate: asOf ?? null, month: m };
}

/** Called by the scheduler on the 1st: draft last month's payroll and tell the owner. */
export async function autoDraftForCompany(companyId: Types.ObjectId, month: string) {
  const exists = await PayrollRun.exists({ companyId, month });
  if (exists) return null;
  const { systemCtx } = await import('../../lib/context.js');
  const ctx = systemCtx(companyId);
  const { companyPlan } = await import('../billing/plans.js');
  const { plan } = await companyPlan({ _id: companyId });
  if (!plan.features.includes('payroll')) return null;
  const run = await createOrRecomputeDraft(ctx, month);
  await notifyOwners(companyId, {
    template: 'salary_ready',
    title: 'Salary ready for review',
    titleHi: 'सैलरी तैयार है',
    body: `${month} salary draft is ready. Review and approve.`,
    bodyHi: `${month} की सैलरी ड्राफ्ट तैयार है। देखकर मंज़ूर करें।`,
    data: { type: 'salary_ready', runId: String(run._id), month },
    whatsapp: { template: 'salary_ready', params: [month, String(run.totals?.employees ?? 0)] },
  });
  return run;
}
