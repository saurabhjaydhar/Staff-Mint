import { describe, expect, it } from 'vitest';
import { Types } from 'mongoose';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks, punchBody } from './helpers.js';
import { Attendance, AuditLog, Employee, LocationPing, Notification, Shift, TrackingSession } from '../src/models/index.js';
import { addEvents, addPings, trackingTick, travelSummary } from '../src/modules/tracking/service.js';
import { sendDigest } from '../src/jobs/handlers.js';
import ExcelJS from 'exceljs';
import { buildEngineInputs } from '../src/modules/payroll/inputs.js';
import { computePayslip } from '../src/modules/payroll/engine.js';
import { cleanPoints, distanceOf, stopsOf } from '../src/modules/tracking/route.js';
import { describe as describeLog } from '../src/modules/audit/describe.js';
import { addDays, todayIn, zonedInstant } from '../src/lib/dates.js';
import type { Ctx } from '../src/lib/context.js';

const TZ = 'Asia/Kolkata';
const at = (base: Date, min: number) => new Date(base.getTime() + min * 60_000);
// ~111 m per 0.001° latitude.
const pt = (base: Date, min: number, dLat: number, accuracyM = 10) => ({ at: at(base, min), lat: 28.6139 + dLat, lng: 77.209, accuracyM });

describe('route maths', () => {
  const t0 = new Date('2026-10-13T05:00:00Z');
  it('distance ignores GPS wobble, bad accuracy and impossible jumps', () => {
    const pts = [
      pt(t0, 0, 0),
      pt(t0, 2, 0.00005), // 5 m wobble
      pt(t0, 4, 0.0001),
      pt(t0, 6, 0.01), // 1.1 km in 2 min = 33 km/h: travel
      pt(t0, 7, 0.5), // 55 km in a minute: a jump
      pt(t0, 8, 0.02, 500), // bad accuracy
      pt(t0, 10, 0.02), // another 1.1 km
    ];
    expect(cleanPoints(pts)).toHaveLength(5);
    expect(distanceOf(pts)).toBeGreaterThan(2100);
    expect(distanceOf(pts)).toBeLessThan(2300);
  });

  it('a stop is 10+ minutes within 100 m', () => {
    const pts = [pt(t0, 0, 0), pt(t0, 5, 0.0002), pt(t0, 12, 0.0003), pt(t0, 14, 0.01), pt(t0, 16, 0.0101), pt(t0, 20, 0.0102)];
    const stops = stopsOf(pts);
    expect(stops).toHaveLength(1);
    expect(stops[0]).toMatchObject({ minutes: 12 });
  });
});

async function setup(plan = 'pro') {
  const { push } = await mocks();
  const owner = await createOwner({ plan });
  // A shift covering the whole day, so tests don't depend on the time they run.
  await Shift.updateMany({ companyId: owner.companyId }, { $set: { start: '00:01', end: '23:58' } });
  const phone = nextPhone();
  const emp = await addEmployee(owner, { name: 'Raju', phone });
  const staff = await employeeSession(phone);
  return { owner, emp, staff, push };
}
const ctxFor = (companyId: string, employeeId: string): Ctx => ({
  userId: null,
  companyId: new Types.ObjectId(companyId),
  role: 'employee',
  employeeId: new Types.ObjectId(employeeId),
  branchIds: [],
  actorName: 'Raju',
  channel: 'app',
  language: 'en',
});
const send = (token: string, points: any[]) => api().post(`${V}/tracking/pings`).set(auth(token)).send({ points });
const nowPts = (n: number) => Array.from({ length: n }, (_, i) => ({ at: new Date(Date.now() - (n - i) * 60_000).toISOString(), lat: 28.6139 + i * 0.002, lng: 77.209, accuracyM: 12, battery: 80 }));

