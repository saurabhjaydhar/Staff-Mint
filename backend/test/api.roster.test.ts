import { describe, expect, it } from 'vitest';
import { Types } from 'mongoose';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks, setPlan } from './helpers.js';
import { Attendance, Config, Leave, Plan, RosterEntry } from '../src/models/index.js';
import { buildEngineInputs } from '../src/modules/payroll/inputs.js';
import { seedDefaults } from '../src/scripts/seedDefaults.js';
import { todayIn } from '../src/lib/dates.js';

const WEEK = '2026-10-05'; // Mon 5 – Sun 11 Oct 2026

async function setup() {
  const owner = await createOwner(); // usual shift 09:00–18:00, Sunday off
  const morning = (await api().post(`${V}/shifts`).set(auth(owner.token)).send({ name: 'Morning', start: '09:00', end: '17:00', weeklyOff: [0] }).expect(201)).body.data;
  const evening = (await api().post(`${V}/shifts`).set(auth(owner.token)).send({ name: 'Evening', start: '13:00', end: '21:00', weeklyOff: [0] }).expect(201)).body.data;
  const aPhone = nextPhone();
  const a = await addEmployee(owner, { name: 'Ramesh Kumar', phone: aPhone, joiningDate: '2026-01-01' });
  const b = await addEmployee(owner, { name: 'Pooja Singh', joiningDate: '2026-01-01' });
  return { owner, morning, evening, a, aPhone, b };
}
const week = async (token: string) => (await api().get(`${V}/roster?week=${WEEK}`).set(auth(token)).expect(200)).body.data;
const cell = (w: any, empId: string, date: string) => w.staff.find((s: any) => s.id === empId).cells.find((c: any) => c.date === date);
const dayStatus = async (companyId: string, empId: string, date: string) => {
  const inputs = await buildEngineInputs(new Types.ObjectId(companyId), date.slice(0, 7), { employeeIds: [new Types.ObjectId(empId)] });
  return inputs[0].employee.days.find((d) => d.date === date)!.status;
};

