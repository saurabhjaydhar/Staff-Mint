import { DateTime } from 'luxon';

export const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
export const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/;
export const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

/** Today's calendar date in a timezone, as YYYY-MM-DD. */
export const todayIn = (tz: string, now: Date = new Date()): string => DateTime.fromJSDate(now).setZone(tz).toISODate()!;

export const localDateOf = (instant: Date, tz: string): string => DateTime.fromJSDate(instant).setZone(tz).toISODate()!;

export const localDateTime = (instant: Date, tz: string) => DateTime.fromJSDate(instant).setZone(tz);

/** Combine a local date + HH:mm in a timezone into a UTC instant. */
export function zonedInstant(date: string, time: string, tz: string): Date {
  const [h, m] = time.split(':').map(Number);
  return DateTime.fromISO(date, { zone: tz }).set({ hour: h, minute: m, second: 0, millisecond: 0 }).toJSDate();
}

export function daysInMonth(month: string): number {
  return DateTime.fromISO(`${month}-01`).daysInMonth!;
}

export function monthDays(month: string): string[] {
  const n = daysInMonth(month);
  return Array.from({ length: n }, (_, i) => `${month}-${String(i + 1).padStart(2, '0')}`);
}

export function dateRange(from: string, to: string): string[] {
  const out: string[] = [];
  let d = DateTime.fromISO(from);
  const end = DateTime.fromISO(to);
  while (d <= end) {
    out.push(d.toISODate()!);
    d = d.plus({ days: 1 });
  }
  return out;
}

/** 0 = Sunday ... 6 = Saturday */
export const weekdayOf = (date: string): number => DateTime.fromISO(date).weekday % 7;

export const monthOf = (date: string): string => date.slice(0, 7);

export const previousMonth = (month: string): string => DateTime.fromISO(`${month}-01`).minus({ months: 1 }).toFormat('yyyy-MM');

export const nextMonth = (month: string): string => DateTime.fromISO(`${month}-01`).plus({ months: 1 }).toFormat('yyyy-MM');

export const addDays = (date: string, n: number): string => DateTime.fromISO(date).plus({ days: n }).toISODate()!;

export const monthLabel = (month: string, lang: 'en' | 'hi' = 'en'): string =>
  DateTime.fromISO(`${month}-01`).setLocale(lang === 'hi' ? 'hi-IN' : 'en-IN').toFormat('LLLL yyyy');

export const minutesOfDay = (time: string): number => {
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
};
