import { Types } from 'mongoose';
import { randomUUID } from 'node:crypto';
import { AppError, notFound } from '../../lib/errors.js';
import { distanceMeters, fromGeoPoint } from '../../lib/geo.js';
import { localDateOf, monthDays, todayIn, weekdayOf, dateRange } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Attendance, Branch, Company, Employee, Holiday, Leave, Shift, User, type AttendanceStatus } from '../../models/index.js';
import { computeDay } from './rules.js';
import { audit } from '../audit/service.js';
import { employeeScope, assertEmployeeInScope } from '../employees/service.js';
import { provider } from '../../providers/registry.js';
import { env } from '../../config/env.js';
import { getConfig } from '../config/service.js';
import { notifyOwners, notifyEmployee } from '../notifications/service.js';
import { companyPlan } from '../billing/plans.js';
import { faceView, matchSelfie, type FaceResult } from '../face/service.js';

export interface PunchInput {
  type: 'in' | 'out';
  clientTime: string;
  geo?: { lat: number; lng: number; accuracyM?: number } | null;
  mockLocation?: boolean;
  /** Phone screen-lock result from the app; absent on older app versions. */
  lockCheck?: 'passed' | 'failed' | 'unavailable';
  deviceId: string;
  selfieBase64?: string | null;
  clientPunchId: string;
}

export type DisplayStatus = 'present' | 'late' | 'checked_in' | 'absent' | 'half_day' | 'leave' | 'holiday' | 'week_off' | 'not_marked';

async function loadEmployeeSetup(companyId: Types.ObjectId, employeeId: Types.ObjectId) {
  const [company, employee] = await Promise.all([Company.findById(companyId).lean(), Employee.findOne({ _id: employeeId, companyId }).lean()]);
  if (!company || !employee) throw notFound('Employee');
  const branch = employee.branchId ? await Branch.findOne({ _id: employee.branchId, companyId }).lean() : await Branch.findOne({ companyId, isDefault: true }).lean();
  const shiftId = employee.shiftId ?? branch?.shiftId;
  const shift = (shiftId ? await Shift.findOne({ _id: shiftId, companyId }).lean() : null) ?? (await Shift.findOne({ companyId, isDefault: true }).lean());
  return { company, employee, branch, shift };
}

const shiftRules = (company: any, shift: any) => ({
  start: shift?.start ?? '09:00',
  end: shift?.end ?? '18:00',
  graceMinutes: shift?.graceMinutes ?? company.settings.graceMinutes ?? 15,
});

/** Re-derive status/late/worked from punches using the rules engine. Overridden records keep their status. */
export function applyRules(record: any, company: any, shift: any, closed: boolean) {
  const r = computeDay({
    date: record.date,
    tz: company.timezone,
    punches: record.punches,
    shift: shiftRules(company, shift),
    halfDayHours: company.settings.halfDayHours,
    missingCheckoutPolicy: company.settings.missingCheckoutPolicy,
    closed,
  });
  record.lateMinutes = r.lateMinutes;
  record.earlyOutMinutes = r.earlyOutMinutes;
  record.workedMinutes = r.workedMinutes;
  const punchFlags = [...new Set(record.punches.flatMap((p: any) => p.flags ?? []))];
  record.flags = [...new Set([...r.flags, ...punchFlags])];
  if (!record.overridden && r.status) {
    record.status = r.status;
    record.leaveType = null;
  }
  return r;
}

