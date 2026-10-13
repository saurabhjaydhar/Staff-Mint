import { describe, expect, it } from 'vitest';
import { Types } from 'mongoose';
import { DateTime } from 'luxon';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks, setPlan } from './helpers.js';
import { AuditLog, Holiday, Notification, RosterEntry } from '../src/models/index.js';
import { dayContext } from '../src/modules/attendance/service.js';
import { todayIn } from '../src/lib/dates.js';

const TZ = 'Asia/Kolkata';
const thisWeek = () => DateTime.fromISO(todayIn(TZ)).startOf('week');
const weekAt = (k: number) => thisWeek().plus({ weeks: k }).toISODate()!;
const dayOf = (week: string, i: number) => DateTime.fromISO(week).plus({ days: i }).toISODate()!;
const tomorrow = () => DateTime.fromISO(todayIn(TZ)).plus({ days: 1 }).toISODate()!;

async function shift(token: string, body: Record<string, unknown>) {
  return (await api().post(`${V}/shifts`).set(auth(token)).send({ weeklyOff: [0], ...body }).expect(201)).body.data;
}
const week = async (token: string, w: string) => (await api().get(`${V}/roster?week=${w}`).set(auth(token)).expect(200)).body.data;
const put = (token: string, cells: any[]) => api().put(`${V}/roster/cells`).set(auth(token)).send({ cells }).expect(200);
const send = (token: string, w: string) => api().post(`${V}/roster/send`).set(auth(token)).send({ week: w }).expect(200);

describe('roster checks before sending', () => {
  it('flags short rest, a long week and a shift below its minimum, but only for planned weeks', async () => {
    const owner = await createOwner({ plan: 'pro' }); // usual 09:00–18:00 × 6 = 54 h: not flagged, never planned
    // Festival holidays depend on the week the test runs in; this test wants a plain week.
    await Holiday.deleteMany({ companyId: owner.companyId });
    const night = await shift(owner.token, { name: 'Night', start: '22:00', end: '06:00' });
    const morning = await shift(owner.token, { name: 'Morning', start: '08:00', end: '14:00', minStaff: 2 });
    const long = await shift(owner.token, { name: 'Long', start: '08:00', end: '18:00' });
    expect(morning.minStaff).toBe(2);
    const a = await addEmployee(owner, { name: 'Raju', joiningDate: '2026-01-01' });
    const b = await addEmployee(owner, { name: 'Pooja', joiningDate: '2026-01-01' });
    const c = await addEmployee(owner, { name: 'Amit', joiningDate: '2026-01-01' });
    const w = weekAt(1);
    await put(owner.token, [
      { employeeId: a.id, date: dayOf(w, 0), kind: 'shift', shiftId: night.id },
      { employeeId: a.id, date: dayOf(w, 1), kind: 'shift', shiftId: morning.id },
      ...[0, 1, 2, 3, 4, 5].map((i) => ({ employeeId: b.id, date: dayOf(w, i), kind: 'shift', shiftId: long.id })),
    ]);
    const v = await week(owner.token, w);
    expect(v.problems).toEqual(
      expect.arrayContaining([
        { type: 'short_rest', employeeId: a.id, name: 'Raju', date: dayOf(w, 1), hours: 2 },
        { type: 'long_week', employeeId: b.id, name: 'Pooja', date: dayOf(w, 6), hours: 60 },
        // Tuesday: Raju alone on Morning, the shop wants 2.
        { type: 'short_staff', date: dayOf(w, 1), shiftId: morning.id, shiftName: 'Morning', count: 1, min: 2 },
        // Monday nobody is on Morning, while the shop is open.
        { type: 'short_staff', date: dayOf(w, 0), shiftId: morning.id, shiftName: 'Morning', count: 0, min: 2 },
      ]),
    );
    // Amit's usual week (never planned) isn't flagged, and Sunday (everyone off) isn't counted.
    expect(v.problems.filter((p: any) => p.employeeId === c.id)).toEqual([]);
    expect(v.problems.find((p: any) => p.type === 'short_staff' && p.date === dayOf(w, 6))).toBeUndefined();
    // Warnings never stop sending.
    expect((await send(owner.token, w)).body.data.sentTo).toBe(2);
  });

  it('staff who already had the week are told "your shift changed" with just the changed days', async () => {
    const { messaging } = await mocks();
    const owner = await createOwner({ plan: 'pro' });
    const evening = await shift(owner.token, { name: 'Evening', start: '14:00', end: '21:00' });
    const a = await addEmployee(owner, { name: 'Raju', joiningDate: '2026-01-01' }); // no app: WhatsApp
    const w = weekAt(1);
    await put(owner.token, [{ employeeId: a.id, date: dayOf(w, 0), kind: 'shift', shiftId: evening.id }]);
    await send(owner.token, w);
    expect(messaging.outbox.at(-1)).toMatchObject({ template: 'roster_published' });
    await put(owner.token, [{ employeeId: a.id, date: dayOf(w, 2), kind: 'off' }]);
    await send(owner.token, w);
    const last = messaging.outbox.at(-1)!;
    expect(last.template).toBe('roster_changed');
    expect(last.params?.[3]).toMatch(/^Wed \d+ Off$/);
  });
});

