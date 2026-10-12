import { describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, punchBody, mocks } from './helpers.js';
import { Attendance, AuditLog, Employee, Notification } from '../src/models/index.js';
import { closeDay } from '../src/modules/attendance/service.js';
import { Types } from 'mongoose';

async function setup(settings: Record<string, unknown> = {}) {
  const owner = await createOwner();
  if (Object.keys(settings).length) await api().patch(`${V}/company/settings`).set(auth(owner.token)).send(settings).expect(200);
  const phone = nextPhone();
  const emp = await addEmployee(owner, { phone, name: 'Ramesh Kumar' });
  const e = await employeeSession(phone);
  return { owner, emp, e };
}

describe('attendance — check-in/out', () => {
  it('check-in inside geofence with selfie, idempotent retries, check-out', async () => {
    const { owner, emp, e } = await setup();
    const body = punchBody(e.deviceId);
    const r = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(body);
    expect(r.status).toBe(201);
    expect(r.body.data.punch).toMatchObject({ type: 'in', insideGeofence: true, approval: 'not_required', source: 'app' });
    expect(r.body.data.punch.distanceM).toBeLessThan(5);
    expect(r.body.data.record.status).toBe('present');
    // Signed selfie URL works; tampered signature does not.
    const url = new URL(r.body.data.punch.selfieUrl);
    expect((await api().get(url.pathname + url.search)).status).toBe(200);
    expect((await api().get(url.pathname + url.search.replace(/sig=[a-f0-9]{4}/, 'sig=0000'))).status).toBe(403);

    const dup = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(body);
    expect(dup.status).toBe(200);
    expect(dup.body.data.punch.id).toBe(r.body.data.punch.id);
    const again = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId));
    expect(again.status).toBe(409);
    const out = await api().post(`${V}/attendance/check-out`).set(auth(e.token)).send(punchBody(e.deviceId));
    expect(out.status).toBe(201);
    expect(out.body.data.record.punches).toHaveLength(2);

    const today = await api().get(`${V}/attendance/today`).set(auth(e.token));
    expect(today.body.data).toMatchObject({ nextAction: 'check_in', shift: { start: '09:00' } });
    const day = await api().get(`${V}/attendance`).set(auth(owner.token));
    expect(day.body.data.find((x: any) => x.employee.id === emp.id).record.punches).toHaveLength(2);
  });

  it('blocks check-in outside the geofence and with fake GPS', async () => {
    const { e } = await setup();
    const far = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { geo: { lat: 28.7, lng: 77.3, accuracyM: 10 } }));
    expect(far.status).toBe(422);
    expect(far.body.error.code).toBe('OUTSIDE_GEOFENCE');
    expect(far.body.error.details.distanceM).toBeGreaterThan(1000);
    const mock = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { mockLocation: true }));
    expect(mock.status).toBe(422);
  });

  it('phone lock (recommended, the default): a failed or missing lock tags the punch but never blocks it', async () => {
    const { owner, e } = await setup();
    const ok = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { lockCheck: 'passed' })).expect(201);
    expect(ok.body.data.punch).toMatchObject({ lockCheck: 'passed', approval: 'not_required', flags: [] });
    const out = await api().post(`${V}/attendance/check-out`).set(auth(e.token)).send(punchBody(e.deviceId, { lockCheck: 'failed' })).expect(201);
    expect(out.body.data.punch).toMatchObject({ lockCheck: 'failed', approval: 'not_required' });
    expect(out.body.data.punch.flags).toContain('phone_lock_failed');
    const again = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { lockCheck: 'unavailable' })).expect(201);
    expect(again.body.data.punch.flags).toContain('no_phone_lock');
    // A failed unlock shows up in the owner's review list; a phone with no lock is only tagged.
    const dash = await api().get(`${V}/dashboard/today`).set(auth(owner.token)).expect(200);
    expect(dash.body.data.needsAction.flags[0].flags).toEqual(expect.arrayContaining(['phone_lock_failed', 'no_phone_lock']));
    expect(dash.body.data.needsAction.punchApprovals).toHaveLength(0);
  });

  it('phone lock required: anything but a pass waits for the owner; off ignores the result', async () => {
    const { owner, e } = await setup({ phoneLockPolicy: 'required' });
    const r = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { lockCheck: 'unavailable' })).expect(201);
    expect(r.body.data.punch).toMatchObject({ approval: 'pending', lockCheck: 'unavailable' });
    const n = await Notification.findOne({ companyId: owner.companyId, 'data.type': 'punch_approval' }).sort({ createdAt: -1 }).lean();
    expect(JSON.stringify(n)).toMatch(/without unlocking|फ़ोन लॉक खोले बिना/);
    // Older app versions send no lockCheck at all: same as not passed.
    const out = await api().post(`${V}/attendance/check-out`).set(auth(e.token)).send(punchBody(e.deviceId)).expect(201);
    expect(out.body.data.punch).toMatchObject({ approval: 'pending', lockCheck: null, flags: ['no_phone_lock'] });

    await api().patch(`${V}/company/settings`).set(auth(owner.token)).send({ phoneLockPolicy: 'off' }).expect(200);
    const p2 = nextPhone();
    await addEmployee(owner, { phone: p2, name: 'Suresh Yadav' });
    const e2 = await employeeSession(p2);
    const off = await api().post(`${V}/attendance/check-in`).set(auth(e2.token)).send(punchBody(e2.deviceId, { lockCheck: 'failed' })).expect(201);
    expect(off.body.data.punch).toMatchObject({ approval: 'not_required', lockCheck: null, flags: [] });
    expect((await api().patch(`${V}/company/settings`).set(auth(owner.token)).send({ phoneLockPolicy: 'always' })).status).toBe(400);
  });

  it('request-approval policy: outside punch is pending until owner approves', async () => {
    const { owner, e } = await setup({ outsideGeofencePolicy: 'request_approval' });
    const r = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { geo: { lat: 28.62, lng: 77.21, accuracyM: 10 } }));
    expect(r.status).toBe(201);
    expect(r.body.data.punch.approval).toBe('pending');
    expect(r.body.data.record.status).toBeNull();
    expect(await Notification.countDocuments({ companyId: owner.companyId, template: 'punch_approval' })).toBeGreaterThan(0);
    const dash = await api().get(`${V}/dashboard/today`).set(auth(owner.token));
    expect(dash.body.data.needsAction.punchApprovals).toHaveLength(1);
    const d = await api().post(`${V}/attendance/${r.body.data.record.id}/punches/${r.body.data.punch.id}/decision`).set(auth(owner.token)).send({ approve: true });
    expect(d.status).toBe(200);
    expect(d.body.data.status).toBe('present');
  });

  it('requires consent, selfie and the bound device', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    await addEmployee(owner, { phone });
    const { otpLogin } = await import('./helpers.js');
    const login = await otpLogin(phone, 'dev-consent-1');
    const r = await api().post(`${V}/attendance/check-in`).set(auth(login.accessToken)).send(punchBody('dev-consent-1'));
    expect(r.status).toBe(403);
    await api().post(`${V}/me/consent`).set(auth(login.accessToken)).send({ location: true }).expect(200);
    const noSelfie = await api().post(`${V}/attendance/check-in`).set(auth(login.accessToken)).send(punchBody('dev-consent-1', { selfieBase64: null }));
    expect(noSelfie.status).toBe(400);
    const otherDevice = await api().post(`${V}/attendance/check-in`).set(auth(login.accessToken)).send(punchBody('dev-other-9'));
    expect(otherDevice.body.error.code).toBe('DEVICE_NOT_BOUND');
  });

  it('offline sync keeps original time, flags late sync and is idempotent', async () => {
    const { e } = await setup();
    const twoDaysAgo = new Date(Date.now() - 2 * 86400_000);
    twoDaysAgo.setUTCHours(4, 0, 0, 0); // 09:30 IST
    const out = new Date(twoDaysAgo.getTime() + 8 * 3600_000);
    const punches = [
      { type: 'out', ...punchBody(e.deviceId, { clientTime: out.toISOString(), selfieBase64: null }) },
      { type: 'in', ...punchBody(e.deviceId, { clientTime: twoDaysAgo.toISOString() }) },
    ];
    const r = await api().post(`${V}/attendance/sync`).set(auth(e.token)).send({ punches });
    expect(r.status).toBe(200);
    expect(r.body.data.results.every((x: any) => x.ok)).toBe(true);
    expect(r.body.data.results[0].punch.flags).toContain('late_sync');
    expect(new Date(r.body.data.results[0].punch.clientTime).toISOString()).toBe(twoDaysAgo.toISOString());
    const rec = await Attendance.findOne({ employeeId: e.user.employeeId }).setOptions({ skipTenant: true }).lean();
    expect(rec!.status).toBe('present');
    expect(rec!.workedMinutes).toBe(480);
    const again = await api().post(`${V}/attendance/sync`).set(auth(e.token)).send({ punches });
    expect(again.body.data.results.every((x: any) => x.ok)).toBe(true);
    const recs = await Attendance.find({ employeeId: e.user.employeeId }).setOptions({ skipTenant: true }).lean();
    expect(recs[0].punches).toHaveLength(2);
  });

  it('owner override is audited and shows in month grid', async () => {
    const { owner, emp } = await setup();
    const r = await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-10-01', status: 'half_day', reason: 'Left early for doctor' });
    expect(r.status).toBe(200);
    expect(r.body.data).toMatchObject({ status: 'half_day', overridden: true, overrideReason: 'Left early for doctor' });
    const log = await AuditLog.findOne({ companyId: owner.companyId, action: 'attendance.override' }).lean();
    expect(log!.after).toMatchObject({ status: 'half_day' });
    const grid = await api().get(`${V}/attendance/month?month=2026-10`).set(auth(owner.token));
    expect(grid.body.data.rows[0].codes['2026-10-01']).toBe('HD');
    // The reason is optional (owners pick what happened first); an invalid status is still refused.
    const noReason = await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-10-01', status: 'absent' });
    expect(noReason.status).toBe(200);
    expect(noReason.body.data.overrideReason).toBeNull();
    expect((await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-10-01', status: 'sick' })).status).toBe(400);
  });
});