describe('field staff location', () => {
  it('owner turns it on (Pro), staff agree, share while checked in, checking out stops it', async () => {
    const { owner, emp, staff } = await setup();
    const on = await api().put(`${V}/tracking/employees/${emp.id}`).set(auth(owner.token)).send({ enabled: true }).expect(200);
    expect(on.body.data).toEqual({ enabled: true, consented: false });
    expect(await Notification.exists({ companyId: owner.companyId, template: 'tracking_request' })).toBeTruthy();

    let me = (await api().get(`${V}/tracking/me`).set(auth(staff.token)).expect(200)).body.data;
    expect(me).toMatchObject({ enabled: true, consented: false, shouldShare: false, intervalSec: 120, minDistanceM: 100 });
    expect(me.consentText.en[1]).toMatch(/Never at other times/);
    // Nothing is taken before they agree.
    expect((await send(staff.token, nowPts(1)).expect(200)).body.data).toMatchObject({ accepted: 0, stop: true, reason: 'no_consent' });

    me = (await api().post(`${V}/tracking/me/consent`).set(auth(staff.token)).expect(200)).body.data;
    expect(me.consented).toBe(true);
    // Not checked in: nothing is taken either.
    expect((await send(staff.token, nowPts(1)).expect(200)).body.data).toMatchObject({ stop: true, reason: 'checked_out' });

    await api().post(`${V}/attendance/check-in`).set(auth(staff.token)).send(punchBody(staff.deviceId)).expect(201);
    me = (await api().get(`${V}/tracking/me`).set(auth(staff.token)).expect(200)).body.data;
    expect(me.shouldShare).toBe(true);
    const r = (await send(staff.token, nowPts(5)).expect(200)).body.data;
    expect(r).toMatchObject({ accepted: 5, stop: false });

    const live = (await api().get(`${V}/tracking/live`).set(auth(owner.token)).expect(200)).body.data;
    expect(live).toHaveLength(1);
    expect(live[0]).toMatchObject({ name: 'Raju', status: 'live', battery: 80 });
    expect(live[0].distanceM).toBeGreaterThan(800);

    const date = todayIn(TZ);
    const day = (await api().get(`${V}/tracking/day?employeeId=${emp.id}&date=${date}`).set(auth(owner.token)).expect(200)).body.data;
    expect(day.route.length).toBe(5);
    expect(day.punches).toEqual([expect.objectContaining({ type: 'in' })]);
    // Staff see their own route, not someone else's.
    await api().get(`${V}/tracking/day?date=${date}`).set(auth(staff.token)).expect(200);
    expect((await api().get(`${V}/tracking/day?employeeId=${new Types.ObjectId()}&date=${date}`).set(auth(staff.token))).status).toBe(403);
    expect((await api().get(`${V}/tracking/live`).set(auth(staff.token))).status).toBe(403);

    // Points are deleted automatically after 90 days.
    const p = (await LocationPing.findOne({ companyId: owner.companyId }).lean())!;
    expect((p.expireAt.getTime() - Date.now()) / 86_400_000).toBeGreaterThan(89);

    await api().post(`${V}/attendance/check-out`).set(auth(staff.token)).send(punchBody(staff.deviceId)).expect(201);
    expect((await TrackingSession.findOne({ companyId: owner.companyId }).lean())!.endReason).toBe('punch_out');
    expect((await send(staff.token, nowPts(1)).expect(200)).body.data).toMatchObject({ stop: true, reason: 'checked_out' });

    const consent = await AuditLog.findOne({ companyId: owner.companyId, action: 'tracking.consent' }).lean();
    expect(describeLog(consent!, 'en', { employeeName: () => 'Raju' } as any)?.text).toBe('Raju agreed to share location during shifts');
  });

  it('not on Starter/Growth', async () => {
    const { owner, emp } = await setup('growth');
    const r = await api().put(`${V}/tracking/employees/${emp.id}`).set(auth(owner.token)).send({ enabled: true });
    expect(r.status).toBe(402);
    expect(r.body.error.code).toBe('FEATURE_NOT_IN_PLAN');
  });

  it('withdrawing stops today’s sharing and tells the owner; the owner turning it off stops it too', async () => {
    const { owner, emp, staff } = await setup();
    await api().put(`${V}/tracking/employees/${emp.id}`).set(auth(owner.token)).send({ enabled: true }).expect(200);
    await api().post(`${V}/tracking/me/consent`).set(auth(staff.token)).expect(200);
    await api().post(`${V}/attendance/check-in`).set(auth(staff.token)).send(punchBody(staff.deviceId)).expect(201);
    await send(staff.token, nowPts(2)).expect(200);
    const me = (await api().delete(`${V}/tracking/me/consent`).set(auth(staff.token)).expect(200)).body.data;
    expect(me).toMatchObject({ consented: false, shouldShare: false });
    expect((await TrackingSession.findOne({ companyId: owner.companyId }).lean())!.endReason).toBe('consent_withdrawn');
    expect(await Notification.exists({ companyId: owner.companyId, template: 'tracking_alert', title: { $in: ['Raju stopped sharing location', 'Raju ने लोकेशन शेयर करना बंद किया'] } })).toBeTruthy();
    const live = (await api().get(`${V}/tracking/live`).set(auth(owner.token)).expect(200)).body.data;
    expect(live[0].status).toBe('waiting_consent');

    await api().post(`${V}/tracking/me/consent`).set(auth(staff.token)).expect(200);
    await send(staff.token, nowPts(1)).expect(200);
    await api().put(`${V}/tracking/employees/${emp.id}`).set(auth(owner.token)).send({ enabled: false }).expect(200);
    const sessions = await TrackingSession.find({ companyId: owner.companyId }).sort({ startedAt: 1 }).lean();
    expect(sessions.map((s) => s.endReason)).toEqual(['consent_withdrawn', 'turned_off']);
    expect((await send(staff.token, nowPts(1)).expect(200)).body.data).toMatchObject({ stop: true, reason: 'turned_off' });
  });

  it('stops at shift end + 2 hours', async () => {
    const { owner, emp, staff } = await setup();
    await Shift.updateMany({ companyId: owner.companyId }, { $set: { start: '09:00', end: '18:00' } });
    await Employee.updateOne({ _id: emp.id, companyId: owner.companyId }, { $set: { 'tracking.enabled': true, 'tracking.consentAt': new Date() } });
    await api().post(`${V}/attendance/check-in`).set(auth(staff.token)).send(punchBody(staff.deviceId)).expect(201);
    const today = todayIn(TZ);
    const ctx = ctxFor(owner.companyId, emp.id);
    const late = zonedInstant(today, '20:30', TZ);
    expect(await addPings(ctx, [{ at: late.toISOString(), lat: 28.6, lng: 77.2 }], late)).toMatchObject({ stop: true, reason: 'shift_end' });
  });

  it('“not updating” and “location off” alerts: once each, in the daytime; old sessions close by themselves', async () => {
    const { owner, emp, staff } = await setup();
    await Employee.updateOne({ _id: emp.id, companyId: owner.companyId }, { $set: { 'tracking.enabled': true, 'tracking.consentAt': new Date() } });
    const today = todayIn(TZ);
    const noon = zonedInstant(today, '12:00', TZ);
    const s = await TrackingSession.create({
      companyId: owner.companyId,
      employeeId: emp.id,
      date: today,
      startedAt: noon,
      lastPingAt: noon,
      endsBy: zonedInstant(today, '20:00', TZ),
    });
    const company = { _id: new Types.ObjectId(owner.companyId), timezone: TZ };
    expect(await trackingTick(company, at(noon, 10))).toEqual({ ended: 0, alerts: 0 });
    expect(await trackingTick(company, at(noon, 25))).toEqual({ ended: 0, alerts: 1 });
    expect(await trackingTick(company, at(noon, 40))).toEqual({ ended: 0, alerts: 0 });
    expect(await Notification.exists({ companyId: owner.companyId, title: { $in: ["Raju's location hasn't updated for 20 minutes", 'Raju की लोकेशन 20 मिनट से नहीं बदली'] } })).toBeTruthy();

    const ctx = ctxFor(owner.companyId, emp.id);
    await addEvents(ctx, [{ at: at(noon, 41).toISOString(), type: 'location_off' }], at(noon, 41));
    await addEvents(ctx, [{ at: at(noon, 42).toISOString(), type: 'location_off' }], at(noon, 42));
    expect(await Notification.countDocuments({ companyId: owner.companyId, title: { $in: ['Raju turned off location', 'Raju ने लोकेशन बंद की'] }, channel: 'in_app' })).toBe(1);
    // At night nobody is woken up.
    await addEvents(ctx, [{ at: noon.toISOString(), type: 'permission_removed' }], zonedInstant(today, '22:30', TZ));
    expect(await Notification.countDocuments({ companyId: owner.companyId, title: { $in: ['Raju took away the location permission', 'Raju ने लोकेशन की अनुमति हटाई'] } })).toBe(0);

    expect(await trackingTick(company, zonedInstant(today, '20:05', TZ))).toEqual({ ended: 1, alerts: 0 });
    expect((await TrackingSession.findOne({ _id: s._id, companyId: owner.companyId }).lean())!).toMatchObject({ endReason: 'shift_end' });
    void staff;
  });
});

