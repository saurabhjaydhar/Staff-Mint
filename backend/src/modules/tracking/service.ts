import { DateTime } from 'luxon';
import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import type { Ctx } from '../../lib/context.js';
import { todayIn, zonedInstant } from '../../lib/dates.js';
import { Attendance, Branch, Company, Employee, LocationPing, Shift, TrackingSession } from '../../models/index.js';
import { audit } from '../audit/service.js';
import { assertEmployeeInScope } from '../employees/service.js';
import { getConfig } from '../config/service.js';
import { notifyEmployee, notifyOwners } from '../notifications/service.js';
import { rosterShiftOn } from '../attendance/service.js';
import { companyPlan } from '../billing/plans.js';
import { distanceOf, simplify, stopsOf } from './route.js';
import { provider } from '../../providers/registry.js';
import { logger } from '../../lib/logger.js';

/** Short place names ("Ajmal Khan Road, Karol Bagh") for points, cached by ~100 m so each place is looked up once. */
const placeCache = new Map<string, string | null>();
export async function placeName(lat: number, lng: number, lang: 'en' | 'hi' = 'en') {
  const key = `${lat.toFixed(3)},${lng.toFixed(3)},${lang}`;
  if (placeCache.has(key)) return placeCache.get(key)!;
  let name: string | null;
  try {
    const { address } = await (await provider('geo')).reverseGeocode(lat, lng, lang);
    // No real place, just coordinates back: show nothing rather than numbers.
    name = address && !/^-?\d+\.\d+,\s*-?\d+\.\d+$/.test(address.trim()) ? address.split(',').slice(0, 2).join(',').trim() : null;
  } catch (err) {
    logger.warn({ err }, 'reverse geocode failed');
    return null;
  }
  if (placeCache.size > 5000) placeCache.clear();
  placeCache.set(key, name);
  return name;
}

/** Bumped when the consent wording changes; the person's agreement records which version they saw. */
export const CONSENT_VERSION = '2026-10';

export const CONSENT_TEXT = {
  en: [
    'While you are checked in, the app shares your location with your employer about every 2 minutes.',
    'It starts when you check in and stops when you check out, or 2 hours after your shift ends. Never at other times.',
    'Your employer sees where you are, your route for the day and how far you travelled.',
    'You can see your own route too. Points are deleted after 90 days.',
    'You can stop sharing at any time from your profile. Your employer will be told.',
  ],
  hi: [
    'चेक-इन रहते हुए ऐप लगभग हर 2 मिनट में आपकी लोकेशन मालिक के साथ शेयर करता है।',
    'यह चेक-इन पर शुरू होता है और चेक-आउट पर, या शिफ़्ट ख़त्म होने के 2 घंटे बाद बंद हो जाता है। बाक़ी समय कभी नहीं।',
    'मालिक देखते हैं कि आप कहाँ हैं, दिन का रास्ता और कितना चले।',
    'आप भी अपना रास्ता देख सकते हैं। लोकेशन 90 दिन बाद हट जाती है।',
    'प्रोफ़ाइल से कभी भी शेयर करना बंद कर सकते हैं। मालिक को बताया जाएगा।',
  ],
};

const MAX_BATCH = 100;

async function settings(companyId: Types.ObjectId) {
  const [intervalSec, distanceM, keepDays, staleMinutes] = await Promise.all([
    getConfig<number>('tracking.intervalSec', companyId),
    getConfig<number>('tracking.distanceM', companyId),
    getConfig<number>('tracking.keepDays', companyId),
    getConfig<number>('tracking.staleMinutes', companyId),
  ]);
  return { intervalSec, distanceM, keepDays, staleMinutes };
}

/** Alerts only in the daytime (7 AM to 10 PM company time), like other alerts. */
const daytime = (tz: string, now: Date) => {
  const h = DateTime.fromJSDate(now).setZone(tz).hour;
  return h >= 7 && h < 22;
};

