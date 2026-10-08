// Date/time helpers. Dates are company-local calendar days (YYYY-MM-DD).

function pad(n: number) {
  return String(n).padStart(2, "0");
}

export function toDateStr(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function toMonthStr(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
}

export function todayStr(): string {
  return toDateStr(new Date());
}

export function currentMonth(): string {
  return toMonthStr(new Date());
}

/** Previous calendar month (YYYY-MM). */
export function previousMonth(from: Date = new Date()): string {
  return toMonthStr(new Date(from.getFullYear(), from.getMonth() - 1, 1));
}

/** Payroll usually runs for last month in the first days of a month. */
export function defaultPayrollMonth(now: Date = new Date()): string {
  return now.getDate() <= 15 ? previousMonth(now) : toMonthStr(now);
}

const MONTHS_EN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export function formatDate(d: string | null | undefined): string {
  if (!d) return "—";
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(d);
  if (!m) return d;
  return `${Number(m[3])} ${MONTHS_EN[Number(m[2]) - 1]} ${m[1]}`;
}

export function formatMonth(month: string): string {
  const m = /^(\d{4})-(\d{2})$/.exec(month);
  if (!m) return month;
  return `${MONTHS_EN[Number(m[2]) - 1]} ${m[1]}`;
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return `${d.getDate()} ${MONTHS_EN[d.getMonth()]} ${d.getFullYear()}, ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function formatTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function formatMinutes(min: number | null | undefined): string {
  if (!min) return "0m";
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h ? `${h}h ${m}m` : `${m}m`;
}

export const WEEKDAYS_EN = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
export const WEEKDAYS_HI = ["रवि", "सोम", "मंगल", "बुध", "गुरु", "शुक्र", "शनि"];

/** Day-of-month number from YYYY-MM-DD. */
export function dayOfMonth(date: string): number {
  return Number(date.slice(8, 10));
}

/** Weekday (0=Sun) of a YYYY-MM-DD date. */
export function weekdayOf(date: string): number {
  const [y, m, d] = date.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}