describe('field staff check-in and place names', () => {
  it('field staff check in away from the shop without approval; others still need it', async () => {
    const { owner, emp, staff } = await setup();
    const far = { geo: { lat: 28.6514, lng: 77.1907, accuracyM: 10 } };
    // Not field staff yet: away from the shop needs the owner's approval.
    const before = await api().post(`${V}/attendance/check-in`).set(auth(staff.token)).send(punchBody(staff.deviceId, far));
    expect([201, 422]).toContain(before.status);
    if (before.status === 201) expect(before.body.data.punch.approval).toBe('pending');
    await api().post(`${V}/attendance/check-out`).set(auth(staff.token)).send(punchBody(staff.deviceId, far));

    await api().put(`${V}/tracking/employees/${emp.id}`).set(auth(owner.token)).send({ enabled: true }).expect(200);
    await api().post(`${V}/tracking/me/consent`).set(auth(staff.token)).expect(200);
    const today = (await api().get(`${V}/attendance/today`).set(auth(staff.token)).expect(200)).body.data;
    expect(today.fieldStaff).toBe(true);
    const r = await api().post(`${V}/attendance/check-in`).set(auth(staff.token)).send(punchBody(staff.deviceId, far)).expect(201);
    expect(r.body.data.punch).toMatchObject({ approval: 'not_required', insideGeofence: null });

    // Checked in 40 minutes ago; a point from before that is left out.
    await Attendance.updateOne({ companyId: owner.companyId, employeeId: emp.id, 'punches.type': 'in' }, { $set: { 'punches.$[].clientTime': new Date(Date.now() - 40 * 60_000) } });
    const early = await send(staff.token, [{ at: new Date(Date.now() - 60 * 60_000).toISOString(), lat: 28.6, lng: 77.2 }]).expect(200);
    expect(early.body.data.accepted).toBe(0);
    // A stop at Karol Bagh gets its place name, and so does the live list.
    const base = Date.now() - 30 * 60_000;
    const pts = Array.from({ length: 8 }, (_, i) => ({ at: new Date(base + i * 2 * 60_000).toISOString(), lat: 28.6514 + i * 0.00002, lng: 77.1907, accuracyM: 10 }));
    await send(staff.token, pts).expect(200);
    const live = (await api().get(`${V}/tracking/live`).set(auth(owner.token)).expect(200)).body.data;
    expect(live[0].near).toBe('Ajmal Khan Road, Karol Bagh');
    const day = (await api().get(`${V}/tracking/day?employeeId=${emp.id}&date=${todayIn(TZ)}`).set(auth(owner.token)).expect(200)).body.data;
    expect(day.stops).toEqual([expect.objectContaining({ minutes: 14, place: 'Ajmal Khan Road, Karol Bagh' })]);
  });
});

