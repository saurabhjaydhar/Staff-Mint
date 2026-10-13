import { describe, expect, it } from 'vitest';
import { Types } from 'mongoose';
import { DateTime } from 'luxon';
import { api, auth, V, createOwner, addEmployee, setPlan } from './helpers.js';
import { Company, Notification, RosterEntry } from '../src/models/index.js';
import { buildEngineInputs } from '../src/modules/payroll/inputs.js';
import { todayIn } from '../src/lib/dates.js';
import { prepareNextRosterWeek } from '../src/jobs/handlers.js';

const TZ = 'Asia/Kolkata';
const thisWeek = () => DateTime.fromISO(todayIn(TZ)).startOf('week');
const weekAt = (k: number) => thisWeek().plus({ weeks: k }).toISODate()!;
const dayOf = (week: string, i: number) => DateTime.fromISO(week).plus({ days: i }).toISODate()!;

async function setup() {
  const owner = await createOwner({ plan: 'pro' }); // usual shift 09:00–18:00, Sunday off
  const morning = (await api().post(`${V}/shifts`).set(auth(owner.token)).send({ name: 'Morning', start: '08:00', end: '14:00', weeklyOff: [0] }).expect(201)).body.data;
  const evening = (await api().post(`${V}/shifts`).set(auth(owner.token)).send({ name: 'Evening', start: '14:00', end: '21:00', weeklyOff: [0] }).expect(201)).body.data;
  const a = await addEmployee(owner, { name: 'Ramesh Kumar', joiningDate: '2026-01-01' });
  const b = await addEmployee(owner, { name: 'Pooja Singh', joiningDate: '2026-01-01' });
  return { owner, morning, evening, a, b };
}
const week = async (token: string, w: string) => (await api().get(`${V}/roster?week=${w}`).set(auth(token)).expect(200)).body.data;
const cell = (w: any, empId: string, date: string) => w.staff.find((s: any) => s.id === empId).cells.find((c: any) => c.date === date);
/** Mon–Sat on one shift for this week. */
const planWeek = (token: string, w: string, rows: { id: string; shiftId: string }[]) =>
  api()
    .put(`${V}/roster/cells`)
    .set(auth(token))
    .send({ cells: rows.flatMap((r) => [0, 1, 2, 3, 4, 5].map((i) => ({ employeeId: r.id, date: dayOf(w, i), kind: 'shift', shiftId: r.shiftId }))) })
    .expect(200);

describe('roster: alternating weekly offs', () => {
  it('"1st and 3rd Saturday off" is off only in those weeks, for attendance, salary and the roster', async () => {
    const owner = await createOwner({ plan: 'pro' });
    const shift = (
      await api()
        .post(`${V}/shifts`)
        .set(auth(owner.token))
        // Monday has no off weeks to keep: it isn't a weekly off, so it's dropped.
        .send({ name: 'Shop', start: '09:00', end: '18:00', weeklyOff: [0, 6], weeklyOffWeeks: { '6': [3, 1], '1': [2] } })
        .expect(201)
    ).body.data;
    expect(shift.weeklyOffWeeks).toEqual({ '6': [1, 3] });
    const e = await addEmployee(owner, { name: 'Raju', joiningDate: '2026-01-01', shiftId: shift.id });
    const inputs = await buildEngineInputs(new Types.ObjectId(owner.companyId), '2026-10', { employeeIds: [new Types.ObjectId(e.id)] });
    const status = (d: string) => inputs[0].employee.days.find((x) => x.date === d)!.status;
    expect(status('2026-10-03')).toBe('week_off'); // 1st Saturday
    expect(status('2026-10-10')).toBe(null); // 2nd Saturday: a working day
    expect(status('2026-10-17')).toBe('week_off'); // 3rd
    expect(status('2026-10-24')).toBe(null); // 4th
    expect(status('2026-10-11')).toBe('week_off'); // every Sunday

    const w = await week(owner.token, '2026-10-05');
    expect(cell(w, e.id, '2026-10-10')).toMatchObject({ kind: 'shift', shiftId: shift.id, usual: true });

    // Changing the off days drops weeks for days that are no longer off.
    const upd = (await api().patch(`${V}/shifts/${shift.id}`).set(auth(owner.token)).send({ weeklyOff: [0] }).expect(200)).body.data;
    expect(upd.weeklyOffWeeks).toEqual({});
  });
});

