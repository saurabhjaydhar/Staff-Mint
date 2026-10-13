import { Types } from 'mongoose';
import { DateTime } from 'luxon';
import { AppError } from '../../lib/errors.js';
import { todayIn } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Company, Employee, RosterEntry, RosterRepeat } from '../../models/index.js';
import { employeeScope } from '../employees/service.js';
import { audit } from '../audit/service.js';
import { companyPlan } from '../billing/plans.js';
import { employedOn, loadWeek, same, weekStartOf, type DayPlan } from './service.js';

export type RepeatMode = 'same' | 'rotate';

/** Future weeks the roster fills in on its own when the owner looks ahead. */
const FILL_AHEAD_WEEKS = 8;

const weeksBetween = (from: string, to: string) => Math.round(DateTime.fromISO(to).diff(DateTime.fromISO(from), 'weeks').weeks);

async function staffInScope(ctx: Ctx, branchId?: string) {
  const f: any = { ...employeeScope(ctx), status: 'active' };
  if (branchId) f.branchId = new Types.ObjectId(branchId);
  return Employee.find(f).select('_id').lean();
}

export async function canRepeat(companyId: Types.ObjectId) {
  return (await companyPlan({ _id: companyId })).plan.features.includes('roster_repeat');
}

/** The repeat set up for the people in view, if any: how it repeats and for how many of them. */
export async function repeatInfo(ctx: Ctx, branchId?: string) {
  const ids = (await staffInScope(ctx, branchId)).map((e) => e._id);
  const docs = await RosterRepeat.find({ companyId: ctx.companyId, employeeId: { $in: ids } }).sort({ updatedAt: -1 }).lean();
  if (!docs.length) return null;
  return { mode: docs[0].mode as RepeatMode, startWeek: docs[0].startWeek, autoSend: !!docs[0].autoSend, staff: docs.length };
}

/**
 * Turn on "Repeat every week" from [week]'s plan for everyone in view. `rotate` moves each person to the
 * next shift every week (in start-time order of the shifts used that week); days off stay on the same days.
 */
export async function turnOnRepeat(ctx: Ctx, input: { week: string; mode: RepeatMode; autoSend?: boolean; branchId?: string }) {
  const start = weekStartOf(input.week);
  const w = await loadWeek(ctx, start, { branchId: input.branchId });
  if (!w.emps.length) throw new AppError('VALIDATION_ERROR', 'Add staff first');
  // A day with no roster entry stays "usual", so a later change to the person's usual shift or weekly off still counts.
  const planOf = (e: any) =>
    w.days.map((d) => {
      const r = w.entryOf.get(`${e._id}:${d}`);
      return !r || r.kind === 'usual' ? { kind: 'usual', shiftId: null } : { kind: r.kind, shiftId: r.shiftId ?? null };
    });
  const used = new Set(w.emps.flatMap((e) => w.days.map((d) => w.draftPlan(e, d)).filter((p) => p.kind === 'shift' && p.shiftId).map((p) => p.shiftId!)));
  const order = w.shifts.filter((s) => used.has(String(s._id))).map((s) => s._id);
  if (input.mode === 'rotate' && order.length < 2) throw new AppError('VALIDATION_ERROR', 'Use at least 2 shifts this week to swap them every week');
  for (const e of w.emps) {
    await RosterRepeat.updateOne(
      { companyId: ctx.companyId, employeeId: e._id },
      { $set: { mode: input.mode, startWeek: start, days: planOf(e), order, autoSend: !!input.autoSend, filled: [], createdBy: ctx.userId } },
      { upsert: true },
    );
  }
  // Weeks filled by an earlier repeat and not sent yet are filled again from this one.
  await clearUnsentRepeatDays(ctx, w.emps.map((e) => e._id), start);
  const next = DateTime.fromISO(start).plus({ weeks: 1 }).toISODate()!;
  const filled = await fillWeek(ctx, next);
  await audit(ctx, { action: 'roster.repeat_on', entity: 'roster', after: { weekStart: start, mode: input.mode, staff: w.emps.length, autoSend: !!input.autoSend } });
  return { staff: w.emps.length, mode: input.mode, nextWeek: next, filled: filled.days };
}