describe('export and the morning summary', () => {
  it('Excel for the day/month with km and stops; yesterday’s travel in the owner’s summary', async () => {
    const { owner, emp } = await setup();
    await Employee.updateOne({ _id: emp.id, companyId: owner.companyId }, { $set: { 'tracking.enabled': true, 'tracking.consentAt': new Date() } });
    const today = todayIn(TZ);
    const yesterday = addDays(today, -1);
    const start = zonedInstant(yesterday, '10:00', TZ);
    const s = await TrackingSession.create({
      companyId: owner.companyId,
      employeeId: emp.id,
      date: yesterday,
      startedAt: start,
      endedAt: at(start, 120),
      endReason: 'punch_out',
      endsBy: zonedInstant(yesterday, '20:00', TZ),
      distanceM: 4200,
    });
    // A drive, then 20 minutes at Karol Bagh.
    const pts = [
      ...Array.from({ length: 5 }, (_, i) => ({ at: at(start, i * 2), lat: 28.6315 + i * 0.004, lng: 77.2167 - i * 0.005 })),
      ...Array.from({ length: 11 }, (_, i) => ({ at: at(start, 12 + i * 2), lat: 28.6514, lng: 77.1907 })),
    ];
    await LocationPing.insertMany(pts.map((p) => ({ ...p, companyId: owner.companyId, employeeId: emp.id, sessionId: s._id, accuracyM: 10, expireAt: at(start, 90 * 24 * 60) })));

    const r = await api().get(`${V}/tracking/export?month=${yesterday.slice(0, 7)}`).set(auth(owner.token)).buffer(true).parse((res, cb) => {
      const chunks: Buffer[] = [];
      res.on('data', (c: Buffer) => chunks.push(c));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    }).expect(200);
    expect(r.headers['content-disposition']).toContain(`field-staff-${yesterday.slice(0, 7)}.xlsx`);
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(r.body);
    const days = wb.worksheets[0];
    expect(days.getRow(2).getCell(2).value).toBe('Raju');
    expect(days.getRow(2).getCell(6).value).toBe(1);
    const stops = wb.worksheets[1];
    expect(stops.getRow(2).getCell(5).value).toBe(20);
    expect(stops.getRow(2).getCell(6).value).toBe('Ajmal Khan Road, Karol Bagh');
    expect(await AuditLog.exists({ companyId: owner.companyId, action: 'tracking.export' })).toBeTruthy();
    expect((await api().get(`${V}/tracking/export`).set(auth(owner.token))).status).toBe(400);

    const travel = await travelSummary(new Types.ObjectId(owner.companyId), yesterday);
    expect(travel).toEqual([{ name: 'Raju', km: 4.2, stops: 1 }]);
    await sendDigest(new Types.ObjectId(owner.companyId));
    const digest = await Notification.findOne({ companyId: owner.companyId, template: 'daily_digest' }).lean();
    expect(digest!.body).toMatch(/(Yesterday: Raju 4.2 km, 1 stop|कल: Raju 4.2 किमी, 1 रुकाव)/);
  });
});