/** Sharing must stop by shift end + 2 hours, and never after 11:59 PM. */
async function endsByFor(company: { _id: Types.ObjectId; timezone: string }, emp: any, date: string) {
  const branch = emp.branchId ? await Branch.findOne({ _id: emp.branchId, companyId: company._id }).lean() : await Branch.findOne({ companyId: company._id, isDefault: true }).lean();
  const shiftId = emp.shiftId ?? branch?.shiftId;
  const shift =
    (await rosterShiftOn(company._id, emp._id, date)) ??
    (shiftId ? await Shift.findOne({ _id: shiftId, companyId: company._id }).lean() : null) ??
    (await Shift.findOne({ companyId: company._id, isDefault: true }).lean());
  const midnight = zonedInstant(date, '23:59', company.timezone);
  const end = shift?.end && shift.start && shift.end > shift.start ? zonedInstant(date, shift.end, company.timezone) : midnight;
  const by = new Date(end.getTime() + 2 * 3_600_000);
  return by < midnight ? { at: by, reason: 'shift_end' as const } : { at: midnight, reason: 'midnight' as const };
}

/** When they checked in, if their last check-in/out today (ignoring rejected ones) is a check-in; else null. */
async function checkedInAt(companyId: Types.ObjectId, employeeId: Types.ObjectId, date: string): Promise<Date | null> {
  const a = await Attendance.findOne({ companyId, employeeId, date }).lean();
  const punches = (a?.punches ?? []).filter((p: any) => p.approval !== 'rejected').sort((x: any, y: any) => +new Date(x.clientTime) - +new Date(y.clientTime));
  const last = punches[punches.length - 1];
  return last?.type === 'in' ? new Date(last.clientTime) : null;
}
const checkedIn = async (companyId: Types.ObjectId, employeeId: Types.ObjectId, date: string) => !!(await checkedInAt(companyId, employeeId, date));

async function openSession(companyId: Types.ObjectId, employeeId: Types.ObjectId) {
  return TrackingSession.findOne({ companyId, employeeId, endedAt: null }).sort({ startedAt: -1 });
}

/** Ends today's sharing (punch-out, shift over, consent withdrawn, owner turned it off). */
export async function endOpenSession(companyId: Types.ObjectId, employeeId: Types.ObjectId, reason: 'punch_out' | 'shift_end' | 'midnight' | 'consent_withdrawn' | 'turned_off', at = new Date()) {
  await TrackingSession.updateMany({ companyId, employeeId, endedAt: null }, { $set: { endedAt: at, endReason: reason } });
}

// ---------------------------------------------------------------- owner

/** Owner/manager: this person is field staff and shares location during the shift (after they agree). */
export async function setTracking(ctx: Ctx, employeeId: string, enabled: boolean) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  if (enabled) {
    const { plan } = await companyPlan({ _id: ctx.companyId });
    if (!plan.features.includes('tracking')) throw new AppError('FEATURE_NOT_IN_PLAN', 'Field staff location is on the Pro plan', { feature: 'tracking' });
  }
  const was = !!emp.tracking?.enabled;
  await Employee.updateOne({ _id: emp._id, companyId: ctx.companyId }, { $set: { 'tracking.enabled': enabled, 'tracking.enabledAt': enabled ? new Date() : null } });
  if (!enabled) await endOpenSession(ctx.companyId, emp._id, 'turned_off');
  if (was !== enabled) {
    await audit(ctx, { action: enabled ? 'tracking.enable' : 'tracking.disable', entity: 'employee', entityId: emp._id });
    if (enabled && !emp.tracking?.consentAt) {
      const company = (await Company.findById(ctx.companyId).select('name').lean())!;
      await notifyEmployee(ctx.companyId, emp._id, {
        template: 'tracking_request',
        title: `${company.name} asks to see your location during work`,
        titleHi: `${company.name} काम के दौरान आपकी लोकेशन देखना चाहते हैं`,
        body: 'Only while you are checked in. Open the app to read and agree.',
        bodyHi: 'सिर्फ़ चेक-इन रहते हुए। ऐप खोलकर पढ़ें और हाँ कहें।',
        data: { type: 'tracking' },
      });
    }
  }
  const fresh = (await Employee.findOne({ _id: emp._id, companyId: ctx.companyId }).lean())!;
  return { enabled: !!fresh.tracking?.enabled, consented: !!fresh.tracking?.consentAt };
}