describe('shift swaps', () => {
  async function setup(plan = 'pro') {
    const owner = await createOwner({ plan });
    const morning = await shift(owner.token, { name: 'Morning', start: '08:00', end: '14:00' });
    const evening = await shift(owner.token, { name: 'Evening', start: '14:00', end: '21:00' });
    const [pa, pb] = [nextPhone(), nextPhone()];
    const a = await addEmployee(owner, { name: 'Raju', phone: pa, joiningDate: '2026-01-01' });
    const b = await addEmployee(owner, { name: 'Pooja', phone: pb, joiningDate: '2026-01-01' });
    const day = dayOf(weekAt(1), 2); // next Wednesday
    await put(owner.token, [
      { employeeId: a.id, date: day, kind: 'shift', shiftId: morning.id },
      { employeeId: b.id, date: day, kind: 'shift', shiftId: evening.id },
    ]);
    await send(owner.token, weekAt(1));
    const [sa, sb] = [await employeeSession(pa), await employeeSession(pb)];
    return { owner, morning, evening, a, b, day, sa, sb };
  }

  it('ask → colleague accepts → owner approves: both days swap and count for salary', async () => {
    const { owner, morning, evening, a, b, day, sa, sb } = await setup();
    const opts = (await api().get(`${V}/roster/swap-options?date=${day}`).set(auth(sa.token)).expect(200)).body.data;
    expect(opts.mine).toMatchObject({ kind: 'shift', shiftId: morning.id, label: 'Morning 08:00–14:00' });
    expect(opts.colleagues).toEqual([expect.objectContaining({ employeeId: b.id, name: 'Pooja', shiftId: evening.id })]);

    const asked = (await api().post(`${V}/roster/swaps`).set(auth(sa.token)).send({ date: day, withEmployeeId: b.id }).expect(201)).body.data;
    expect(asked).toMatchObject({ status: 'asked', from: { name: 'Raju', shiftId: morning.id }, to: { name: 'Pooja', shiftId: evening.id } });
    expect(await Notification.exists({ companyId: owner.companyId, template: 'roster_swap_asked', employeeId: b.id })).toBeTruthy();
    // Asking twice for the same day is refused.
    expect((await api().post(`${V}/roster/swaps`).set(auth(sa.token)).send({ date: day, withEmployeeId: b.id })).status).toBe(409);
    // The owner can't approve before the colleague accepts; the asker can't accept for them.
    expect((await api().post(`${V}/roster/swaps/${asked.id}/approve`).set(auth(owner.token))).status).toBe(409);
    expect((await api().post(`${V}/roster/swaps/${asked.id}/accept`).set(auth(sa.token))).status).toBe(404);

    expect((await api().get(`${V}/roster/swaps`).set(auth(sb.token)).expect(200)).body.data).toEqual([expect.objectContaining({ id: asked.id, status: 'asked' })]);
    await api().post(`${V}/roster/swaps/${asked.id}/accept`).set(auth(sb.token)).expect(200);
    expect(await Notification.exists({ companyId: owner.companyId, template: 'roster_swap_approval' })).toBeTruthy();
    const pending = (await api().get(`${V}/roster/swaps`).set(auth(owner.token)).expect(200)).body.data;
    expect(pending).toEqual([expect.objectContaining({ id: asked.id, status: 'accepted' })]);
    // Staff can't approve.
    expect((await api().post(`${V}/roster/swaps/${asked.id}/approve`).set(auth(sb.token))).status).toBe(403);

    const done = (await api().post(`${V}/roster/swaps/${asked.id}/approve`).set(auth(owner.token)).expect(200)).body.data;
    expect(done.status).toBe('approved');
    const entries = await RosterEntry.find({ companyId: owner.companyId, date: day }).lean();
    const byEmp = Object.fromEntries(entries.map((r) => [String(r.employeeId), r]));
    expect(byEmp[a.id].sent).toMatchObject({ kind: 'shift' });
    expect(String(byEmp[a.id].sent!.shiftId)).toBe(evening.id);
    expect(String(byEmp[b.id].sent!.shiftId)).toBe(morning.id);
    // Attendance and salary use the swapped shifts.
    const dc = await dayContext(new Types.ObjectId(owner.companyId), day, day, [new Types.ObjectId(a.id)]);
    expect(String(dc.shiftOf({ _id: new Types.ObjectId(a.id) }, day)!._id)).toBe(evening.id);
    expect(await Notification.countDocuments({ companyId: owner.companyId, template: 'roster_swap_approved' })).toBeGreaterThanOrEqual(2);
    expect(await AuditLog.exists({ companyId: owner.companyId, action: 'roster.swap_approved' })).toBeTruthy();
    // The owner's week shows it as sent.
    const v = await week(owner.token, weekAt(1));
    const cell = v.staff.find((s: any) => s.id === a.id).cells.find((c: any) => c.date === day);
    expect(cell).toMatchObject({ shiftId: evening.id, changed: false });
  });

  it('declined, cancelled, and approval after the shifts changed', async () => {
    const { owner, a, b, day, sa, sb } = await setup();
    const ask = async () => (await api().post(`${V}/roster/swaps`).set(auth(sa.token)).send({ date: day, withEmployeeId: b.id }).expect(201)).body.data;
    const s1 = await ask();
    expect((await api().post(`${V}/roster/swaps/${s1.id}/decline`).set(auth(sb.token)).expect(200)).body.data.status).toBe('declined');
    expect(await Notification.exists({ companyId: owner.companyId, template: 'roster_swap_declined', employeeId: a.id })).toBeTruthy();
    const s2 = await ask();
    expect((await api().post(`${V}/roster/swaps/${s2.id}/cancel`).set(auth(sa.token)).expect(200)).body.data.status).toBe('cancelled');
    const s3 = await ask();
    await api().post(`${V}/roster/swaps/${s3.id}/accept`).set(auth(sb.token)).expect(200);
    // The owner changes Raju's day and sends it before deciding.
    await put(owner.token, [{ employeeId: a.id, date: day, kind: 'off' }]);
    await send(owner.token, weekAt(1));
    const r = await api().post(`${V}/roster/swaps/${s3.id}/approve`).set(auth(owner.token));
    expect(r.status).toBe(409);
    expect(r.body.error.message).toMatch(/changed since they asked/);
    expect((await api().post(`${V}/roster/swaps/${s3.id}/reject`).set(auth(owner.token)).expect(200)).body.data.status).toBe('rejected');
  });

  it('swaps are on Growth and up', async () => {
    const { owner, day, sa } = await setup();
    await setPlan(owner.companyId, 'starter');
    const r = await api().get(`${V}/roster/swap-options?date=${day}`).set(auth(sa.token));
    expect(r.status).toBe(402);
    expect((await api().get(`${V}/roster/mine`).set(auth(sa.token)).expect(200)).body.data.swapsAllowed).toBe(false);
  });
});

