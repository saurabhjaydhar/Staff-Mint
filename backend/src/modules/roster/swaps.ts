import { Types } from 'mongoose';
import { DateTime } from 'luxon';
import { AppError, notFound } from '../../lib/errors.js';
import { todayIn } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Attendance, Company, Employee, RosterEntry, RosterSwap } from '../../models/index.js';
import { employeeScope } from '../employees/service.js';
import { audit } from '../audit/service.js';
import { notifyEmployee, notifyOwners } from '../notifications/service.js';
import { applyRules } from '../attendance/service.js';
import { employedOn, loadWeek, same, weekStartOf, type DayPlan } from './service.js';

/** How far ahead staff can ask for a swap. */
const SWAP_AHEAD_DAYS = 56;

const plan = (p: { kind?: string | null; shiftId?: unknown }): DayPlan => ({ kind: p.kind as DayPlan['kind'], shiftId: p.shiftId ? String(p.shiftId) : null });
const toDoc = (p: DayPlan) => ({ kind: p.kind, shiftId: p.shiftId ? new Types.ObjectId(p.shiftId) : null });
const nice = (d: string, hi = false) => DateTime.fromISO(d).setLocale(hi ? 'hi' : 'en').toFormat(hi ? 'cccc, d LLLL' : 'ccc d LLL');

async function today(companyId: Types.ObjectId) {
  return todayIn((await Company.findById(companyId).select('timezone').lean())!.timezone);
}

/** What staff were sent for [date] (or their usual day), for several people at once. */
async function sentPlans(ctx: Ctx, date: string, employeeIds: Types.ObjectId[]) {
  const w = await loadWeek(ctx, weekStartOf(date), { employeeIds });
  return {
    w,
    planOf: (e: any) => w.sentPlan(e, date),
    leaveOf: (e: any) => w.leaveOn.get(`${e._id}:${date}`) ?? null,
  };
}

function label(w: Awaited<ReturnType<typeof loadWeek>>, p: DayPlan, hi = false) {
  if (p.kind === 'off') return hi ? 'छुट्टी' : 'Day off';
  const sh = w.shiftById.get(p.shiftId ?? '');
  return sh ? `${sh.name} ${sh.start}–${sh.end}` : hi ? 'शिफ़्ट' : 'Shift';
}

/** Staff: colleagues they could swap [date] with, and what each would give them. */
export async function swapOptions(ctx: Ctx, date: string) {
  const me = await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId }).lean();
  if (!me) throw notFound('Employee');
  // Swaps stay inside one branch.
  const f: Record<string, unknown> = { companyId: ctx.companyId, deletedAt: null, status: 'active', _id: { $ne: me._id }, branchId: me.branchId ?? null };
  const others = await Employee.find(f).sort({ name: 1 }).lean();
  const { w, planOf, leaveOf } = await sentPlans(ctx, date, [me._id, ...others.map((o) => o._id)]);
  const mine = planOf(me);
  return {
    date,
    mine: { ...mine, label: label(w, mine, ctx.language === 'hi') },
    colleagues: w.emps
      .filter((e) => String(e._id) !== String(me._id) && employedOn(e, date) && !leaveOf(e))
      .map((e) => ({ employeeId: String(e._id), name: e.name, ...planOf(e), label: label(w, planOf(e), ctx.language === 'hi') }))
      .filter((c) => !same(c, mine)),
  };
}

/** Staff asks a colleague to swap one day. */
export async function askSwap(ctx: Ctx, input: { date: string; withEmployeeId: string; note?: string }) {
  const t = await today(ctx.companyId);
  if (input.date < t) throw new AppError('VALIDATION_ERROR', 'That day has passed');
  if (input.date > DateTime.fromISO(t).plus({ days: SWAP_AHEAD_DAYS }).toISODate()!) throw new AppError('VALIDATION_ERROR', 'Pick a day in the next 8 weeks');
  const options = await swapOptions(ctx, input.date);
  const other = options.colleagues.find((c) => c.employeeId === input.withEmployeeId);
  if (!other) throw new AppError('VALIDATION_ERROR', 'You can’t swap this day with them');
  const both = [ctx.employeeId!, new Types.ObjectId(other.employeeId)];
  const open = await RosterSwap.exists({
    companyId: ctx.companyId,
    date: input.date,
    status: { $in: ['asked', 'accepted'] },
    $or: [{ fromEmployeeId: { $in: both } }, { toEmployeeId: { $in: both } }],
  });
  if (open) throw new AppError('CONFLICT', 'There is already a swap asked for this day');
  const me = (await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId }).select('name').lean())!;
  const swap = await RosterSwap.create({
    companyId: ctx.companyId,
    date: input.date,
    fromEmployeeId: ctx.employeeId!,
    toEmployeeId: other.employeeId,
    fromPlan: toDoc(options.mine),
    toPlan: toDoc(other),
    note: input.note ?? null,
  });
  await notifyEmployee(ctx.companyId, new Types.ObjectId(other.employeeId), {
    template: 'roster_swap_asked',
    title: `${me.name} wants to swap ${nice(input.date)}`,
    titleHi: `${me.name} ${nice(input.date, true)} की शिफ़्ट बदलना चाहते हैं`,
    body: `You'd work ${options.mine.label}; they'd take your ${other.label}. Open the app to answer.`,
    bodyHi: `आपको ${options.mine.label} करनी होगी, वे आपकी ${other.label} लेंगे। जवाब देने के लिए ऐप खोलें।`,
    data: { type: 'roster_swap', swapId: String(swap._id) },
  });
  return swapView(swap, { [String(ctx.employeeId)]: me.name, [other.employeeId]: other.name });
}