export async function punch(ctx: Ctx, input: PunchInput, source: 'app' | 'offline_sync' = 'app') {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Only staff can check in');
  const { company, employee, branch, shift } = await loadEmployeeSetup(ctx.companyId, ctx.employeeId);
  if (employee.status !== 'active') throw new AppError('FORBIDDEN', 'Your staff account is inactive');
  if (!employee.consent?.location) throw new AppError('FORBIDDEN', 'Please accept the location consent first', { reason: 'consent_required' });

  const user = ctx.userId ? await User.findById(ctx.userId).lean() : null;
  if (user && user.deviceIds.length && !user.deviceIds.includes(input.deviceId)) throw new AppError('DEVICE_NOT_BOUND', 'Check-in is allowed only from your registered phone');

  // Idempotency (offline queue may retry).
  const dup = await Attendance.findOne({ companyId: ctx.companyId, employeeId: employee._id, 'punches.clientPunchId': input.clientPunchId }).lean();
  if (dup) return { record: dup, punch: dup.punches.find((p: any) => p.clientPunchId === input.clientPunchId)!, duplicate: true };

  const s = company.settings;
  const now = new Date();
  const deviceTime = new Date(input.clientTime);
  if (Number.isNaN(deviceTime.getTime())) throw new AppError('VALIDATION_ERROR', 'Invalid clientTime');
  const flags: string[] = [];
  const driftMin = Math.abs(now.getTime() - deviceTime.getTime()) / 60000;
  let effective = now; // server time is authoritative for online punches
  if (source === 'offline_sync') {
    if (deviceTime.getTime() > now.getTime() + 5 * 60000) flags.push('device_time_drift');
    else {
      effective = deviceTime;
      const lateHours = await getConfig<number>('attendance.offlineLateSyncHours', ctx.companyId);
      if (driftMin > lateHours * 60) flags.push('late_sync');
    }
  } else if (driftMin > s.maxDeviceTimeDriftMin) flags.push('device_time_drift');
  if (input.mockLocation) flags.push('mock_location');
  if (input.geo?.accuracyM && input.geo.accuracyM > s.minGpsAccuracyM) flags.push('low_accuracy');

  const date = localDateOf(effective, company.timezone);
  const today = todayIn(company.timezone, now);

  // Geofence
  let distanceM: number | null = null;
  let insideGeofence: boolean | null = null;
  let approval: 'not_required' | 'pending' = 'not_required';
  const center = fromGeoPoint(branch?.geo as any);
  if (center && input.geo) {
    distanceM = distanceMeters(center, input.geo);
    insideGeofence = distanceM <= (branch?.radiusM ?? 100);
  } else if (center && !input.geo) {
    insideGeofence = false;
    flags.push('no_location');
  }
  if (insideGeofence === false || input.mockLocation) {
    if (insideGeofence === false) flags.push('outside_geofence');
    if (s.outsideGeofencePolicy === 'block' && source === 'app') {
      throw new AppError('OUTSIDE_GEOFENCE', input.mockLocation ? 'Fake GPS detected. Turn off mock location apps.' : `You are ${distanceM ?? '?'} m away from the shop. Check-in allowed within ${branch?.radiusM ?? 100} m.`, {
        distanceM,
        radiusM: branch?.radiusM ?? 100,
      });
    }
    approval = 'pending';
  }

  // Phone screen lock: never blocks a check-in. "required" sends anything but a pass to the owner.
  const lockPolicy = s.phoneLockPolicy ?? 'recommended';
  if (lockPolicy !== 'off') {
    if (input.lockCheck === 'failed') flags.push('phone_lock_failed');
    if (input.lockCheck === 'unavailable') flags.push('no_phone_lock');
    if (lockPolicy === 'required' && input.lockCheck !== 'passed') {
      // Older app versions send nothing; tag those too so the owner sees why it waits.
      if (!input.lockCheck) flags.push('no_phone_lock');
      approval = 'pending';
    }
  }

  if (s.selfieRequired && !input.selfieBase64 && source === 'app') throw new AppError('VALIDATION_ERROR', 'Selfie is required for check-in');

  let record = await Attendance.findOne({ companyId: ctx.companyId, employeeId: employee._id, date });
  if (!record) record = new Attendance({ companyId: ctx.companyId, employeeId: employee._id, date, punches: [] });

  const valid = record.punches.filter((p: any) => p.approval !== 'rejected').sort((a: any, b: any) => a.clientTime - b.clientTime);
  const last = valid[valid.length - 1];
  if (source === 'app') {
    if (input.type === 'in' && last?.type === 'in') throw new AppError('CONFLICT', 'You are already checked in');
    if (input.type === 'out' && (!last || last.type === 'out')) throw new AppError('CONFLICT', 'Check in first');
  }

  const punchId = new Types.ObjectId();
  let selfieKey: string | null = null;
  let face: { result: FaceResult; similarity: number | null } | null = null;
  if (input.selfieBase64) {
    const buf = Buffer.from(input.selfieBase64.replace(/^data:image\/\w+;base64,/, ''), 'base64');
    if (buf.length > 2_000_000) throw new AppError('VALIDATION_ERROR', 'Selfie too large (max 2 MB)');
    selfieKey = `selfies/${ctx.companyId}/${date}/${employee._id}-${punchId}.jpg`;
    await (await provider('storage')).put(selfieKey, buf, 'image/jpeg');
    // Face check: only for approved photos, on plans that include it. Never blocks a check-in.
    if (s.faceMatchPolicy === 'review' && employee.face?.status === 'approved' && employee.face.refKey) {
      const { plan } = await companyPlan(company);
      if (plan.features.includes('face_match')) {
        face = await matchSelfie(employee, buf);
        if (face.result !== 'match') flags.push(face.result === 'error' ? 'face_check_failed' : `face_${face.result}`);
        if (face.result !== 'match' && face.result !== 'error') approval = 'pending';
      }
    }
  }

  record.punches.push({
    _id: punchId,
    type: input.type,
    clientTime: effective,
    deviceTime,
    serverTime: now,
    geo: input.geo ? { lat: input.geo.lat, lng: input.geo.lng, accuracyM: input.geo.accuracyM } : undefined,
    distanceM,
    insideGeofence,
    selfieKey,
    mockLocation: !!input.mockLocation,
    lockCheck: lockPolicy === 'off' ? null : (input.lockCheck ?? null),
    face: face ?? undefined,
    deviceId: input.deviceId,
    clientPunchId: input.clientPunchId,
    source,
    flags,
    approval,
  } as any);
  applyRules(record, company, shift, date < today);
  await record.save();

  if (approval === 'pending') {
    await notifyOwners(ctx.companyId, {
      template: 'punch_approval',
      title: 'Check-in needs approval',
      titleHi: 'पंच को मंज़ूरी चाहिए',
      body:
        insideGeofence === false || input.mockLocation
          ? `${employee.name} punched ${input.type} ${distanceM ?? '?'} m away from the shop`
          : face && face.result !== 'match' && face.result !== 'error'
            ? `${employee.name}'s selfie does not clearly match their face photo`
            : `${employee.name} punched ${input.type} without unlocking their phone`,
      bodyHi:
        insideGeofence === false || input.mockLocation
          ? `${employee.name} ने दुकान से ${distanceM ?? '?'} मीटर दूर पंच किया`
          : face && face.result !== 'match' && face.result !== 'error'
            ? `${employee.name} की सेल्फ़ी उनकी चेहरे की फ़ोटो से साफ़ मेल नहीं खाती`
            : `${employee.name} ने फ़ोन लॉक खोले बिना पंच किया`,
      data: { type: 'punch_approval', attendanceId: String(record._id), punchId: String(punchId) },
    });
  }
  return { record: record.toObject(), punch: record.punches.find((p: any) => String(p._id) === String(punchId))!.toObject?.() ?? record.punches[record.punches.length - 1], duplicate: false };
}