type LiveStatus = 'waiting_consent' | 'not_started' | 'live' | 'recent' | 'stale' | 'ended';

/** Owner/manager: every field staff member's latest point and today's distance. */
export async function live(ctx: Ctx, now = new Date()) {
  const company = (await Company.findById(ctx.companyId).select('timezone').lean())!;
  const today = todayIn(company.timezone, now);
  const f: Record<string, unknown> = { companyId: ctx.companyId, status: 'active', 'tracking.enabled': true };
  if (ctx.role === 'manager' && ctx.branchIds.length) f.branchId = { $in: ctx.branchIds };
  const emps = await Employee.find(f).select('name tracking branchId').sort({ name: 1 }).lean();
  const sessions = await TrackingSession.find({ companyId: ctx.companyId, date: today, employeeId: { $in: emps.map((e) => e._id) } }).sort({ startedAt: 1 }).lean();
  const rows = emps.map((e) => {
    const mine = sessions.filter((s) => String(s.employeeId) === String(e._id));
    const s = mine[mine.length - 1];
    const ageMin = s?.lastPingAt ? (now.getTime() - s.lastPingAt.getTime()) / 60_000 : null;
    const status: LiveStatus = !e.tracking?.consentAt
      ? 'waiting_consent'
      : !s
        ? 'not_started'
        : s.endedAt
          ? 'ended'
          : ageMin === null || ageMin >= 15
            ? 'stale'
            : ageMin >= 5
              ? 'recent'
              : 'live';
    return {
      employeeId: String(e._id),
      name: e.name,
      status,
      lastPingAt: s?.lastPingAt ?? null,
      lat: s?.last?.lat ?? null,
      lng: s?.last?.lng ?? null,
      battery: s?.last?.battery ?? null,
      distanceM: mine.reduce((n, x) => n + (x.distanceM ?? 0), 0),
      endReason: s?.endReason ?? null,
      lastEvent: s?.events?.length ? s.events[s.events.length - 1] : null,
      near: null as string | null,
    };
  });
  for (const r of rows) if (r.lat != null && r.lng != null) r.near = await placeName(r.lat, r.lng, ctx.language);
  return rows;
}

/** One person's day: route, stops, distance, check-in/out and what happened. Staff may see their own. */
export async function day(ctx: Ctx, employeeId: string | null, date: string) {
  let empId: Types.ObjectId;
  if (ctx.role === 'employee' || (ctx.role === 'manager' && !employeeId)) {
    if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Staff only');
    if (employeeId && employeeId !== String(ctx.employeeId)) throw new AppError('FORBIDDEN', 'You can see only your own route');
    empId = ctx.employeeId;
  } else {
    if (!employeeId) throw new AppError('VALIDATION_ERROR', 'Pick a person');
    empId = (await assertEmployeeInScope(ctx, employeeId))._id;
  }
  const emp = (await Employee.findOne({ _id: empId, companyId: ctx.companyId }).select('name').lean())!;
  const sessions = await TrackingSession.find({ companyId: ctx.companyId, employeeId: empId, date }).sort({ startedAt: 1 }).lean();
  const pings = sessions.length
    ? await LocationPing.find({ companyId: ctx.companyId, sessionId: { $in: sessions.map((s) => s._id) } }).sort({ at: 1 }).select('at lat lng accuracyM').lean()
    : [];
  const att = await Attendance.findOne({ companyId: ctx.companyId, employeeId: empId, date }).lean();
  const route = simplify(pings);
  return {
    employeeId: String(empId),
    name: emp.name,
    date,
    distanceM: distanceOf(pings),
    route: route.map((p) => ({ at: p.at, lat: p.lat, lng: p.lng })),
    stops: await Promise.all(stopsOf(pings).map(async (s) => ({ ...s, place: await placeName(s.lat, s.lng, ctx.language) }))),
    punches: (att?.punches ?? [])
      .filter((p: any) => p.approval !== 'rejected' && p.geo?.lat != null)
      .map((p: any) => ({ type: p.type, at: p.clientTime, lat: p.geo.lat, lng: p.geo.lng })),
    sessions: sessions.map((s) => ({ startedAt: s.startedAt, endedAt: s.endedAt, endReason: s.endReason, events: s.events ?? [] })),
  };
}

