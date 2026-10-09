/**
 * Deterministic attendance rules engine (PRD F4). Pure functions only.
 */
import { DateTime } from 'luxon';
import type { AttendanceStatus } from '../../models/attendance.js';

export interface RulesPunch {
  type: 'in' | 'out';
  serverTime: Date;
  clientTime: Date;
  approval: 'not_required' | 'pending' | 'approved' | 'rejected';
}

export interface RulesShift {
  start: string; // HH:mm
  end: string;
  graceMinutes: number;
}

export interface DayComputation {
  status: AttendanceStatus | null;
  lateMinutes: number;
  earlyOutMinutes: number;
  workedMinutes: number;
  flags: string[];
  /** true when checked in and the day is still open (no check-out yet). */
  checkedIn: boolean;
}

/** Effective time of a punch: client time (it may have been captured offline), already sanity-checked at ingest. */
const t = (p: RulesPunch) => p.clientTime.getTime();

export function computeDay(args: {
  date: string;
  tz: string;
  punches: RulesPunch[];
  shift: RulesShift;
  halfDayHours: number;
  missingCheckoutPolicy: 'half_day' | 'present' | 'flag';
  /** Day is closed (nightly job or a past date). */
  closed: boolean;
}): DayComputation {
  const valid = args.punches.filter((p) => p.approval === 'not_required' || p.approval === 'approved').sort((a, b) => t(a) - t(b));
  const flags: string[] = [];
  const firstIn = valid.find((p) => p.type === 'in');
  if (!firstIn) return { status: null, lateMinutes: 0, earlyOutMinutes: 0, workedMinutes: 0, flags, checkedIn: false };

  const day = DateTime.fromISO(args.date, { zone: args.tz });
  const [sh, sm] = args.shift.start.split(':').map(Number);
  const [eh, em] = args.shift.end.split(':').map(Number);
  const shiftStart = day.set({ hour: sh, minute: sm });
  let shiftEnd = day.set({ hour: eh, minute: em });
  if (shiftEnd <= shiftStart) shiftEnd = shiftEnd.plus({ days: 1 }); // overnight shift

  const inAt = DateTime.fromMillis(t(firstIn));
  const minutesAfterStart = Math.floor(inAt.diff(shiftStart, 'minutes').minutes);
  const lateMinutes = minutesAfterStart > args.shift.graceMinutes ? minutesAfterStart : 0;
  if (lateMinutes) flags.push('late');

  // Pair in/out punches to compute worked time.
  let worked = 0;
  let openIn: RulesPunch | null = null;
  let lastOut: RulesPunch | null = null;
  for (const p of valid) {
    if (p.type === 'in') {
      if (!openIn) openIn = p;
    } else if (openIn) {
      worked += (t(p) - t(openIn)) / 60000;
      openIn = null;
      lastOut = p;
    }
  }
  const workedMinutes = Math.max(0, Math.round(worked));
  let earlyOutMinutes = 0;
  if (lastOut && !openIn) {
    const outAt = DateTime.fromMillis(t(lastOut));
    const early = Math.floor(shiftEnd.diff(outAt, 'minutes').minutes);
    if (early > 0) {
      earlyOutMinutes = early;
      flags.push('early_out');
    }
  }

  const checkedOut = !openIn && !!lastOut;
  if (!checkedOut) {
    if (!args.closed) return { status: 'present', lateMinutes, earlyOutMinutes: 0, workedMinutes, flags, checkedIn: true };
    flags.push('missing_checkout');
    const status: AttendanceStatus = args.missingCheckoutPolicy === 'half_day' ? 'half_day' : 'present';
    if (args.missingCheckoutPolicy === 'flag') flags.push('needs_review');
    return { status, lateMinutes, earlyOutMinutes: 0, workedMinutes, flags, checkedIn: false };
  }

  const status: AttendanceStatus = workedMinutes < args.halfDayHours * 60 ? 'half_day' : 'present';
  return { status, lateMinutes, earlyOutMinutes, workedMinutes, flags, checkedIn: false };
}