export async function syncPunches(ctx: Ctx, punches: PunchInput[]) {
  const sorted = [...punches].sort((a, b) => new Date(a.clientTime).getTime() - new Date(b.clientTime).getTime());
  const results: { clientPunchId: string; ok: boolean; error?: { code: string; message: string }; punch?: any }[] = [];
  for (const p of sorted) {
    try {
      const r = await punch(ctx, p, 'offline_sync');
      results.push({ clientPunchId: p.clientPunchId, ok: true, punch: await punchView(r.punch) });
    } catch (e: any) {
      results.push({ clientPunchId: p.clientPunchId, ok: false, error: { code: e?.code ?? 'INTERNAL', message: e?.message ?? 'failed' } });
    }
  }
  return { results };
}

// ---------- Views ----------
export async function punchView(p: any) {
  const storage = await provider('storage');
  return {
    id: String(p._id),
    type: p.type,
    clientTime: p.clientTime,
    deviceTime: p.deviceTime ?? null,
    serverTime: p.serverTime,
    geo: p.geo?.lat !== undefined && p.geo?.lat !== null ? { lat: p.geo.lat, lng: p.geo.lng, accuracyM: p.geo.accuracyM ?? null } : null,
    distanceM: p.distanceM ?? null,
    insideGeofence: p.insideGeofence ?? null,
    selfieUrl: p.selfieKey ? await storage.signedUrl(p.selfieKey, env.SIGNED_URL_TTL_SEC) : null,
    mockLocation: !!p.mockLocation,
    lockCheck: p.lockCheck ?? null,
    face: p.face?.result ? { result: p.face.result, similarity: p.face.similarity ?? null } : null,
    deviceId: p.deviceId ?? null,
    source: p.source,
    flags: p.flags ?? [],
    approval: p.approval,
  };
}