/** Turn repeat off for everyone in view; future days it filled in and nobody sent are removed. */
export async function turnOffRepeat(ctx: Ctx, branchId?: string) {
  const ids = (await staffInScope(ctx, branchId)).map((e) => e._id);
  const { deletedCount } = await RosterRepeat.deleteMany({ companyId: ctx.companyId, employeeId: { $in: ids } });
  if (!deletedCount) return { staff: 0 };
  const company = await Company.findById(ctx.companyId).select('timezone').lean();
  await clearUnsentRepeatDays(ctx, ids, todayIn(company!.timezone));
  await audit(ctx, { action: 'roster.repeat_off', entity: 'roster', after: { staff: deletedCount } });
  return { staff: deletedCount };
}

async function clearUnsentRepeatDays(ctx: Ctx, ids: Types.ObjectId[], after: string) {
  await RosterEntry.deleteMany({ companyId: ctx.companyId, employeeId: { $in: ids }, source: 'repeat', sent: null, date: { $gt: after } });
}

/** What the repeat gives [e] on day [i] of the week starting [weekStart]. */
function plannedDay(doc: any, w: Awaited<ReturnType<typeof loadWeek>>, e: any, i: number, weekStart: string): DayPlan {
  const d = w.days[i];
  const stored = doc.days[i] ?? { kind: 'usual' };
  const base: DayPlan = stored.kind === 'usual' ? w.usual(e, d) : { kind: stored.kind, shiftId: stored.shiftId ? String(stored.shiftId) : null };
  if (doc.mode !== 'rotate' || base.kind !== 'shift' || !base.shiftId) return base;
  const order = (doc.order ?? []).map(String);
  const at = order.indexOf(base.shiftId);
  if (at < 0 || order.length < 2) return base;
  const k = weeksBetween(doc.startWeek, weekStart);
  return { kind: 'shift', shiftId: order[(((at + k) % order.length) + order.length) % order.length] };
}

/**
 * Fill [weekStart] from the repeat, once per person and week, as not sent yet. Days the owner already
 * planned are kept, and days that match the usual shift need no entry.
 */
export async function fillWeek(ctx: Ctx, weekStart: string, opts: { branchId?: string } = {}) {
  const start = weekStartOf(weekStart);
  const ids = (await staffInScope(ctx, opts.branchId)).map((e) => e._id);
  const docs = await RosterRepeat.find({ companyId: ctx.companyId, employeeId: { $in: ids }, startWeek: { $lt: start }, filled: { $ne: start } }).lean();
  if (!docs.length) return { staff: 0, days: 0 };
  const w = await loadWeek(ctx, start, { employeeIds: docs.map((d) => d.employeeId) });
  const docOf = new Map(docs.map((d) => [String(d.employeeId), d]));
  let days = 0;
  for (const e of w.emps) {
    const doc = docOf.get(String(e._id))!;
    for (let i = 0; i < 7; i++) {
      const d = w.days[i];
      if (!employedOn(e, d) || w.entryOf.has(`${e._id}:${d}`)) continue;
      const plan = plannedDay(doc, w, e, i, start);
      if (same(plan, w.usual(e, d))) continue;
      const r = await RosterEntry.updateOne(
        { companyId: ctx.companyId, employeeId: e._id, date: d },
        { $setOnInsert: { kind: plan.kind, shiftId: plan.kind === 'shift' ? new Types.ObjectId(plan.shiftId!) : null, sent: null, source: 'repeat', updatedBy: ctx.userId } },
        { upsert: true },
      );
      if (r.upsertedCount) days++;
    }
  }
  await RosterRepeat.updateMany({ companyId: ctx.companyId, _id: { $in: docs.map((d) => d._id) } }, { $addToSet: { filled: start } });
  return { staff: docs.length, days };
}

/** Looking ahead at a future week fills it from the repeat first (up to a couple of months ahead). */
export async function fillIfAhead(ctx: Ctx, weekStart: string, branchId?: string) {
  const company = await Company.findById(ctx.companyId).select('timezone').lean();
  const thisWeek = weekStartOf(todayIn(company!.timezone));
  const ahead = weeksBetween(thisWeek, weekStart);
  if (ahead < 1 || ahead > FILL_AHEAD_WEEKS) return;
  if (!(await RosterRepeat.exists({ companyId: ctx.companyId }))) return;
  if (!(await canRepeat(ctx.companyId))) return;
  // Fill the weeks in between too, so a rotation lands the same however far ahead the owner jumps.
  for (let k = 1; k <= ahead; k++) await fillWeek(ctx, DateTime.fromISO(thisWeek).plus({ weeks: k }).toISODate()!, { branchId });
}
