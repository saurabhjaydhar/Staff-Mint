import { Types } from 'mongoose';
import { DateTime } from 'luxon';
import { AppError, notFound } from '../../lib/errors.js';
import { dateRange, todayIn } from '../../lib/dates.js';
import { isShiftOff, usualShiftResolver } from './days.js';
import type { Ctx } from '../../lib/context.js';
import { Attendance, Branch, Company, Employee, Holiday, Leave, RosterEntry, Shift } from '../../models/index.js';
import { employeeScope } from '../employees/service.js';
import { audit } from '../audit/service.js';
import { notifyEmployee } from '../notifications/service.js';
import { applyRules } from '../attendance/service.js';
import { shiftView } from '../views.js';
import { canRepeat, fillIfAhead, repeatInfo } from './repeat.js';

export type Kind = 'shift' | 'off';
export interface DayPlan {
  kind: Kind;
  shiftId: string | null;
}

/** Monday of the week that contains [date]. */
export const weekStartOf = (date: string) => DateTime.fromISO(date).startOf('week').toISODate()!;
export const weekDays = (start: string) => dateRange(start, DateTime.fromISO(start).plus({ days: 6 }).toISODate()!);
export const same = (a: DayPlan, b: DayPlan) => a.kind === b.kind && (a.kind === 'off' || a.shiftId === b.shiftId);
export const employedOn = (e: any, d: string) => (!e.joiningDate || e.joiningDate <= d) && (!e.exitDate || e.exitDate >= d);

/** Everything a week needs: people in scope, their usual shift and weekly off, roster rows, leave, holidays. */
export async function loadWeek(ctx: Ctx, start: string, opts: { branchId?: string; employeeIds?: Types.ObjectId[] } = {}) {
  const days = weekDays(start);
  const f: any = { ...employeeScope(ctx), status: 'active' };
  if (opts.branchId) f.branchId = new Types.ObjectId(opts.branchId);
  if (opts.employeeIds) f._id = { $in: opts.employeeIds };
  const emps = (await Employee.find(f).sort({ name: 1 }).lean()).filter((e) => days.some((d) => employedOn(e, d)));
  const ids = emps.map((e) => e._id);
  const [shifts, branches, entries, holidays, leaves] = await Promise.all([
    Shift.find({ companyId: ctx.companyId }).sort({ start: 1 }).lean(),
    Branch.find({ companyId: ctx.companyId }).lean(),
    RosterEntry.find({ companyId: ctx.companyId, employeeId: { $in: ids }, date: { $gte: days[0], $lte: days[6] } }).lean(),
    Holiday.find({ companyId: ctx.companyId, deletedAt: null, date: { $gte: days[0], $lte: days[6] } }).lean(),
    Leave.find({ companyId: ctx.companyId, employeeId: { $in: ids }, status: 'approved', deletedAt: null, from: { $lte: days[6] }, to: { $gte: days[0] } }).lean(),
  ]);
  const shiftById = new Map(shifts.map((s) => [String(s._id), s]));
  const usualShift = usualShiftResolver(shifts, branches);
  const usual = (e: any, d: string): DayPlan => {
    const sh = usualShift(e);
    return isShiftOff(sh, d) ? { kind: 'off', shiftId: null } : { kind: 'shift', shiftId: sh ? String(sh._id) : null };
  };
  const entryOf = new Map(entries.map((r) => [`${r.employeeId}:${r.date}`, r]));
  const holidayOn = new Map(holidays.map((h) => [h.date, h.name]));
  const leaveOn = new Map<string, string>();
  for (const l of leaves) for (const d of dateRange(l.from, l.to)) leaveOn.set(`${l.employeeId}:${d}`, l.type);
  /** What staff were last sent for the day (or their usual plan). */
  const sentPlan = (e: any, d: string): DayPlan => {
    const r = entryOf.get(`${e._id}:${d}`);
    return r?.sent ? { kind: r.sent.kind as Kind, shiftId: r.sent.shiftId ? String(r.sent.shiftId) : null } : usual(e, d);
  };
  /** What the owner has set now, sent or not. */
  const draftPlan = (e: any, d: string): DayPlan => {
    const r = entryOf.get(`${e._id}:${d}`);
    if (!r || r.kind === 'usual') return usual(e, d);
    return { kind: r.kind as Kind, shiftId: r.shiftId ? String(r.shiftId) : null };
  };
  return { days, emps, shifts, shiftById, entryOf, holidayOn, leaveOn, usual, sentPlan, draftPlan };
}