export async function attendanceView(r: any) {
  return {
    id: String(r._id),
    employeeId: String(r.employeeId),
    date: r.date,
    status: r.status ?? null,
    leaveType: r.leaveType ?? null,
    punches: await Promise.all((r.punches ?? []).map(punchView)),
    lateMinutes: r.lateMinutes ?? 0,
    earlyOutMinutes: r.earlyOutMinutes ?? 0,
    workedMinutes: r.workedMinutes ?? 0,
    overridden: !!r.overridden,
    overrideReason: r.overrideReason ?? null,
    flags: r.flags ?? [],
  };
}

/** Context needed to classify days without punches: holidays, week offs, approved leaves. */
export async function dayContext(companyId: Types.ObjectId, from: string, to: string, employeeIds: Types.ObjectId[]) {
  const [holidays, leaves, shifts, company] = await Promise.all([
    Holiday.find({ companyId, deletedAt: null, date: { $gte: from, $lte: to } }).lean(),
    Leave.find({ companyId, employeeId: { $in: employeeIds }, status: 'approved', deletedAt: null, from: { $lte: to }, to: { $gte: from } }).lean(),
    Shift.find({ companyId }).lean(),
    Company.findById(companyId).lean(),
  ]);
  const holidaySet = new Map(holidays.map((h) => [h.date, h.name]));
  const shiftById = new Map(shifts.map((s) => [String(s._id), s]));
  const defaultShift = shifts.find((s) => s.isDefault) ?? shifts[0];
  const leaveIndex = new Map<string, { type: 'paid' | 'sick' | 'unpaid'; halfDay: boolean }>();
  for (const l of leaves) for (const d of dateRange(l.from, l.to)) leaveIndex.set(`${l.employeeId}:${d}`, { type: l.type as any, halfDay: !!l.halfDay });
  return {
    company: company!,
    holidayName: (d: string) => holidaySet.get(d) ?? null,
    shiftOf: (emp: any) => (emp.shiftId && shiftById.get(String(emp.shiftId))) || defaultShift,
    isWeekOff: (emp: any, d: string) => {
      const sh = (emp.shiftId && shiftById.get(String(emp.shiftId))) || defaultShift;
      return (sh?.weeklyOff ?? [0]).includes(weekdayOf(d));
    },
    leaveOn: (empId: Types.ObjectId | string, d: string) => leaveIndex.get(`${empId}:${d}`) ?? null,
  };
}

/** Status a day would have with no punches. */
export function implicitStatus(dc: Awaited<ReturnType<typeof dayContext>>, emp: any, d: string): { status: AttendanceStatus; leaveType?: 'paid' | 'sick' | 'unpaid' } | null {
  const leave = dc.leaveOn(emp._id, d);
  if (leave) return leave.halfDay ? { status: 'half_day' } : { status: 'leave', leaveType: leave.type };
  if (dc.holidayName(d)) return { status: 'holiday' };
  if (dc.isWeekOff(emp, d)) return { status: 'week_off' };
  return null;
}

export function displayStatusOf(record: any | null, implicit: { status: string } | null, closed: boolean): DisplayStatus {
  if (record?.status) {
    if (record.status === 'present') {
      const open = !closed && record.punches?.length && !record.overridden && lastValidPunch(record)?.type === 'in';
      if ((record.lateMinutes ?? 0) > 0) return 'late';
      return open ? 'checked_in' : 'present';
    }
    return record.status as DisplayStatus;
  }
  if (implicit) return implicit.status as DisplayStatus;
  return 'not_marked';
}

const lastValidPunch = (r: any) =>
  [...(r.punches ?? [])].filter((p: any) => p.approval !== 'rejected' && p.approval !== 'pending').sort((a: any, b: any) => +new Date(a.clientTime) - +new Date(b.clientTime)).pop();

const employedOn = (e: any, d: string) => (!e.joiningDate || e.joiningDate <= d) && (!e.exitDate || e.exitDate >= d);