async function load(ctx: Ctx, id: string) {
  if (!Types.ObjectId.isValid(id)) throw notFound('Swap');
  const s = await RosterSwap.findOne({ _id: id, companyId: ctx.companyId });
  if (!s) throw notFound('Swap');
  if (s.date < (await today(ctx.companyId)) && ['asked', 'accepted'].includes(s.status)) throw new AppError('CONFLICT', 'That day has passed');
  return s;
}

/** The colleague answers. Accepting sends it to the owner or manager. */
export async function answerSwap(ctx: Ctx, id: string, accept: boolean) {
  const s = await load(ctx, id);
  if (String(s.toEmployeeId) !== String(ctx.employeeId)) throw notFound('Swap');
  if (s.status !== 'asked') throw new AppError('CONFLICT', 'This swap was already answered');
  s.status = accept ? 'accepted' : 'declined';
  await s.save();
  const names = await namesOf(ctx, [s.fromEmployeeId, s.toEmployeeId]);
  const [from, to] = [names[String(s.fromEmployeeId)], names[String(s.toEmployeeId)]];
  if (accept) {
    await notifyOwners(ctx.companyId, {
      template: 'roster_swap_approval',
      title: `${from} and ${to} want to swap ${nice(s.date)}`,
      titleHi: `${from} और ${to} ${nice(s.date, true)} की शिफ़्ट बदलना चाहते हैं`,
      body: 'Approve or reject it in Roster.',
      bodyHi: 'रोस्टर में मंज़ूर या नामंज़ूर करें।',
      data: { type: 'roster_swap', swapId: String(s._id), weekStart: weekStartOf(s.date) },
    });
  } else {
    await notifyEmployee(ctx.companyId, s.fromEmployeeId, {
      template: 'roster_swap_declined',
      title: `${to} can’t swap ${nice(s.date)}`,
      titleHi: `${to} ${nice(s.date, true)} की शिफ़्ट नहीं बदल सकते`,
      body: 'Your shift stays the same. You can ask someone else.',
      bodyHi: 'आपकी शिफ़्ट वही रहेगी। किसी और से पूछ सकते हैं।',
      data: { type: 'roster_swap', swapId: String(s._id) },
    });
  }
  return swapView(s, names);
}

/** The asker takes it back before it's approved. */
export async function cancelSwap(ctx: Ctx, id: string) {
  const s = await load(ctx, id);
  if (String(s.fromEmployeeId) !== String(ctx.employeeId)) throw notFound('Swap');
  if (!['asked', 'accepted'].includes(s.status)) throw new AppError('CONFLICT', 'This swap is already closed');
  s.status = 'cancelled';
  await s.save();
  return swapView(s, await namesOf(ctx, [s.fromEmployeeId, s.toEmployeeId]));
}

/**
 * Owner or manager decides. Approving checks both still have the day they asked about, then swaps it
 * straight away (sent: attendance and salary follow it) and tells both.
 */
