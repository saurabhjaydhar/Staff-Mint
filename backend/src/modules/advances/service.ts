import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { monthOf } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Advance, Adjustment, Employee, PayrollRun } from '../../models/index.js';
import { audit } from '../audit/service.js';
import { assertEmployeeInScope, employeeScope } from '../employees/service.js';

type AdvanceLike = { amountPaise: number; openingRepaidPaise?: number | null; repayments?: { month?: string | null; amountPaise?: number | null }[] };

/** Outstanding balance. With `beforeMonth`, only repayments of earlier payroll months count (used by the engine). */
export function outstandingOf(a: AdvanceLike, beforeMonth?: string): number {
  const repaid = (a.repayments ?? []).filter((r) => !beforeMonth || (r.month ?? '') < beforeMonth).reduce((s, r) => s + (r.amountPaise ?? 0), 0);
  return Math.max(0, a.amountPaise - (a.openingRepaidPaise ?? 0) - repaid);
}

export const advanceView = (a: any, employeeName?: string) => {
  const balance = outstandingOf(a);
  return {
    id: String(a._id),
    employeeId: String(a.employeeId?._id ?? a.employeeId),
    employeeName: employeeName ?? a.employeeId?.name ?? null,
    amountPaise: a.amountPaise,
    date: a.date,
    mode: a.mode,
    installments: a.installments,
    installmentPaise: a.mode === 'full_next' ? balance : Math.ceil(a.amountPaise / Math.max(1, a.installments)),
    repaidPaise: a.amountPaise - balance,
    balancePaise: balance,
    status: a.status,
    skipMonths: a.skipMonths ?? [],
    note: a.note ?? null,
    createdAt: a.createdAt,
  };
};

export async function advanceBalanceFor(companyId: Types.ObjectId, employeeId: Types.ObjectId): Promise<number> {
  const list = await Advance.find({ companyId, employeeId, status: 'active', deletedAt: null }).lean();
  return list.reduce((s, a) => s + outstandingOf(a), 0);
}

export async function listAdvances(ctx: Ctx, q: { employeeId?: string; status?: 'active' | 'closed' }) {
  const scopeIds = (await Employee.find(employeeScope(ctx)).select('_id').lean()).map((e) => e._id);
  const f: any = { companyId: ctx.companyId, deletedAt: null, employeeId: { $in: scopeIds } };
  if (q.employeeId) f.employeeId = q.employeeId;
  if (q.status) f.status = q.status;
  const list = await Advance.find(f).sort({ date: -1 }).populate('employeeId', 'name').lean();
  return list.map((a) => advanceView(a));
}

export async function createAdvance(
  ctx: Ctx,
  input: { employeeId: string; amountPaise: number; date: string; mode: 'installments' | 'full_next'; installments?: number; note?: string; openingRepaidPaise?: number; importSessionId?: Types.ObjectId },
) {
  const emp = await assertEmployeeInScope(ctx, input.employeeId);
  if (input.amountPaise <= 0) throw new AppError('VALIDATION_ERROR', 'Amount must be more than zero');
  const a = await Advance.create({
    companyId: ctx.companyId,
    employeeId: emp._id,
    amountPaise: input.amountPaise,
    date: input.date,
    mode: input.mode,
    installments: input.mode === 'installments' ? Math.max(1, input.installments ?? 1) : 1,
    note: input.note,
    openingRepaidPaise: input.openingRepaidPaise ?? 0,
    source: ctx.channel,
    importSessionId: input.importSessionId ?? null,
  });
  await audit(ctx, { action: 'advance.create', entity: 'advance', entityId: a._id, after: a });
  return advanceView(a, emp.name);
}

export async function skipAdvanceMonth(ctx: Ctx, id: string, month: string) {
  const a = await Advance.findOne({ _id: id, companyId: ctx.companyId, deletedAt: null });
  if (!a) throw notFound('Advance');
  await assertEmployeeInScope(ctx, a.employeeId);
  const before = a.toObject();
  if (!a.skipMonths.includes(month)) a.skipMonths.push(month);
  await a.save();
  await audit(ctx, { action: 'advance.skip', entity: 'advance', entityId: a._id, before, after: a });
  return advanceView(a);
}