export async function dayView(ctx: Ctx, date: string) {
  const company = await Company.findById(ctx.companyId).lean();
  const emps = (await Employee.find({ ...employeeScope(ctx), status: { $in: ['active', 'inactive'] } }).sort({ name: 1 }).lean()).filter(
    (e) => employedOn(e, date) && (e.status === 'active' || (e.exitDate && e.exitDate >= date)),
  );
  const records = await Attendance.find({ companyId: ctx.companyId, date, employeeId: { $in: emps.map((e) => e._id) } }).lean();
  const byEmp = new Map(records.map((r) => [String(r.employeeId), r]));
  const dc = await dayContext(ctx.companyId, date, date, emps.map((e) => e._id));
  const closed = date < todayIn(company!.timezone);
  return Promise.all(
    emps.map(async (e) => {
      const r = byEmp.get(String(e._id)) ?? null;
      return {
        employee: { id: String(e._id), name: e.name, phone: e.phone, designation: e.designation ?? null },
        record: r ? await attendanceView(r) : null,
        displayStatus: displayStatusOf(r, implicitStatus(dc, e, date), closed),
      };
    }),
  );
}

export async function todayForEmployee(ctx: Ctx) {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Staff only');
  const { company, employee, branch, shift } = await loadEmployeeSetup(ctx.companyId, ctx.employeeId);
  const date = todayIn(company.timezone);
  const r = await Attendance.findOne({ companyId: ctx.companyId, employeeId: employee._id, date }).lean();
  const dc = await dayContext(ctx.companyId, date, date, [employee._id]);
  const { branchView, shiftView } = await import('../views.js');
  return {
    date,
    record: r ? await attendanceView(r) : null,
    displayStatus: displayStatusOf(r, implicitStatus(dc, employee, date), false),
    nextAction: r && lastValidPunch(r)?.type === 'in' ? 'check_out' : 'check_in',
    shift: shift ? shiftView(shift) : null,
    branch: branch ? branchView(branch) : null,
  };
}

const CODE: Record<DisplayStatus, string> = { present: 'P', late: 'P', checked_in: 'P', absent: 'A', half_day: 'HD', leave: 'L', holiday: 'H', week_off: 'WO', not_marked: '-' };

export async function monthGrid(ctx: Ctx, month: string, employeeId?: string) {
  const company = await Company.findById(ctx.companyId).lean();
  const f: any = { ...employeeScope(ctx) };
  if (employeeId) f._id = ctx.role === 'employee' ? ctx.employeeId : employeeId;
  const days = monthDays(month);
  const emps = (await Employee.find(f).sort({ name: 1 }).lean()).filter((e) => days.some((d) => employedOn(e, d)) && (e.status === 'active' || (e.exitDate ?? '') >= days[0]));
  const records = await Attendance.find({ companyId: ctx.companyId, employeeId: { $in: emps.map((e) => e._id) }, date: { $gte: days[0], $lte: days[days.length - 1] } }).lean();
  const idx = new Map(records.map((r) => [`${r.employeeId}:${r.date}`, r]));
  const dc = await dayContext(ctx.companyId, days[0], days[days.length - 1], emps.map((e) => e._id));
  const today = todayIn(company!.timezone);
  const rows = emps.map((e) => {
    const out: Record<string, DisplayStatus | null> = {};
    const totals = { present: 0, late: 0, absent: 0, halfDay: 0, leave: 0, holiday: 0, weekOff: 0, notMarked: 0 };
    for (const d of days) {
      if (!employedOn(e, d) || d > today) {
        out[d] = null;
        continue;
      }
      const ds = displayStatusOf(idx.get(`${e._id}:${d}`) ?? null, implicitStatus(dc, e, d), d < today);
      out[d] = ds;
      if (ds === 'present' || ds === 'checked_in') totals.present++;
      else if (ds === 'late') {
        totals.present++;
        totals.late++;
      }
      else if (ds === 'absent') totals.absent++;
      else if (ds === 'half_day') totals.halfDay++;
      else if (ds === 'leave') totals.leave++;
      else if (ds === 'holiday') totals.holiday++;
      else if (ds === 'week_off') totals.weekOff++;
      else totals.notMarked++;
    }
    return { employee: { id: String(e._id), name: e.name, phone: e.phone }, days: out, codes: Object.fromEntries(Object.entries(out).map(([d, s]) => [d, s ? CODE[s] : ''])), totals };
  });
  return { month, days, rows };
}