describe('travel allowance', () => {
  it('km tracked in the month × the business rate becomes a salary line (off by default)', async () => {
    const { owner, emp } = await setup();
    const today = todayIn(TZ);
    await TrackingSession.create({ companyId: owner.companyId, employeeId: emp.id, date: today, startedAt: new Date(), endedAt: new Date(), endsBy: new Date(), distanceM: 42_500 });
    const cid = new Types.ObjectId(owner.companyId);
    let [input] = (await buildEngineInputs(cid, today.slice(0, 7))).filter((i) => i.employee.employeeId === emp.id);
    // Off until the owner sets a rate.
    expect(input.employee.travelKm).toBe(0);
    expect(computePayslip(input).lines.some((l) => l.code === 'travel')).toBe(false);

    await api().patch(`${V}/company/settings`).set(auth(owner.token)).send({ travelRatePaisePerKm: 500 }).expect(200);
    [input] = (await buildEngineInputs(cid, today.slice(0, 7))).filter((i) => i.employee.employeeId === emp.id);
    expect(input.employee).toMatchObject({ travelKm: 42.5, travelRatePaisePerKm: 500 });
    const line = computePayslip(input).lines.find((l) => l.code === 'travel')!;
    expect(line).toMatchObject({ kind: 'earning', amountPaise: 21300, label: { en: 'Travel allowance (42.5 km)' } });
    expect(line.explanation.en).toBe('42.5 km travelled during shifts × ₹5 per km.');
  });
});