/** Called when a payroll run is approved: replace that month's repayments with the run's deductions. */
export async function recordRepayments(companyId: Types.ObjectId, runId: Types.ObjectId, month: string, deductions: { advanceId: string; amountPaise: number }[]) {
  const byId = new Map(deductions.map((d) => [d.advanceId, d.amountPaise]));
  const affected = await Advance.find({ companyId, deletedAt: null, $or: [{ _id: { $in: [...byId.keys()] } }, { 'repayments.month': month }] });
  for (const a of affected) {
    a.repayments = a.repayments.filter((r: any) => r.month !== month) as any;
    const amt = byId.get(String(a._id));
    if (amt) a.repayments.push({ month, runId, amountPaise: amt } as any);
    a.status = outstandingOf(a) <= 0 ? 'closed' : 'active';
    await a.save();
  }
}

/** Advances eligible for deduction in a payroll month (given on/before month end). */
export async function advancesForMonth(companyId: Types.ObjectId, employeeIds: Types.ObjectId[], month: string) {
  const list = await Advance.find({ companyId, employeeId: { $in: employeeIds }, deletedAt: null, date: { $lte: `${month}-31` } }).lean();
  return list.filter((a) => monthOf(a.date) <= month);
}

// ---- Adjustments (bonus / deduction) ----
export const adjustmentView = (a: any) => ({
  id: String(a._id),
  employeeId: String(a.employeeId?._id ?? a.employeeId),
  employeeName: a.employeeId?.name ?? null,
  month: a.month,
  type: a.type,
  amountPaise: a.amountPaise,
  note: a.note ?? null,
});

/** A month is locked when its latest revision is approved/paid; a correction draft (revise) reopens it. */
async function assertMonthOpen(companyId: Types.ObjectId, month: string) {
  const latest = await PayrollRun.findOne({ companyId, month, deletedAt: null }).sort({ revision: -1 }).select('status').lean();
  const locked = latest && ['approved', 'paid'].includes(latest.status);
  if (locked) throw new AppError('CONFLICT', `Salary for ${month} is already approved. Revise the payroll run to change it.`);
}

export async function listAdjustments(ctx: Ctx, q: { month?: string; employeeId?: string }) {
  const f: any = { companyId: ctx.companyId, deletedAt: null };
  if (q.month) f.month = q.month;
  if (q.employeeId) f.employeeId = q.employeeId;
  return (await Adjustment.find(f).sort({ createdAt: -1 }).populate('employeeId', 'name').lean()).map(adjustmentView);
}

export async function createAdjustment(ctx: Ctx, input: { employeeId: string; month: string; type: 'bonus' | 'deduction'; amountPaise: number; note?: string }) {
  const emp = await assertEmployeeInScope(ctx, input.employeeId);
  if (input.amountPaise <= 0) throw new AppError('VALIDATION_ERROR', 'Amount must be more than zero');
  await assertMonthOpen(ctx.companyId, input.month);
  const a = await Adjustment.create({ companyId: ctx.companyId, ...input, employeeId: emp._id });
  await audit(ctx, { action: `adjustment.${input.type}`, entity: 'adjustment', entityId: a._id, after: a });
  return { ...adjustmentView(a), employeeName: emp.name };
}

export async function deleteAdjustment(ctx: Ctx, id: string) {
  const a = await Adjustment.findOne({ _id: id, companyId: ctx.companyId, deletedAt: null });
  if (!a) throw notFound('Adjustment');
  await assertMonthOpen(ctx.companyId, a.month);
  a.deletedAt = new Date();
  await a.save();
  await audit(ctx, { action: 'adjustment.delete', entity: 'adjustment', entityId: a._id, before: a });
}