describe('roster: repeat every week', () => {
  it('swap every week: next weeks fill themselves with shifts swapped, not sent until the owner sends', async () => {
    const { owner, morning, evening, a, b } = await setup();
    const w0 = weekAt(0);
    await planWeek(owner.token, w0, [
      { id: a.id, shiftId: morning.id },
      { id: b.id, shiftId: evening.id },
    ]);
    const on = (await api().post(`${V}/roster/repeat`).set(auth(owner.token)).send({ week: w0, mode: 'rotate' }).expect(200)).body.data;
    expect(on).toMatchObject({ staff: 2, mode: 'rotate', nextWeek: weekAt(1) });
    expect(on.filled).toBe(12);

    const w1 = await week(owner.token, weekAt(1));
    expect(w1.repeat).toMatchObject({ mode: 'rotate', startWeek: w0, staff: 2, autoSend: false });
    expect(cell(w1, a.id, dayOf(weekAt(1), 0))).toMatchObject({ kind: 'shift', shiftId: evening.id, changed: true });
    expect(cell(w1, b.id, dayOf(weekAt(1), 0))).toMatchObject({ kind: 'shift', shiftId: morning.id, changed: true });
    expect(cell(w1, a.id, dayOf(weekAt(1), 6))).toMatchObject({ kind: 'off', usual: true });
    expect(w1.notSent).toBe(12);

    // Looking two weeks ahead fills it too, swapped back.
    const w2 = await week(owner.token, weekAt(2));
    expect(cell(w2, a.id, dayOf(weekAt(2), 2))).toMatchObject({ kind: 'shift', shiftId: morning.id });
    expect(cell(w2, b.id, dayOf(weekAt(2), 2))).toMatchObject({ kind: 'shift', shiftId: evening.id });

    // A week fills once: a day the owner puts back to usual stays usual.
    await api()
      .put(`${V}/roster/cells`)
      .set(auth(owner.token))
      .send({ cells: [{ employeeId: a.id, date: dayOf(weekAt(1), 0), kind: 'usual' }] })
      .expect(200);
    expect(cell(await week(owner.token, weekAt(1)), a.id, dayOf(weekAt(1), 0))).toMatchObject({ usual: true, changed: false });

    // The owner's own change in a filled week is kept when repeat is turned off; the rest goes.
    await api()
      .put(`${V}/roster/cells`)
      .set(auth(owner.token))
      .send({ cells: [{ employeeId: b.id, date: dayOf(weekAt(1), 1), kind: 'off' }] })
      .expect(200);
    expect((await api().delete(`${V}/roster/repeat`).set(auth(owner.token)).expect(200)).body.data).toEqual({ staff: 2 });
    const after = await week(owner.token, weekAt(1));
    expect(after.repeat).toBeNull();
    expect(cell(after, b.id, dayOf(weekAt(1), 1))).toMatchObject({ kind: 'off', changed: true });
    expect(cell(after, b.id, dayOf(weekAt(1), 2))).toMatchObject({ usual: true });
    expect(await RosterEntry.countDocuments({ companyId: owner.companyId, source: 'repeat' })).toBe(0);
    // This week (the one it was copied from) is untouched.
    expect(cell(await week(owner.token, w0), a.id, dayOf(w0, 0))).toMatchObject({ kind: 'shift', shiftId: morning.id });
  });

  it('same every week keeps roster days and leaves usual days alone', async () => {
    const { owner, evening, a, b } = await setup();
    const w0 = weekAt(0);
    await api()
      .put(`${V}/roster/cells`)
      .set(auth(owner.token))
      .send({
        cells: [
          { employeeId: b.id, date: dayOf(w0, 0), kind: 'shift', shiftId: evening.id },
          { employeeId: b.id, date: dayOf(w0, 3), kind: 'off' },
        ],
      })
      .expect(200);
    const on = (await api().post(`${V}/roster/repeat`).set(auth(owner.token)).send({ week: w0, mode: 'same' }).expect(200)).body.data;
    expect(on.filled).toBe(2);
    const w1 = await week(owner.token, weekAt(1));
    expect(cell(w1, b.id, dayOf(weekAt(1), 0))).toMatchObject({ kind: 'shift', shiftId: evening.id });
    expect(cell(w1, b.id, dayOf(weekAt(1), 3))).toMatchObject({ kind: 'off' });
    expect(w1.staff.find((s: any) => s.id === a.id).cells.every((c: any) => c.usual)).toBe(true);
  });

  it('swapping needs two shifts in the week', async () => {
    const { owner, morning, a, b } = await setup();
    await planWeek(owner.token, weekAt(0), [
      { id: a.id, shiftId: morning.id },
      { id: b.id, shiftId: morning.id },
    ]);
    // b's Sunday is off; a and b both work the usual 9–6 nowhere: only Morning is used.
    const r = await api().post(`${V}/roster/repeat`).set(auth(owner.token)).send({ week: weekAt(0), mode: 'rotate' });
    expect(r.status).toBe(400);
    expect(r.body.error.message).toMatch(/2 shifts/);
  });

  it('Thursday: next week is sent on its own when chosen, otherwise owners are reminded', async () => {
    const { owner, morning, evening, a, b } = await setup();
    await planWeek(owner.token, weekAt(0), [
      { id: a.id, shiftId: morning.id },
      { id: b.id, shiftId: evening.id },
    ]);
    await api().post(`${V}/roster/repeat`).set(auth(owner.token)).send({ week: weekAt(0), mode: 'rotate' }).expect(200);
    const company = await Company.findById(owner.companyId).lean();
    const thursday = thisWeek().setZone(TZ, { keepLocalTime: true }).plus({ days: 3, hours: 10, minutes: 5 });
    // Wednesday: nothing yet.
    expect(await prepareNextRosterWeek(company, thursday.minus({ days: 1 }))).toBeNull();
    expect(await prepareNextRosterWeek(company, thursday)).toBe(weekAt(1));
    const reminder = await Notification.findOne({ companyId: owner.companyId, template: 'roster_ready', channel: 'in_app' }).lean();
    // Owners read it in their language (Hindi by default).
    expect(reminder?.title).toMatch(/^अगले हफ़्ते का रोस्टर तैयार है \(\d+ \S+ से\)$/);
    expect(await RosterEntry.countDocuments({ companyId: owner.companyId, date: { $gte: weekAt(1) }, sent: { $ne: null } })).toBe(0);
    // Already handled this week.
    expect(await prepareNextRosterWeek(company, thursday, weekAt(1))).toBeNull();

    // With "send on its own", the next run sends it.
    await api().post(`${V}/roster/repeat`).set(auth(owner.token)).send({ week: weekAt(0), mode: 'rotate', autoSend: true }).expect(200);
    expect(await prepareNextRosterWeek(company, thursday)).toBe(weekAt(1));
    const sent = await RosterEntry.find({ companyId: owner.companyId, date: { $gte: weekAt(1), $lte: dayOf(weekAt(1), 6) } }).lean();
    expect(sent).toHaveLength(12);
    expect(sent.every((r) => r.sent?.kind === 'shift')).toBe(true);
    expect(cell(await week(owner.token, weekAt(1)), a.id, dayOf(weekAt(1), 0))).toMatchObject({ shiftId: evening.id, changed: false });
  });

  it('repeating is on Growth and up; turning it off works on any plan', async () => {
    const { owner, morning, evening, a, b } = await setup();
    await planWeek(owner.token, weekAt(0), [
      { id: a.id, shiftId: morning.id },
      { id: b.id, shiftId: evening.id },
    ]);
    await api().post(`${V}/roster/repeat`).set(auth(owner.token)).send({ week: weekAt(0), mode: 'rotate' }).expect(200);
    await setPlan(owner.companyId, 'starter');
    const r = await api().post(`${V}/roster/repeat`).set(auth(owner.token)).send({ week: weekAt(0), mode: 'same' });
    expect(r.status).toBe(402);
    expect(r.body.error).toMatchObject({ code: 'FEATURE_NOT_IN_PLAN', details: { feature: 'roster_repeat' } });
    // No more filling on Starter.
    const w3 = await week(owner.token, weekAt(3));
    expect(w3.repeatAllowed).toBe(false);
    expect(cell(w3, a.id, dayOf(weekAt(3), 0))).toMatchObject({ usual: true });
    await api().delete(`${V}/roster/repeat`).set(auth(owner.token)).expect(200);
    expect((await week(owner.token, weekAt(1))).repeat).toBeNull();
  });
});