export async function overrideDay(ctx: Ctx, input: { employeeId: string; date: string; status: AttendanceStatus; leaveType?: 'paid' | 'sick' | 'unpaid'; reason: string }) {
  const emp = await assertEmployeeInScope(ctx, input.employeeId);
  if (input.status === 'leave' && !input.leaveType) input.leaveType = 'paid';
  let r = await Attendance.findOne({ companyId: ctx.companyId, employeeId: emp._id, date: input.date });
  const before = r?.toObject() ?? null;
  if (!r) r = new Attendance({ companyId: ctx.companyId, employeeId: emp._id, date: input.date, punches: [] });
  r.status = input.status;
  r.leaveType = input.status === 'leave' ? input.leaveType! : null;
  r.overridden = true;
  r.overrideReason = input.reason;
  r.overriddenBy = ctx.userId ?? undefined;
  r.autoMarked = false;
  if (input.status !== 'present') r.lateMinutes = 0;
  await r.save();
  await audit(ctx, { action: 'attendance.override', entity: 'attendance', entityId: r._id, before, after: r });
  return r;
}

/** Undo an owner override: status goes back to what punches / leave / holiday imply (may be unmarked). */
export async function clearOverride(ctx: Ctx, input: { employeeId: string; date: string; reason: string }) {
  const emp = await assertEmployeeInScope(ctx, input.employeeId);
  const r = await Attendance.findOne({ companyId: ctx.companyId, employeeId: emp._id, date: input.date });
  if (!r) return null;
  const before = r.toObject();
  r.overridden = false;
  r.overrideReason = undefined;
  r.overriddenBy = undefined;
  r.status = null;
  r.leaveType = null;
  r.lateMinutes = 0;
  if (r.punches.length) {
    const { company, shift } = await loadEmployeeSetup(ctx.companyId, emp._id);
    applyRules(r, company, shift, input.date < todayIn(company.timezone));
  }
  await r.save();
  await audit(ctx, { action: 'attendance.override.clear', entity: 'attendance', entityId: r._id, before, after: { ...r.toObject(), reason: input.reason } });
  return r;
}

export async function decidePunch(ctx: Ctx, attendanceId: string, punchId: string, approve: boolean) {
  const r = await Attendance.findOne({ _id: attendanceId, companyId: ctx.companyId });
  if (!r) throw notFound('Attendance');
  await assertEmployeeInScope(ctx, r.employeeId);
  const p: any = r.punches.find((x: any) => String(x._id) === punchId);
  if (!p) throw notFound('Punch');
  if (p.approval !== 'pending') throw new AppError('CONFLICT', 'Already decided');
  const before = r.toObject();
  p.approval = approve ? 'approved' : 'rejected';
  const { company, shift } = await loadEmployeeSetup(ctx.companyId, r.employeeId);
  applyRules(r, company, shift, r.date < todayIn(company.timezone));
  await r.save();
  await audit(ctx, { action: approve ? 'attendance.punch.approve' : 'attendance.punch.reject', entity: 'attendance', entityId: r._id, before, after: r });
  await notifyEmployee(ctx.companyId, r.employeeId, {
    template: 'punch_decision',
    title: approve ? 'Check-in approved' : 'Check-in rejected',
    titleHi: approve ? 'पंच मंज़ूर' : 'पंच नामंज़ूर',
    body: `${r.date}`,
    bodyHi: `${r.date}`,
    data: { type: 'punch_decision', date: r.date },
  });
  return r;
}