describe('attendance — undo override', () => {
  it('clear-override restores the punch-derived status, or unmarked without punches', async () => {
    const { owner, emp, e } = await setup();
    await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId)).expect(201);
    const today = (await api().get(`${V}/attendance/today`).set(auth(e.token))).body.data.date;
    await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: emp.id, date: today, status: 'absent', reason: 'Owner confirmed' }).expect(200);
    const undo = await api().post(`${V}/attendance/clear-override`).set(auth(owner.token)).send({ employeeId: emp.id, date: today, reason: 'Undo' });
    expect(undo.status).toBe(200);
    expect(undo.body.data).toMatchObject({ status: 'present', overridden: false });
    // No punches: back to unmarked
    await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-09-01', status: 'half_day', reason: 'Owner confirmed' }).expect(200);
    const undo2 = await api().post(`${V}/attendance/clear-override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-09-01', reason: 'Undo' });
    expect(undo2.body.data).toMatchObject({ status: null, overridden: false });
    expect(await AuditLog.countDocuments({ companyId: owner.companyId, action: 'attendance.override.clear' })).toBe(2);
    // Nothing recorded → null
    const none = await api().post(`${V}/attendance/clear-override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-08-01', reason: 'Undo' });
    expect(none.body.data).toBeNull();
    // Employees cannot call it
    expect((await api().post(`${V}/attendance/clear-override`).set(auth(e.token)).send({ employeeId: emp.id, date: today, reason: 'Undo' })).status).toBe(403);
  });
});