// ---------------------------------------------------------------- staff

function staffOnly(ctx: Ctx) {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Staff only');
  return ctx.employeeId;
}

/** Staff phone: should it share location now, how often, and the consent words. */
export async function mine(ctx: Ctx, now = new Date()) {
  const employeeId = staffOnly(ctx);
  const [emp, company] = await Promise.all([
    Employee.findOne({ _id: employeeId, companyId: ctx.companyId }).lean(),
    Company.findById(ctx.companyId).select('name timezone').lean(),
  ]);
  if (!emp || !company) throw notFound('Employee');
  const today = todayIn(company.timezone, now);
  const s = await openSession(ctx.companyId, employeeId);
  const cfg = await settings(ctx.companyId);
  const enabled = !!emp.tracking?.enabled;
  const consented = !!emp.tracking?.consentAt;
  const inNow = enabled && consented ? await checkedIn(ctx.companyId, employeeId, today) : false;
  const todayDistance = (await TrackingSession.find({ companyId: ctx.companyId, employeeId, date: today }).select('distanceM').lean()).reduce((n, x) => n + (x.distanceM ?? 0), 0);
  return {
    businessName: company.name,
    enabled,
    consented,
    /** The phone should be sharing right now (enabled, agreed, checked in). */
    shouldShare: enabled && consented && inNow,
    sharing: !!s,
    endsBy: s?.endsBy ?? (inNow ? (await endsByFor(company, emp, today)).at : null),
    distanceM: todayDistance,
    intervalSec: cfg.intervalSec,
    minDistanceM: cfg.distanceM,
    consentText: CONSENT_TEXT,
  };
}

export async function giveConsent(ctx: Ctx) {
  const employeeId = staffOnly(ctx);
  const emp = await Employee.findOne({ _id: employeeId, companyId: ctx.companyId }).lean();
  if (!emp?.tracking?.enabled) throw new AppError('CONFLICT', 'Your employer hasn’t asked for this');
  if (!emp.tracking.consentAt) {
    await Employee.updateOne({ _id: employeeId, companyId: ctx.companyId }, { $set: { 'tracking.consentAt': new Date(), 'tracking.consentVersion': CONSENT_VERSION } });
    await audit(ctx, { action: 'tracking.consent', entity: 'employee', entityId: employeeId, after: { version: CONSENT_VERSION } });
  }
  return mine(ctx);
}

/** Stop sharing (DPDP withdrawal): today's sharing ends now and the owner is told. */
export async function withdrawConsent(ctx: Ctx) {
  const employeeId = staffOnly(ctx);
  const emp = await Employee.findOne({ _id: employeeId, companyId: ctx.companyId }).lean();
  if (emp?.tracking?.consentAt) {
    await Employee.updateOne({ _id: employeeId, companyId: ctx.companyId }, { $set: { 'tracking.consentAt': null, 'tracking.consentVersion': null } });
    await endOpenSession(ctx.companyId, employeeId, 'consent_withdrawn');
    await audit(ctx, { action: 'tracking.withdraw', entity: 'employee', entityId: employeeId });
    await notifyOwners(ctx.companyId, {
      template: 'tracking_alert',
      title: `${emp.name} stopped sharing location`,
      titleHi: `${emp.name} ने लोकेशन शेयर करना बंद किया`,
      body: 'They withdrew their agreement in the app. You can talk to them about it.',
      bodyHi: 'उन्होंने ऐप में अपनी सहमति वापस ली। आप उनसे बात कर सकते हैं।',
      data: { type: 'tracking', employeeId: String(employeeId) },
    });
  }
  return mine(ctx);
}

export interface PingInput {
  at: string;
  lat: number;
  lng: number;
  accuracyM?: number | null;
  speed?: number | null;
  battery?: number | null;
  mock?: boolean;
}