/** Nightly 11:59 PM job body for one company + date (PRD F4). Idempotent. */
export async function closeDay(companyId: Types.ObjectId, date: string) {
  const company = await Company.findById(companyId).lean();
  if (!company) return { marked: 0 };
  // Never auto-mark days before the employee was added to StaffMint.
  const emps = (await Employee.find({ companyId, status: 'active', deletedAt: null }).lean()).filter(
    (e) => employedOn(e, date) && (!e.createdAt || localDateOf(e.createdAt, company.timezone) <= date),
  );
  const dc = await dayContext(companyId, date, date, emps.map((e) => e._id));
  const records = await Attendance.find({ companyId, date, employeeId: { $in: emps.map((e) => e._id) } });
  const byEmp = new Map(records.map((r) => [String(r.employeeId), r]));
  let marked = 0;
  for (const e of emps) {
    const r = byEmp.get(String(e._id));
    if (r && r.punches.length) {
      if (!r.overridden) {
        applyRules(r, company, dc.shiftOf(e), true);
        await r.save();
      }
      continue;
    }
    if (r?.status) continue;
    const imp = implicitStatus(dc, e, date);
    await Attendance.updateOne(
      { companyId, employeeId: e._id, date },
      { $set: { status: imp?.status ?? 'absent', leaveType: imp?.leaveType ?? null, autoMarked: true }, $setOnInsert: { companyId, employeeId: e._id, date, punches: [] } },
      { upsert: true },
    );
    marked++;
  }
  return { marked };
}

export async function dashboardToday(ctx: Ctx) {
  const company = await Company.findById(ctx.companyId).lean();
  const date = todayIn(company!.timezone);
  const rows = await dayView(ctx, date);
  const counts = { total: rows.length, present: 0, late: 0, absent: 0, onLeave: 0, notMarked: 0, checkedIn: 0, halfDay: 0, off: 0 };
  for (const r of rows) {
    switch (r.displayStatus) {
      case 'present':
        counts.present++;
        break;
      case 'checked_in':
        counts.present++;
        counts.checkedIn++;
        break;
      case 'late':
        counts.present++;
        counts.late++;
        break;
      case 'absent':
        counts.absent++;
        break;
      case 'half_day':
        counts.present++;
        counts.halfDay++;
        break;
      case 'leave':
        counts.onLeave++;
        break;
      case 'holiday':
      case 'week_off':
        counts.off++;
        break;
      default:
        counts.notMarked++;
    }
  }
  const scopeIds = rows.map((r) => new Types.ObjectId(r.employee.id));
  const { leaveView } = await import('../views.js');
  const leaveRequests = (await Leave.find({ companyId: ctx.companyId, status: 'pending', deletedAt: null, employeeId: { $in: scopeIds } }).sort({ createdAt: 1 }).populate('employeeId', 'name').lean()).map((l) => leaveView(l));
  const pending = await Attendance.find({ companyId: ctx.companyId, 'punches.approval': 'pending', employeeId: { $in: scopeIds } }).populate('employeeId', 'name face').lean();
  const punchApprovals = [];
  for (const r of pending)
    for (const p of r.punches.filter((x: any) => x.approval === 'pending')) {
      const emp = r.employeeId as any;
      // The approved face photo sits next to the selfie when the face check flagged it.
      const facePhotoUrl = p.face?.result && emp?.face?.refKey ? (await faceView(emp)).photoUrl : null;
      punchApprovals.push({ attendanceId: String(r._id), employeeName: emp?.name, date: r.date, punch: await punchView(p), facePhotoUrl });
    }
  const faceEnrollments = await Promise.all(
    (await Employee.find({ companyId: ctx.companyId, 'face.status': 'pending', status: 'active', _id: { $in: scopeIds } }).lean()).map(async (e) => ({
      employeeId: String(e._id),
      employeeName: e.name,
      ...(await faceView(e)),
    })),
  );
  const flagged = await Attendance.find({ companyId: ctx.companyId, date: { $gte: date.slice(0, 8) + '01' }, flags: { $in: ['mock_location', 'device_time_drift', 'needs_review', 'late_sync', 'phone_lock_failed', 'face_check_failed'] }, employeeId: { $in: scopeIds } })
    .sort({ date: -1 })
    .limit(20)
    .populate('employeeId', 'name')
    .lean();
  const { activeStaffCount, companyPlan } = await import('../billing/plans.js');
  const { plan } = await companyPlan({ _id: ctx.companyId });
  return {
    date,
    counts,
    needsAction: {
      leaveRequests,
      punchApprovals,
      faceEnrollments,
      flags: flagged.map((r) => ({ attendanceId: String(r._id), employeeName: (r.employeeId as any)?.name, date: r.date, flags: r.flags })),
    },
    plan: { code: plan.code, staffCount: await activeStaffCount(ctx.companyId), staffLimit: plan.staffLimit },
  };
}

export const newClientPunchId = () => randomUUID();