describe('roster', () => {
  it('a week starts from the usual shift; changes wait until sent; problems are listed', async () => {
    const { owner, evening, morning, a, b } = await setup();
    let w = await week(owner.token);
    expect(w.weekStart).toBe(WEEK);
    expect(w.days).toHaveLength(7);
    expect(cell(w, a.id, '2026-10-05')).toMatchObject({ kind: 'shift', usual: true, changed: false });
    expect(cell(w, a.id, '2026-10-11')).toMatchObject({ kind: 'off', usual: true });
    expect(w.notSent).toBe(0);

    await api()
      .put(`${V}/roster/cells`)
      .set(auth(owner.token))
      .send({
        cells: [
          { employeeId: a.id, date: '2026-10-05', kind: 'shift', shiftId: evening.id },
          { employeeId: a.id, date: '2026-10-11', kind: 'shift', shiftId: morning.id },
          { employeeId: b.id, date: '2026-10-07', kind: 'off' },
        ],
      })
      .expect(200);
    await Leave.create({ companyId: owner.companyId, employeeId: b.id, type: 'paid', from: '2026-10-06', to: '2026-10-06', status: 'approved', reason: 'x', days: 1 });
    w = await week(owner.token);
    expect(w.notSent).toBe(3);
    expect(cell(w, a.id, '2026-10-05')).toMatchObject({ kind: 'shift', shiftId: evening.id, usual: false, changed: true });
    expect(w.problems).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: 'no_day_off', employeeId: a.id, date: '2026-10-11' }),
        expect.objectContaining({ type: 'leave_working', employeeId: b.id, date: '2026-10-06' }),
      ]),
    );
    // Not sent yet: salary still uses the usual week.
    expect(await dayStatus(owner.companyId, a.id, '2026-10-11')).toBe('week_off');
    expect(await dayStatus(owner.companyId, b.id, '2026-10-07')).toBe(null);
  });

  it('sending makes it count for attendance and salary, tells staff without the app on WhatsApp, and can go back to usual', async () => {
    const { messaging } = await mocks();
    const { owner, evening, morning, a, b } = await setup();
    await api()
      .put(`${V}/roster/cells`)
      .set(auth(owner.token))
      .send({
        cells: [
          { employeeId: a.id, date: '2026-10-11', kind: 'shift', shiftId: morning.id },
          { employeeId: b.id, date: '2026-10-07', kind: 'off' },
          { employeeId: b.id, date: '2026-10-08', kind: 'shift', shiftId: evening.id },
        ],
      })
      .expect(200);
    const sent = await api().post(`${V}/roster/send`).set(auth(owner.token)).send({ week: WEEK }).expect(200);
    expect(sent.body.data).toEqual({ sentTo: 2, days: 3 });
    expect((await week(owner.token)).notSent).toBe(0);
    expect(await dayStatus(owner.companyId, a.id, '2026-10-11')).toBe(null); // works this Sunday
    expect(await dayStatus(owner.companyId, b.id, '2026-10-07')).toBe('week_off');
    const wa = messaging.outbox.filter((m) => m.template === 'roster_published');
    expect(wa).toHaveLength(2);
    expect(wa.every((m) => !m.params!.join(' ').includes('\n'))).toBe(true);

    // Back to the usual Sunday off.
    await api().put(`${V}/roster/cells`).set(auth(owner.token)).send({ cells: [{ employeeId: a.id, date: '2026-10-11', kind: 'usual' }] }).expect(200);
    expect((await week(owner.token)).notSent).toBe(1);
    await api().post(`${V}/roster/send`).set(auth(owner.token)).send({ week: WEEK }).expect(200);
    expect(await RosterEntry.countDocuments({ companyId: owner.companyId, employeeId: a.id })).toBe(0);
    expect(await dayStatus(owner.companyId, a.id, '2026-10-11')).toBe('week_off');

    // Copy last week onto the next one, not sent yet.
    await api().post(`${V}/roster/copy-last-week`).set(auth(owner.token)).send({ week: '2026-10-12' }).expect(200);
    const next = (await api().get(`${V}/roster?week=2026-10-12`).set(auth(owner.token)).expect(200)).body.data;
    expect(cell(next, b.id, '2026-10-14')).toMatchObject({ kind: 'off', changed: true });
    expect(cell(next, b.id, '2026-10-15')).toMatchObject({ kind: 'shift', shiftId: evening.id });
  });

  it('days already worked follow the new shift; staff see their week and today’s shift', async () => {
    const { owner, evening, a, aPhone } = await setup();
    // Checked in 09:30 on Tue 6 Oct: 30 min late for the usual 09:00 shift.
    const at = (h: number, m: number) => new Date(Date.UTC(2026, 9, 6, h - 5, m - 30));
    await Attendance.create({
      companyId: owner.companyId,
      employeeId: a.id,
      date: '2026-10-06',
      status: 'present',
      lateMinutes: 30,
      punches: [
        { type: 'in', clientTime: at(9, 30), serverTime: at(9, 30) },
        { type: 'out', clientTime: at(21, 0), serverTime: at(21, 0) },
      ],
    });
    await api().put(`${V}/roster/cells`).set(auth(owner.token)).send({ cells: [{ employeeId: a.id, date: '2026-10-06', kind: 'shift', shiftId: evening.id }] }).expect(200);
    await api().post(`${V}/roster/send`).set(auth(owner.token)).send({ week: WEEK }).expect(200);
    const rec = await Attendance.findOne({ companyId: owner.companyId, employeeId: a.id, date: '2026-10-06' }).lean();
    expect(rec!.lateMinutes).toBe(0);

    // Today's roster shift shows on the staff home.
    const today = todayIn('Asia/Kolkata');
    await api().put(`${V}/roster/cells`).set(auth(owner.token)).send({ cells: [{ employeeId: a.id, date: today, kind: 'shift', shiftId: evening.id }] }).expect(200);
    await api().post(`${V}/roster/send`).set(auth(owner.token)).send({ week: today }).expect(200);
    const e = await employeeSession(aPhone);
    const t = await api().get(`${V}/attendance/today`).set(auth(e.token)).expect(200);
    expect(t.body.data.shift).toMatchObject({ start: '13:00', end: '21:00' });
    const mine = await api().get(`${V}/roster/mine?week=${WEEK}`).set(auth(e.token)).expect(200);
    expect(mine.body.data.days).toHaveLength(7);
    expect(mine.body.data.rostered).toBe(true);
    expect(mine.body.data.days.find((d: any) => d.date === '2026-10-06')).toMatchObject({ kind: 'shift', shiftId: evening.id, changed: true });
    expect(mine.body.data.days.find((d: any) => d.date === '2026-10-11')).toMatchObject({ kind: 'off', changed: false });
    // Staff can't edit the roster.
    await api().get(`${V}/roster?week=${WEEK}`).set(auth(e.token)).expect(403);
  });

  it('is a paid feature; Free gets a clear upgrade error', async () => {
    const owner = await createOwner();
    await setPlan(owner.companyId, 'free');
    const r = await api().get(`${V}/roster`).set(auth(owner.token));
    expect(r.status).toBe(402);
    expect(r.body.error).toMatchObject({ code: 'FEATURE_NOT_IN_PLAN', details: { feature: 'roster' } });
  });

  it('plans already saved get the roster feature once; an admin removing it later sticks', async () => {
    await Plan.updateOne({ code: 'starter' }, { $pull: { features: 'roster' } });
    await Config.deleteOne({ key: 'features.added', companyId: null });
    await seedDefaults();
    expect((await Plan.findOne({ code: 'starter' }).lean())!.features).toContain('roster');
    await Plan.updateOne({ code: 'starter' }, { $pull: { features: 'roster' } });
    await seedDefaults();
    expect((await Plan.findOne({ code: 'starter' }).lean())!.features).not.toContain('roster');
    await Plan.updateOne({ code: 'starter' }, { $addToSet: { features: 'roster' } });
  });
});