export async function decideSwap(ctx: Ctx, id: string, approve: boolean) {
  const s = await load(ctx, id);
  const inScope = await Employee.countDocuments({ ...employeeScope(ctx), _id: { $in: [s.fromEmployeeId, s.toEmployeeId] } });
  if (inScope !== 2) throw notFound('Swap');
  if (s.status !== 'accepted') throw new AppError('CONFLICT', s.status === 'asked' ? 'Waiting for the colleague to accept' : 'This swap is already closed');
  const names = await namesOf(ctx, [s.fromEmployeeId, s.toEmployeeId]);
  const [from, to] = [names[String(s.fromEmployeeId)], names[String(s.toEmployeeId)]];
  if (!approve) {
    Object.assign(s, { status: 'rejected', decidedBy: ctx.userId, decidedAt: new Date() });
    await s.save();
    for (const id of [s.fromEmployeeId, s.toEmployeeId]) {
      await notifyEmployee(ctx.companyId, id, {
        template: 'roster_swap_rejected',
        title: `Swap on ${nice(s.date)} not approved`,
        titleHi: `${nice(s.date, true)} की अदला-बदली मंज़ूर नहीं हुई`,
        body: 'Your shifts stay as they were.',
        bodyHi: 'आपकी शिफ़्ट पहले जैसी रहेगी।',
        data: { type: 'roster_swap', swapId: String(s._id) },
      });
    }
    await audit(ctx, { action: 'roster.swap_rejected', entity: 'roster', after: { date: s.date, from, to } });
    return swapView(s, names);
  }
  const emps = await Employee.find({ companyId: ctx.companyId, _id: { $in: [s.fromEmployeeId, s.toEmployeeId] } }).lean();
  const { w, planOf, leaveOf } = await sentPlans(ctx, s.date, emps.map((e) => e._id));
  const fromEmp = w.emps.find((e) => String(e._id) === String(s.fromEmployeeId));
  const toEmp = w.emps.find((e) => String(e._id) === String(s.toEmployeeId));
  if (!fromEmp || !toEmp || leaveOf(fromEmp) || leaveOf(toEmp) || !same(planOf(fromEmp), plan(s.fromPlan)) || !same(planOf(toEmp), plan(s.toPlan))) {
    throw new AppError('CONFLICT', 'Their shifts changed since they asked. Ask them to swap again.');
  }
  const company = await Company.findById(ctx.companyId).lean();
  const t = todayIn(company!.timezone);
  const now = new Date();
  for (const [emp, next] of [
    [fromEmp, plan(s.toPlan)],
    [toEmp, plan(s.fromPlan)],
  ] as const) {
    const doc = toDoc(next);
    await RosterEntry.updateOne(
      { companyId: ctx.companyId, employeeId: emp._id, date: s.date },
      { $set: { ...doc, sent: { ...doc, at: now }, source: 'owner', updatedBy: ctx.userId } },
      { upsert: true },
    );
    // Swapped on the day itself, after someone already checked in: late / half day follow the new shift.
    if (s.date === t) {
      const rec = await Attendance.findOne({ companyId: ctx.companyId, employeeId: emp._id, date: s.date });
      if (rec && rec.punches.length && !rec.overridden) {
        applyRules(rec, company, w.shiftById.get(next.kind === 'shift' ? next.shiftId! : (w.usual(emp, s.date).shiftId ?? '')), false);
        await rec.save();
      }
    }
    await notifyEmployee(ctx.companyId, emp._id, {
      template: 'roster_swap_approved',
      title: `Swap approved for ${nice(s.date)}`,
      titleHi: `${nice(s.date, true)} की अदला-बदली मंज़ूर`,
      body: `You now work ${label(w, next)} that day.`,
      bodyHi: `उस दिन अब आपकी ${label(w, next, true)} है।`,
      data: { type: 'roster', weekStart: weekStartOf(s.date) },
    });
  }
  Object.assign(s, { status: 'approved', decidedBy: ctx.userId, decidedAt: now });
  await s.save();
  await audit(ctx, { action: 'roster.swap_approved', entity: 'roster', after: { date: s.date, from, to } });
  return swapView(s, names);
}

/** Staff: swaps they asked for or were asked. Owner/manager: swaps waiting for approval, plus recent ones. */
export async function listSwaps(ctx: Ctx) {
  const t = await today(ctx.companyId);
  const recent = DateTime.fromISO(t).minus({ days: 14 }).toISODate()!;
  let f: any;
  if (ctx.role === 'employee') {
    f = { companyId: ctx.companyId, date: { $gte: recent }, $or: [{ fromEmployeeId: ctx.employeeId }, { toEmployeeId: ctx.employeeId }] };
  } else {
    const ids = (await Employee.find(employeeScope(ctx)).select('_id').lean()).map((e) => e._id);
    f = { companyId: ctx.companyId, date: { $gte: recent }, fromEmployeeId: { $in: ids }, toEmployeeId: { $in: ids } };
  }
  const list = await RosterSwap.find(f).sort({ date: 1, createdAt: -1 }).limit(100).lean();
  const names = await namesOf(ctx, list.flatMap((s) => [s.fromEmployeeId, s.toEmployeeId]));
  const views = list.map((s) => swapView(s, names, t));
  // Only show answered-and-closed swaps for a couple of weeks; open ones for days that passed are gone.
  return views.filter((v) => v.status !== 'expired');
}

async function namesOf(ctx: Ctx, ids: Types.ObjectId[]) {
  const emps = await Employee.find({ companyId: ctx.companyId, _id: { $in: ids } }).select('name').lean();
  return Object.fromEntries(emps.map((e) => [String(e._id), e.name]));
}

function swapView(s: any, names: Record<string, string>, today?: string) {
  const open = ['asked', 'accepted'].includes(s.status);
  return {
    id: String(s._id),
    date: s.date,
    from: { employeeId: String(s.fromEmployeeId), name: names[String(s.fromEmployeeId)] ?? '', ...plan(s.fromPlan) },
    to: { employeeId: String(s.toEmployeeId), name: names[String(s.toEmployeeId)] ?? '', ...plan(s.toPlan) },
    status: open && today && s.date < today ? 'expired' : (s.status as string),
    note: s.note ?? null,
    createdAt: s.createdAt,
  };
}