describe('attendance — nightly close (auto-absent)', () => {
  it('marks absent / holiday / week off / leave and applies missing-checkout policy', async () => {
    const owner = await createOwner();
    const cid = new Types.ObjectId(owner.companyId);
    const a = await addEmployee(owner, { name: 'Absent Guy' });
    const b = await addEmployee(owner, { name: 'Forgot Checkout' });
    await Employee.collection.updateMany({ companyId: cid }, { $set: { createdAt: new Date('2026-01-01') } });
    await Attendance.create({ companyId: cid, employeeId: b.id, date: '2026-10-06', punches: [{ type: 'in', clientTime: new Date('2026-10-06T03:30:00Z'), serverTime: new Date('2026-10-06T03:30:00Z'), clientPunchId: randomUUID() }], status: 'present' });
    await api().post(`${V}/holidays`).set(auth(owner.token)).send({ date: '2026-10-07', name: 'Local fair' }).expect(201);

    await closeDay(cid, '2026-10-06'); // Tuesday
    await closeDay(cid, '2026-10-07'); // holiday
    await closeDay(cid, '2026-10-04'); // Sunday
    const recs = await Attendance.find({ companyId: cid }).lean();
    const st = (emp: string, d: string) => recs.find((r) => String(r.employeeId) === emp && r.date === d)?.status;
    expect(st(a.id, '2026-10-06')).toBe('absent');
    expect(st(b.id, '2026-10-06')).toBe('half_day');
    expect(recs.find((r) => String(r.employeeId) === b.id && r.date === '2026-10-06')!.flags).toContain('missing_checkout');
    expect(st(a.id, '2026-10-07')).toBe('holiday');
    expect(st(a.id, '2026-10-04')).toBe('week_off');
    // Idempotent
    await closeDay(cid, '2026-10-06');
    expect(await Attendance.countDocuments({ companyId: cid, date: '2026-10-06' })).toBe(2);
  });

  it('never marks days before the employee was added', async () => {
    const owner = await createOwner();
    await addEmployee(owner);
    await closeDay(new Types.ObjectId(owner.companyId), '2020-01-07');
    expect(await Attendance.countDocuments({ companyId: owner.companyId })).toBe(0);
  });
});