/** Owner/manager: the week, one row per person, with what isn't sent yet and what needs a look. */
export async function weekView(ctx: Ctx, date: string, branchId?: string) {
  const start = weekStartOf(date);
  await fillIfAhead(ctx, start, branchId);
  const w = await loadWeek(ctx, start, { branchId });
  const problems: { type: 'leave_working' | 'no_day_off'; employeeId: string; name: string; date: string }[] = [];
  let notSent = 0;
  const staff = w.emps.map((e) => {
    const cells = w.days.map((d) => {
      const draft = w.draftPlan(e, d);
      const changed = w.entryOf.has(`${e._id}:${d}`) && !same(draft, w.sentPlan(e, d));
      if (changed) notSent++;
      const leave = w.leaveOn.get(`${e._id}:${d}`) ?? null;
      const holiday = w.holidayOn.get(d) ?? null;
      if (leave && draft.kind === 'shift' && !holiday) problems.push({ type: 'leave_working', employeeId: String(e._id), name: e.name, date: d });
      return { date: d, ...draft, usual: !w.entryOf.has(`${e._id}:${d}`) || w.entryOf.get(`${e._id}:${d}`)!.kind === 'usual', changed, leave, employed: employedOn(e, d) };
    });
    const working = cells.filter((c) => c.employed && c.kind === 'shift' && !c.leave && !w.holidayOn.get(c.date)).length;
    const employedDays = cells.filter((c) => c.employed).length;
    if (employedDays === 7 && working === 7) problems.push({ type: 'no_day_off', employeeId: String(e._id), name: e.name, date: w.days[6] });
    return { id: String(e._id), name: e.name, designation: e.designation ?? null, cells };
  });
  return {
    weekStart: start,
    days: w.days.map((d) => ({ date: d, holiday: w.holidayOn.get(d) ?? null })),
    shifts: w.shifts.map(shiftView),
    staff,
    notSent,
    problems,
    repeat: await repeatInfo(ctx, branchId),
    repeatAllowed: await canRepeat(ctx.companyId),
  };
}

export interface CellInput {
  employeeId: string;
  date: string;
  kind: 'shift' | 'off' | 'usual';
  shiftId?: string | null;
}

/** Save changes as not-sent-yet. "usual" puts the day back to the person's usual shift. */
export async function setCells(ctx: Ctx, cells: CellInput[]) {
  if (!cells.length) return { saved: 0 };
  const ids = [...new Set(cells.map((c) => c.employeeId))];
  const inScope = await Employee.find({ ...employeeScope(ctx), _id: { $in: ids } }).select('_id').lean();
  if (inScope.length !== ids.length) throw notFound('Employee');
  const shiftIds = [...new Set(cells.filter((c) => c.kind === 'shift').map((c) => String(c.shiftId ?? '')))];
  if (shiftIds.some((s) => !Types.ObjectId.isValid(s))) throw new AppError('VALIDATION_ERROR', 'Pick a shift');
  if ((await Shift.countDocuments({ companyId: ctx.companyId, _id: { $in: shiftIds } })) !== shiftIds.length) throw notFound('Shift');
  for (const c of cells) {
    const key = { companyId: ctx.companyId, employeeId: new Types.ObjectId(c.employeeId), date: c.date };
    if (c.kind === 'usual') {
      // Nothing was ever sent for this day: forget it. Otherwise remember to send "back to usual".
      await RosterEntry.deleteOne({ ...key, sent: null });
      await RosterEntry.updateOne(key, { $set: { kind: 'usual', shiftId: null, source: 'owner', updatedBy: ctx.userId } });
      continue;
    }
    await RosterEntry.updateOne(
      key,
      { $set: { kind: c.kind, shiftId: c.kind === 'shift' ? new Types.ObjectId(c.shiftId!) : null, source: 'owner', updatedBy: ctx.userId }, $setOnInsert: { sent: null } },
      { upsert: true },
    );
  }
  return { saved: cells.length };
}

/** Copy last week's roster days onto this week (same weekday), as not sent yet. */
export async function copyLastWeek(ctx: Ctx, date: string, branchId?: string) {
  const start = weekStartOf(date);
  const prevStart = DateTime.fromISO(start).minus({ weeks: 1 }).toISODate()!;
  const prev = await loadWeek(ctx, prevStart, { branchId });
  const cells: CellInput[] = [];
  for (const e of prev.emps) {
    prev.days.forEach((d, i) => {
      const r = prev.entryOf.get(`${e._id}:${d}`);
      if (!r) return; // usual both weeks: nothing to copy
      const plan = prev.draftPlan(e, d);
      const target = DateTime.fromISO(start).plus({ days: i }).toISODate()!;
      cells.push({ employeeId: String(e._id), date: target, kind: plan.kind, shiftId: plan.shiftId });
    });
  }
  await setCells(ctx, cells);
  return { copied: cells.length };
}

/**
 * Send the week to staff: changes become what attendance and salary use, the people whose days changed
 * are told, and days already worked are re-checked against the new shift.
 */
