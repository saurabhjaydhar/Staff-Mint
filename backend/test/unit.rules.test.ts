import { describe, expect, it } from 'vitest';
import { DateTime } from 'luxon';
import { computeDay, describeRules } from '../src/modules/attendance/rules.js';

const tz = 'Asia/Kolkata';
const at = (date: string, hm: string) => DateTime.fromISO(`${date}T${hm}`, { zone: tz }).toJSDate();
const p = (type: 'in' | 'out', date: string, hm: string, approval: any = 'not_required') => ({ type, clientTime: at(date, hm), serverTime: at(date, hm), approval });
const base = { date: '2026-10-08', tz, shift: { start: '09:00', end: '18:00', graceMinutes: 15 }, halfDayHours: 4, missingCheckoutPolicy: 'half_day' as const, closed: true };

describe('attendance rules engine', () => {
  it('on time within grace is not late; full day present', () => {
    const r = computeDay({ ...base, punches: [p('in', base.date, '09:14'), p('out', base.date, '18:05')] });
    expect(r).toMatchObject({ status: 'present', lateMinutes: 0, earlyOutMinutes: 0 });
    expect(r.workedMinutes).toBe(531);
  });
  it('late after grace counts minutes from shift start', () => {
    const r = computeDay({ ...base, punches: [p('in', base.date, '09:40'), p('out', base.date, '18:00')] });
    expect(r.lateMinutes).toBe(40);
    expect(r.flags).toContain('late');
  });
  it('worked less than half-day hours → Half Day, early out flagged', () => {
    const r = computeDay({ ...base, punches: [p('in', base.date, '09:00'), p('out', base.date, '12:30')] });
    expect(r.status).toBe('half_day');
    expect(r.earlyOutMinutes).toBe(330);
    expect(r.flags).toContain('early_out');
  });
  it('missing checkout follows the owner policy', () => {
    const punches = [p('in', base.date, '09:00')];
    expect(computeDay({ ...base, punches }).status).toBe('half_day');
    expect(computeDay({ ...base, punches, missingCheckoutPolicy: 'present' }).status).toBe('present');
    const flagged = computeDay({ ...base, punches, missingCheckoutPolicy: 'flag' });
    expect(flagged.status).toBe('present');
    expect(flagged.flags).toEqual(expect.arrayContaining(['missing_checkout', 'needs_review']));
  });
  it('open day with only check-in is provisional present (checked in)', () => {
    const r = computeDay({ ...base, closed: false, punches: [p('in', base.date, '09:05')] });
    expect(r).toMatchObject({ status: 'present', checkedIn: true });
  });
  it('multiple in/out pairs sum worked time', () => {
    const r = computeDay({ ...base, punches: [p('in', base.date, '09:00'), p('out', base.date, '11:00'), p('in', base.date, '12:00'), p('out', base.date, '14:30')] });
    expect(r.workedMinutes).toBe(270);
    expect(r.status).toBe('present');
  });
  it('pending / rejected punches are ignored', () => {
    const r = computeDay({ ...base, punches: [p('in', base.date, '09:00', 'pending'), p('out', base.date, '18:00', 'rejected')] });
    expect(r.status).toBeNull();
  });
  it('overnight shift computes against next-day end', () => {
    const r = computeDay({ ...base, shift: { start: '22:00', end: '06:00', graceMinutes: 10 }, punches: [p('in', base.date, '22:05'), p('out', '2026-10-09', '06:00')] });
    expect(r).toMatchObject({ status: 'present', lateMinutes: 0, earlyOutMinutes: 0, workedMinutes: 475 });
  });
  it('describes rules in plain Hindi and English', () => {
    const s = { graceMinutes: 15, halfDayHours: 4, missingCheckoutPolicy: 'half_day', weekOffsPaid: true, holidaysPaid: true, monthDivisor: 'days_in_month', outsideGeofencePolicy: 'block' };
    expect(describeRules(s, 'hi').find((r) => r.key === 'missing_checkout')!.text).toContain('चेक-आउट नहीं किया तो आधा दिन लगेगा');
    expect(describeRules(s, 'en').map((r) => r.key)).toContain('auto_absent');
  });
});