describe('leave', () => {
  it('employee applies → owner notified → approve writes attendance and balance → cancel reverts', async () => {
    const { push } = await mocks();
    const { owner, emp, e } = await setup();
    await api().post(`${V}/me/push-token`).set(auth(owner.token)).send({ token: 'owner-fcm-token-123', platform: 'android' }).expect(200);
    await api().put(`${V}/leave-balances/${emp.id}`).set(auth(owner.token)).send({ year: 2026, paid: 12, sick: 6 }).expect(200);
    // Tue 13 – Thu 15 Oct 2026, no holidays/week offs → 3 days
    const r = await api().post(`${V}/leaves`).set(auth(e.token)).send({ type: 'paid', from: '2026-10-13', to: '2026-10-15', reason: 'Shaadi' });
    expect(r.status).toBe(201);
    expect(r.body.data).toMatchObject({ status: 'pending', days: 3, employeeName: 'Ramesh Kumar' });
    expect(push.sent.some((p) => p.msg.title.includes('Ramesh'))).toBe(true);
    const overlap = await api().post(`${V}/leaves`).set(auth(e.token)).send({ type: 'paid', from: '2026-10-14', to: '2026-10-14' });
    expect(overlap.status).toBe(409);

    const d = await api().post(`${V}/leaves/${r.body.data.id}/decision`).set(auth(owner.token)).send({ decision: 'approved' });
    expect(d.body.data.status).toBe('approved');
    const recs = await Attendance.find({ companyId: owner.companyId, employeeId: emp.id }).sort({ date: 1 }).lean();
    expect(recs.map((x) => [x.date, x.status, x.leaveType])).toEqual([
      ['2026-10-13', 'leave', 'paid'],
      ['2026-10-14', 'leave', 'paid'],
      ['2026-10-15', 'leave', 'paid'],
    ]);
    const bal = await api().get(`${V}/leave-balances?employeeId=${emp.id}&year=2026`).set(auth(owner.token));
    expect(bal.body.data[0]).toMatchObject({ paid: 12, usedPaid: 3 });
    expect((await api().post(`${V}/leaves/${r.body.data.id}/decision`).set(auth(owner.token)).send({ decision: 'rejected' })).status).toBe(409);
    expect((await api().post(`${V}/leaves/${r.body.data.id}/cancel`).set(auth(e.token))).status).toBe(403);
    await api().post(`${V}/leaves/${r.body.data.id}/cancel`).set(auth(owner.token)).expect(200);
    const after = await Attendance.find({ companyId: owner.companyId, employeeId: emp.id, status: { $ne: null } }).lean();
    expect(after).toHaveLength(0);
    const bal2 = await api().get(`${V}/leave-balances?employeeId=${emp.id}&year=2026`).set(auth(owner.token));
    expect(bal2.body.data[0].usedPaid).toBe(0);
  });

  it('owner applying on behalf auto-approves; week offs excluded from day count', async () => {
    const owner = await createOwner();
    const emp = await addEmployee(owner);
    // Sat 10 – Mon 12 Oct 2026: Sunday excluded → 2 days
    const r = await api().post(`${V}/leaves`).set(auth(owner.token)).send({ type: 'sick', from: '2026-10-10', to: '2026-10-12', employeeId: emp.id });
    expect(r.body.data).toMatchObject({ status: 'approved', days: 2 });
  });
});