/**
 * Staff phone sends a batch of points (also ones saved while offline). Starts today's session on the first
 * point after check-in. `stop: true` tells the phone to stop sharing (checked out, shift over, turned off).
 */
export async function addPings(ctx: Ctx, input: PingInput[], now = new Date()) {
  const employeeId = staffOnly(ctx);
  const [emp, company] = await Promise.all([Employee.findOne({ _id: employeeId, companyId: ctx.companyId }).lean(), Company.findById(ctx.companyId).select('timezone').lean()]);
  if (!emp || !company) throw notFound('Employee');
  const stop = (reason: string) => ({ accepted: 0, stop: true, reason });
  if (!emp.tracking?.enabled) return stop('turned_off');
  if (!emp.tracking.consentAt) return stop('no_consent');
  const today = todayIn(company.timezone, now);
  let s = await openSession(ctx.companyId, employeeId);
  // Yesterday's session that nobody closed: close it, today starts fresh.
  if (s && s.date !== today) {
    await endOpenSession(ctx.companyId, employeeId, 'midnight', s.endsBy);
    s = null;
  }
  const inAt = await checkedInAt(ctx.companyId, employeeId, today);
  if (!inAt) {
    if (s) await endOpenSession(ctx.companyId, employeeId, 'punch_out', now);
    return stop('checked_out');
  }
  if (!s) {
    const by = await endsByFor(company, emp, today);
    if (now >= by.at) return stop(by.reason);
    s = await TrackingSession.create({ companyId: ctx.companyId, employeeId, date: today, startedAt: now, endsBy: by.at, consentVersion: emp.tracking.consentVersion });
  }
  if (now >= s.endsBy) {
    const reason = s.endsBy.getTime() === zonedInstant(today, '23:59', company.timezone).getTime() ? 'midnight' : 'shift_end';
    await endOpenSession(ctx.companyId, employeeId, reason, s.endsBy);
    return stop(reason);
  }
  const cfg = await settings(ctx.companyId);
  // Nothing from before they checked in (a few minutes' leeway for the phone clock).
  const dayStart = new Date(Math.max(zonedInstant(today, '00:00', company.timezone).getTime(), inAt.getTime() - 5 * 60_000));
  const pts = input
    .slice(0, MAX_BATCH)
    .map((p) => ({ ...p, atDate: new Date(p.at) }))
    // Only points from today, not from the future, and not after sharing had to stop.
    .filter((p) => !Number.isNaN(p.atDate.getTime()) && p.atDate >= dayStart && p.atDate <= new Date(now.getTime() + 120_000) && p.atDate <= s!.endsBy)
    .filter((p) => Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180);
  if (pts.length) {
    const expireAt = new Date(now.getTime() + cfg.keepDays * 86_400_000);
    await LocationPing.insertMany(
      pts.map((p) => ({
        companyId: ctx.companyId,
        employeeId,
        sessionId: s!._id,
        at: p.atDate,
        lat: p.lat,
        lng: p.lng,
        accuracyM: p.accuracyM ?? null,
        speed: p.speed ?? null,
        battery: p.battery ?? null,
        mock: !!p.mock,
        expireAt,
      })),
    );
    const latest = pts.reduce((a, b) => (b.atDate > a.atDate ? b : a));
    const all = await LocationPing.find({ companyId: ctx.companyId, sessionId: s._id }).select('at lat lng accuracyM').lean();
    const update: Record<string, unknown> = { points: all.length, distanceM: distanceOf(all) };
    if (!s.lastPingAt || latest.atDate > s.lastPingAt) {
      update.lastPingAt = latest.atDate;
      update.last = { lat: latest.lat, lng: latest.lng, accuracyM: latest.accuracyM ?? null, battery: latest.battery ?? null };
    }
    await TrackingSession.updateOne({ _id: s._id, companyId: ctx.companyId }, { $set: update });
    if (pts.some((p) => p.mock)) await addEvents(ctx, [{ at: latest.at, type: 'mock_location' }], now);
  }
  return { accepted: pts.length, stop: false, reason: null, intervalSec: cfg.intervalSec, minDistanceM: cfg.distanceM, endsBy: s.endsBy };
}