export async function sendWeek(ctx: Ctx, date: string, branchId?: string) {
  const start = weekStartOf(date);
  const w = await loadWeek(ctx, start, { branchId });
  const company = await Company.findById(ctx.companyId).lean();
  const today = todayIn(company!.timezone);
  const changedBy = new Map<string, { emp: any; days: string[] }>();
  const now = new Date();
  for (const e of w.emps) {
    for (const d of w.days) {
      const r = w.entryOf.get(`${e._id}:${d}`);
      if (!r) continue;
      const draft = w.draftPlan(e, d);
      const differs = !same(draft, w.sentPlan(e, d));
      if (r.kind === 'usual') await RosterEntry.deleteOne({ _id: r._id, companyId: ctx.companyId });
      else if (differs || !r.sent) await RosterEntry.updateOne({ _id: r._id, companyId: ctx.companyId }, { $set: { sent: { kind: r.kind, shiftId: r.shiftId ?? null, at: now } } });
      if (!differs) continue;
      const c = changedBy.get(String(e._id)) ?? { emp: e, days: [] };
      c.days.push(d);
      changedBy.set(String(e._id), c);
      // A day already worked: late / half day follow the new shift.
      if (d <= today) {
        const rec = await Attendance.findOne({ companyId: ctx.companyId, employeeId: e._id, date: d });
        if (rec && rec.punches.length && !rec.overridden) {
          const sh = draft.kind === 'shift' && draft.shiftId ? w.shiftById.get(draft.shiftId) : w.shiftById.get(w.usual(e, d).shiftId ?? '');
          applyRules(rec, company, sh, d < today);
          await rec.save();
        }
      }
    }
  }
  const label = `${DateTime.fromISO(w.days[0]).toFormat('d LLL')} – ${DateTime.fromISO(w.days[6]).toFormat('d LLL')}`;
  for (const { emp, days } of changedBy.values()) {
    const lines = w.days
      .map((d) => {
        const p = w.draftPlan(emp, d);
        const sh = p.kind === 'shift' && p.shiftId ? w.shiftById.get(p.shiftId) : null;
        return `${DateTime.fromISO(d).toFormat('ccc d')} ${sh ? `${sh.name} ${sh.start}–${sh.end}` : 'Off'}${days.includes(d) ? ' (changed)' : ''}`;
      })
      // WhatsApp template values can't hold line breaks.
      .join(' · ');
    await notifyEmployee(
      ctx.companyId,
      emp._id,
      {
        template: 'roster_published',
        title: `Your shifts for ${label}`,
        titleHi: `${label} की आपकी शिफ़्ट`,
        body: days.length === 1 ? `1 day changed. Open the app to see your week.` : `${days.length} days changed. Open the app to see your week.`,
        bodyHi: `${days.length} दिन बदले। अपना हफ़्ता देखने के लिए ऐप खोलें।`,
        data: { type: 'roster', weekStart: start },
        whatsapp: { template: 'roster_published', params: [emp.name, company!.name, label, lines] },
      },
      // Staff with the app get a push; WhatsApp only for those who haven't joined yet.
      { whatsapp: !emp.userId },
    );
  }
  const changedDays = [...changedBy.values()].reduce((n, c) => n + c.days.length, 0);
  if (changedDays) await audit(ctx, { action: 'roster.send', entity: 'roster', after: { weekStart: start, staff: changedBy.size, days: changedDays } });
  return { sentTo: changedBy.size, days: changedDays };
}

/** Staff: their own week as sent (roster days, usual shift otherwise), with holidays and leave. */
export async function myWeek(ctx: Ctx, date: string) {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Staff only');
  const start = weekStartOf(date);
  const w = await loadWeek(ctx, start, { employeeIds: [ctx.employeeId] });
  const e = w.emps[0];
  const recent = Date.now() - 3 * 86400_000;
  return {
    weekStart: start,
    /** True when the owner sent a roster touching this week; the app shows "My week" only then. */
    rostered: !!e && w.days.some((d) => !!w.entryOf.get(`${e._id}:${d}`)?.sent),
    shifts: w.shifts.map(shiftView),
    days: w.days.map((d) => {
      const p = e ? w.sentPlan(e, d) : { kind: 'off' as Kind, shiftId: null };
      const r = e ? w.entryOf.get(`${e._id}:${d}`) : null;
      return {
        date: d,
        ...p,
        holiday: w.holidayOn.get(d) ?? null,
        leave: e ? (w.leaveOn.get(`${e._id}:${d}`) ?? null) : null,
        /** Sent in the last 3 days and different from their usual day: the app highlights it. */
        changed: !!(r?.sent?.at && r.sent.at.getTime() > recent) && (() => {
          const u = w.usual(e!, d);
          return u.kind !== p.kind || (p.kind === 'shift' && u.shiftId !== p.shiftId);
        })(),
      };
    }),
  };
}