describe('Mint roster commands', () => {
  const say = (token: string, text: string, sessionId?: string) => api().post(`${V}/assistant/message`).set(auth(token)).send({ text, sessionId });
  const act = (token: string, id: string) => api().post(`${V}/assistant/confirm`).set(auth(token)).send({ pendingActionId: id, action: 'confirm' });

  it('"Raju ko kal evening shift do" changes and sends it; "kal kaun kaam par hai" lists the day', async () => {
    const owner = await createOwner({ plan: 'pro' });
    const evening = await shift(owner.token, { name: 'Evening', start: '14:00', end: '21:00' });
    const raju = await addEmployee(owner, { name: 'Raju', joiningDate: '2026-01-01' });
    await addEmployee(owner, { name: 'Pooja Singh', joiningDate: '2026-01-01' });
    const r = await say(owner.token, 'Raju ko kal evening shift do');
    expect(r.body.data).toMatchObject({ kind: 'confirm', intent: 'set_shift' });
    const rows = Object.fromEntries(r.body.data.preview.rows.map((x: any) => [x.label, x.value]));
    expect(Object.values(rows)).toEqual(expect.arrayContaining(['Raju', 'Evening 14:00–21:00']));
    // Nothing saved before "yes".
    expect(await RosterEntry.countDocuments({ companyId: owner.companyId })).toBe(0);
    const done = await act(owner.token, r.body.data.pendingActionId);
    expect(done.body.data.kind).toBe('done');
    const entry = await RosterEntry.findOne({ companyId: owner.companyId, employeeId: raju.id, date: tomorrow() }).lean();
    // One named day is changed as asked, even if it's usually a day off.
    expect(entry?.sent).toMatchObject({ kind: 'shift' });
    expect(String(entry!.sent!.shiftId)).toBe(evening.id);
    expect(await AuditLog.exists({ companyId: owner.companyId, action: 'roster.send', channel: 'assistant' })).toBeTruthy();

    const who = await say(owner.token, 'kal kaun kaam par hai');
    expect(who.body.data).toMatchObject({ kind: 'answer', intent: 'who_works' });
    expect(who.body.data.text).toMatch(/Evening 14:00–21:00: Raju/);
  });

  it('a range of days keeps the person\'s days off', async () => {
    const owner = await createOwner({ plan: 'pro' });
    await shift(owner.token, { name: 'Evening', start: '14:00', end: '21:00' });
    await addEmployee(owner, { name: 'Raju', joiningDate: '2026-01-01' });
    const r = await say(owner.token, 'Raju ko agle hafte evening shift do');
    expect(r.body.data.kind).toBe('confirm');
    const daysRow = r.body.data.preview.rows.at(-1).value as string;
    expect(daysRow.split(', ')).toHaveLength(6); // Monday–Saturday, Sunday stays off
  });
});