const EVENT_ALERTS: Record<string, { title: [string, string]; body: [string, string] }> = {
  location_off: { title: ['{name} turned off location', '{name} ने लोकेशन बंद की'], body: ['Ask them to turn it back on while they are checked in.', 'चेक-इन रहते हुए उनसे लोकेशन चालू करने को कहें।'] },
  permission_removed: {
    title: ['{name} took away the location permission', '{name} ने लोकेशन की अनुमति हटाई'],
    body: ['StaffMint can’t see their location until they allow it again.', 'दोबारा अनुमति देने तक StaffMint उनकी लोकेशन नहीं देख सकता।'],
  },
  mock_location: { title: ['Fake location app on {name}’s phone', '{name} के फ़ोन पर नकली लोकेशन ऐप'], body: ['Their points may not be real. Talk to them.', 'उनकी लोकेशन सही न हो सकती है। उनसे बात करें।'] },
};

/** Phone events (location turned off, permission removed, fake location, low battery). Owners hear once per day. */
export async function addEvents(ctx: Ctx, events: { at: string; type: string }[], now = new Date()) {
  const employeeId = staffOnly(ctx);
  const s = await openSession(ctx.companyId, employeeId);
  if (!s) return { ok: true, recorded: 0 };
  const list = events.slice(0, 20).map((e) => ({ at: new Date(e.at), type: e.type })).filter((e) => !Number.isNaN(e.at.getTime()));
  s.events.push(...(list as any));
  const company = (await Company.findById(ctx.companyId).select('timezone').lean())!;
  const emp = (await Employee.findOne({ _id: employeeId, companyId: ctx.companyId }).select('name').lean())!;
  for (const e of list) {
    const a = EVENT_ALERTS[e.type];
    if (!a || s.alerted.includes(e.type) || !daytime(company.timezone, now)) continue;
    s.alerted.push(e.type);
    await notifyOwners(ctx.companyId, {
      template: 'tracking_alert',
      title: a.title[0].replace('{name}', emp.name),
      titleHi: a.title[1].replace('{name}', emp.name),
      body: a.body[0],
      bodyHi: a.body[1],
      data: { type: 'tracking', employeeId: String(employeeId) },
    });
  }
  await s.save();
  return { ok: true, recorded: list.length };
}

// ---------------------------------------------------------------- jobs

/** Every few minutes: close sessions past their end, and tell owners when someone's location stopped updating. */
export async function trackingTick(company: { _id: Types.ObjectId; timezone: string }, now = new Date()) {
  const open = await TrackingSession.find({ companyId: company._id, endedAt: null }).limit(500);
  if (!open.length) return { ended: 0, alerts: 0 };
  const { staleMinutes } = await settings(company._id);
  let ended = 0;
  let alerts = 0;
  for (const s of open) {
    if (now >= s.endsBy) {
      const midnight = zonedInstant(s.date, '23:59', company.timezone).getTime();
      s.endedAt = s.endsBy;
      s.endReason = s.endsBy.getTime() === midnight ? 'midnight' : 'shift_end';
      await s.save();
      ended++;
      continue;
    }
    const last = s.lastPingAt ?? s.startedAt;
    if (now.getTime() - last.getTime() < staleMinutes * 60_000 || s.alerted.includes('stale') || !daytime(company.timezone, now)) continue;
    const emp = await Employee.findOne({ _id: s.employeeId, companyId: company._id }).select('name').lean();
    if (!emp) continue;
    s.alerted.push('stale');
    await s.save();
    await notifyOwners(company._id, {
      template: 'tracking_alert',
      title: `${emp.name}'s location hasn't updated for ${staleMinutes} minutes`,
      titleHi: `${emp.name} की लोकेशन ${staleMinutes} मिनट से नहीं बदली`,
      body: 'Their phone may be off, without signal, or location may be turned off.',
      bodyHi: 'हो सकता है फ़ोन बंद हो, नेटवर्क न हो, या लोकेशन बंद हो।',
      data: { type: 'tracking', employeeId: String(s.employeeId) },
    });
    alerts++;
  }
  return { ended, alerts };
}