/** Plain-language rules shown in Settings (PRD F4). */
export function describeRules(
  s: { graceMinutes: number; halfDayHours: number; missingCheckoutPolicy: string; weekOffsPaid: boolean; holidaysPaid: boolean; monthDivisor: string; outsideGeofencePolicy: string; phoneLockPolicy?: string },
  lang: 'en' | 'hi',
  shift?: { start: string; end: string },
): { key: string; text: string }[] {
  const divisorText = {
    en: s.monthDivisor === 'days_in_month' ? 'number of days in that month' : `${s.monthDivisor} days`,
    hi: s.monthDivisor === 'days_in_month' ? 'उस महीने के कुल दिन' : `${s.monthDivisor} दिन`,
  };
  const missing = {
    en: { half_day: 'Half Day', present: 'Present (full day)', flag: 'Present, flagged for your review' }[s.missingCheckoutPolicy],
    hi: { half_day: 'Half Day', present: 'पूरा दिन Present', flag: 'Present, पर आपके रिव्यू के लिए फ़्लैग' }[s.missingCheckoutPolicy],
  };
  const rules = {
    en: [
      ['late', `Late if check-in is more than ${s.graceMinutes} minutes after shift start${shift ? ` (${shift.start})` : ''}.`],
      ['half_day', `Half Day if worked less than ${s.halfDayHours} hours.`],
      ['missing_checkout', `If someone forgets to punch out, the day counts as ${missing.en}.`],
      ['auto_absent', 'At 11:59 PM, anyone with no punch is marked Absent (unless on leave, holiday or week off).'],
      ['week_off', s.weekOffsPaid ? 'Week offs are paid for monthly staff.' : 'Week offs are not paid.'],
      ['holiday', s.holidaysPaid ? 'Holidays are paid for monthly staff.' : 'Holidays are not paid.'],
      ['salary', `Monthly salary = salary ÷ ${divisorText.en} × payable days.`],
      ['geofence', s.outsideGeofencePolicy === 'block' ? 'Check-in outside the shop radius is blocked.' : 'Check-in outside the shop radius needs your approval.'],
      ['phone_lock', { off: 'Staff are not asked to unlock their phone at check-in.', recommended: 'Staff unlock their phone (fingerprint, face, PIN or pattern) at check-in. If they can\'t, the check-in still counts and is tagged for you.', required: 'Staff unlock their phone at check-in. If they can\'t, the check-in waits for your approval.' }[s.phoneLockPolicy ?? 'recommended']!],
    ],
    hi: [
      ['late', `शिफ्ट शुरू${shift ? ` (${shift.start})` : ''} होने के ${s.graceMinutes} मिनट बाद पंच-इन किया तो Late लगेगा।`],
      ['half_day', `${s.halfDayHours} घंटे से कम काम किया तो Half Day लगेगा।`],
      ['missing_checkout', `अगर punch-out नहीं किया तो ${missing.hi} लगेगा।`],
      ['auto_absent', 'रात 11:59 तक कोई पंच नहीं हुआ तो Absent लगेगा (छुट्टी, त्योहार या साप्ताहिक छुट्टी को छोड़कर)।'],
      ['week_off', s.weekOffsPaid ? 'मासिक स्टाफ़ को साप्ताहिक छुट्टी का पैसा मिलेगा।' : 'साप्ताहिक छुट्टी का पैसा नहीं मिलेगा।'],
      ['holiday', s.holidaysPaid ? 'मासिक स्टाफ़ को त्योहार की छुट्टी का पैसा मिलेगा।' : 'त्योहार की छुट्टी का पैसा नहीं मिलेगा।'],
      ['salary', `मासिक वेतन = वेतन ÷ ${divisorText.hi} × देय दिन।`],
      ['geofence', s.outsideGeofencePolicy === 'block' ? 'दुकान की दूरी से बाहर पंच-इन नहीं होगा।' : 'दुकान की दूरी से बाहर पंच-इन के लिए आपकी मंज़ूरी चाहिए।'],
      ['phone_lock', { off: 'पंच-इन पर फ़ोन लॉक नहीं पूछा जाएगा।', recommended: 'पंच-इन पर स्टाफ़ अपना फ़ोन लॉक (फ़िंगरप्रिंट, चेहरा, PIN या पैटर्न) खोलेगा। न खुले तो भी हाज़िरी लगेगी, आपको टैग दिखेगा।', required: 'पंच-इन पर स्टाफ़ अपना फ़ोन लॉक खोलेगा। न खुले तो हाज़िरी आपकी मंज़ूरी के बाद लगेगी।' }[s.phoneLockPolicy ?? 'recommended']!],
    ],
  };
  return rules[lang].map(([key, text]) => ({ key, text }));
}
