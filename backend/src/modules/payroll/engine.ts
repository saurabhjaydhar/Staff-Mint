/**
 * Pure, deterministic payroll engine (PRD F8). No I/O, no clock, no randomness.
 * "AI suggests, code calculates, owner confirms." Every number carries a plain-language reason.
 * Bump ENGINE_VERSION whenever output for the same input could change.
 */
import { formatMoney, roundToRupee } from '../../lib/money.js';

export const ENGINE_VERSION = '1.0.0';

export type DayStatus = 'present' | 'absent' | 'half_day' | 'leave' | 'holiday' | 'week_off' | null;
export type LeaveType = 'paid' | 'sick' | 'unpaid';

export interface PayrollSettings {
  monthDivisor: 'days_in_month' | '30' | '26';
  weekOffsPaid: boolean;
  holidaysPaid: boolean;
  sickLeavePaid: boolean;
  dailyPaysOffDays: boolean;
  roundToRupee: boolean;
}

export interface EngineAdvance {
  id: string;
  date: string;
  amountPaise: number;
  mode: 'installments' | 'full_next';
  installments: number;
  /** Outstanding before this month's deduction. */
  outstandingPaise: number;
  skip: boolean;
}

export interface EngineAdjustment {
  id: string;
  type: 'bonus' | 'deduction';
  amountPaise: number;
  note?: string;
}

export interface EmployeePayrollInput {
  employeeId: string;
  name: string;
  wageType: 'monthly' | 'daily';
  ratePaise: number;
  joiningDate?: string | null;
  exitDate?: string | null;
  /** Every calendar day of the month, in order. */
  days: { date: string; status: DayStatus; leaveType?: LeaveType | null }[];
  adjustments: EngineAdjustment[];
  advances: EngineAdvance[];
  lastNetPaise?: number | null;
}

export interface EngineInput {
  month: string;
  currency: string;
  settings: PayrollSettings;
  /** For running estimates: days after this date are ignored. Omit for a full month. */
  asOfDate?: string | null;
  employee: EmployeePayrollInput;
}

export interface Bilingual {
  en: string;
  hi: string;
}

export interface EngineLine {
  code: 'basic' | 'bonus' | 'deduction' | 'advance';
  kind: 'earning' | 'deduction';
  amountPaise: number;
  label: Bilingual;
  explanation: Bilingual;
  refId?: string | null;
}

export interface DaySummary {
  present: number;
  halfDay: number;
  absent: number;
  paidLeave: number;
  unpaidLeave: number;
  holidays: number;
  weekOffs: number;
  unmarked: number;
}

export interface EngineAnomaly {
  code: 'negative_net' | 'big_change' | 'zero_rate' | 'unmarked_days' | 'no_payable_days' | 'advance_capped';
  message: Bilingual;
}

export interface EngineResult {
  engineVersion: string;
  employeeId: string;
  wageType: 'monthly' | 'daily';
  ratePaise: number;
  daysInMonth: number;
  divisor: number;
  payableDays: number;
  summary: DaySummary;
  lines: EngineLine[];
  grossPaise: number;
  deductionsPaise: number;
  netPaise: number;
  anomalies: EngineAnomaly[];
  advanceDeductions: { advanceId: string; amountPaise: number }[];
}

const fmtDays = (n: number) => (Number.isInteger(n) ? String(n) : n.toFixed(1));

export function computePayslip(input: EngineInput): EngineResult {
  const { settings, employee: e, currency } = input;
  const money = (p: number) => formatMoney(p, currency);
  const daysInMonth = input.employee.days.length;
  const summary: DaySummary = { present: 0, halfDay: 0, absent: 0, paidLeave: 0, unpaidLeave: 0, holidays: 0, weekOffs: 0, unmarked: 0 };
  const isDaily = e.wageType === 'daily';
  const offDaysPaid = (paidSetting: boolean) => (isDaily ? settings.dailyPaysOffDays && paidSetting : paidSetting);

  let payable = 0;
  for (const d of e.days) {
    if (e.joiningDate && d.date < e.joiningDate) continue;
    if (e.exitDate && d.date > e.exitDate) continue;
    if (input.asOfDate && d.date > input.asOfDate) continue;
    switch (d.status) {
      case 'present':
        summary.present++;
        payable += 1;
        break;
      case 'half_day':
        summary.halfDay++;
        payable += 0.5;
        break;
      case 'absent':
        summary.absent++;
        break;
      case 'leave': {
        const paid = d.leaveType === 'paid' || (d.leaveType === 'sick' && settings.sickLeavePaid);
        if (paid) {
          summary.paidLeave++;
          payable += 1;
        } else summary.unpaidLeave++;
        break;
      }
      case 'holiday':
        summary.holidays++;
        if (offDaysPaid(settings.holidaysPaid)) payable += 1;
        break;
      case 'week_off':
        summary.weekOffs++;
        if (offDaysPaid(settings.weekOffsPaid)) payable += 1;
        break;
      default:
        summary.unmarked++;
    }
  }

  const divisor = settings.monthDivisor === 'days_in_month' ? daysInMonth : Number(settings.monthDivisor);
  const round = (p: number) => (settings.roundToRupee ? roundToRupee(p) : Math.round(p));

  // ---- Basic earning ----
  let basic: number;
  let basicExplain: Bilingual;
  const parts = describeDays(summary, settings, isDaily);
  if (isDaily) {
    basic = round(e.ratePaise * payable);
    basicExplain = {
      en: `${parts.en} → ${fmtDays(payable)} payable days. ${money(e.ratePaise)}/day × ${fmtDays(payable)} = ${money(basic)}`,
      hi: `${parts.hi} → ${fmtDays(payable)} देय दिन। ${money(e.ratePaise)}/दिन × ${fmtDays(payable)} = ${money(basic)}`,
    };
  } else {
    const raw = (e.ratePaise * payable) / divisor;
    const capped = Math.min(raw, e.ratePaise);
    basic = round(capped);
    const capNote = raw > e.ratePaise ? { en: ' (capped at full monthly salary)', hi: ' (पूरे मासिक वेतन तक सीमित)' } : { en: '', hi: '' };
    basicExplain = {
      en: `${parts.en} → ${fmtDays(payable)} payable days of ${divisor}. ${money(e.ratePaise)} ÷ ${divisor} × ${fmtDays(payable)} = ${money(basic)}${capNote.en}`,
      hi: `${parts.hi} → ${divisor} में से ${fmtDays(payable)} देय दिन। ${money(e.ratePaise)} ÷ ${divisor} × ${fmtDays(payable)} = ${money(basic)}${capNote.hi}`,
    };
  }

  const lines: EngineLine[] = [
    {
      code: 'basic',
      kind: 'earning',
      amountPaise: basic,
      label: { en: `Salary for ${fmtDays(payable)} days`, hi: `${fmtDays(payable)} दिन का वेतन` },
      explanation: basicExplain,
    },
  ];

  for (const a of e.adjustments.filter((x) => x.type === 'bonus')) {
    lines.push({
      code: 'bonus',
      kind: 'earning',
      amountPaise: a.amountPaise,
      label: { en: 'Bonus / incentive', hi: 'बोनस / इंसेंटिव' },
      explanation: { en: a.note ? `Bonus: ${a.note}` : 'Bonus added by owner', hi: a.note ? `बोनस: ${a.note}` : 'मालिक द्वारा जोड़ा गया बोनस' },
      refId: a.id,
    });
  }
  for (const a of e.adjustments.filter((x) => x.type === 'deduction')) {
    lines.push({
      code: 'deduction',
      kind: 'deduction',
      amountPaise: a.amountPaise,
      label: { en: 'Deduction', hi: 'कटौती' },
      explanation: { en: a.note ? `Deduction: ${a.note}` : 'Deduction added by owner', hi: a.note ? `कटौती: ${a.note}` : 'मालिक द्वारा की गई कटौती' },
      refId: a.id,
    });
  }

  const gross = lines.filter((l) => l.kind === 'earning').reduce((s, l) => s + l.amountPaise, 0);
  let deductions = lines.filter((l) => l.kind === 'deduction').reduce((s, l) => s + l.amountPaise, 0);
  const anomalies: EngineAnomaly[] = [];

  // ---- Advances (udhaar): oldest first, never push net below zero ----
  const advanceDeductions: { advanceId: string; amountPaise: number }[] = [];
  let available = Math.max(0, gross - deductions);
  let capped = false;
  for (const adv of [...e.advances].sort((a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id))) {
    if (adv.outstandingPaise <= 0 || adv.skip) continue;
    const scheduled =
      adv.mode === 'full_next' ? adv.outstandingPaise : Math.min(adv.outstandingPaise, Math.ceil(adv.amountPaise / Math.max(1, adv.installments)));
    const amount = Math.min(scheduled, available);
    if (amount < scheduled) capped = true;
    if (amount <= 0) continue;
    available -= amount;
    deductions += amount;
    advanceDeductions.push({ advanceId: adv.id, amountPaise: amount });
    const remaining = adv.outstandingPaise - amount;
    lines.push({
      code: 'advance',
      kind: 'deduction',
      amountPaise: amount,
      label: { en: `Advance recovery (${adv.date})`, hi: `एडवांस वापसी (${adv.date})` },
      explanation: {
        en: `Advance of ${money(adv.amountPaise)} given on ${adv.date}. Deducted ${money(amount)} this month; ${money(remaining)} remaining.`,
        hi: `${adv.date} को ${money(adv.amountPaise)} एडवांस दिया गया। इस महीने ${money(amount)} कटे; ${money(remaining)} बाकी।`,
      },
      refId: adv.id,
    });
  }

  const net = gross - deductions;

  if (capped) anomalies.push({ code: 'advance_capped', message: { en: 'Advance deduction reduced so salary does not go negative', hi: 'वेतन माइनस न हो, इसलिए एडवांस कटौती कम की गई' } });
  if (e.ratePaise <= 0) anomalies.push({ code: 'zero_rate', message: { en: 'Salary amount is not set', hi: 'वेतन राशि सेट नहीं है' } });
  if (summary.unmarked > 0)
    anomalies.push({ code: 'unmarked_days', message: { en: `${summary.unmarked} day(s) have no attendance`, hi: `${summary.unmarked} दिन की हाज़िरी नहीं लगी` } });
  if (payable === 0 && !input.asOfDate) anomalies.push({ code: 'no_payable_days', message: { en: 'No payable days this month', hi: 'इस महीने कोई देय दिन नहीं' } });
  if (net < 0) anomalies.push({ code: 'negative_net', message: { en: `Net salary is negative (${money(net)})`, hi: `कुल वेतन माइनस में है (${money(net)})` } });
  if (e.lastNetPaise && e.lastNetPaise > 0 && !input.asOfDate) {
    const diff = net - e.lastNetPaise;
    if (Math.abs(diff) >= 100000 && Math.abs(diff) / e.lastNetPaise >= 0.25) {
      anomalies.push({
        code: 'big_change',
        message: {
          en: `Net changed by ${money(diff)} vs last month (${money(e.lastNetPaise)})`,
          hi: `पिछले महीने (${money(e.lastNetPaise)}) से ${money(diff)} का फ़र्क`,
        },
      });
    }
  }

  return {
    engineVersion: ENGINE_VERSION,
    employeeId: e.employeeId,
    wageType: e.wageType,
    ratePaise: e.ratePaise,
    daysInMonth,
    divisor: isDaily ? 1 : divisor,
    payableDays: payable,
    summary,
    lines,
    grossPaise: gross,
    deductionsPaise: deductions,
    netPaise: net,
    anomalies,
    advanceDeductions,
  };
}

function describeDays(s: DaySummary, settings: PayrollSettings, isDaily: boolean): Bilingual {
  const paid: Bilingual[] = [];
  const unpaid: Bilingual[] = [];
  const offPaid = (p: boolean) => (isDaily ? settings.dailyPaysOffDays && p : p);
  const add = (list: Bilingual[], n: number, en: string, hi: string) => {
    if (n) list.push({ en, hi });
  };
  add(paid, s.present, `Present ${s.present}`, `हाज़िर ${s.present}`);
  add(paid, s.halfDay, `Half day ${s.halfDay} (= ${fmtDays(s.halfDay / 2)})`, `आधा दिन ${s.halfDay} (= ${fmtDays(s.halfDay / 2)})`);
  add(paid, s.paidLeave, `Paid leave ${s.paidLeave}`, `सवेतन छुट्टी ${s.paidLeave}`);
  add(offPaid(settings.weekOffsPaid) ? paid : unpaid, s.weekOffs, `${offPaid(settings.weekOffsPaid) ? 'Week offs' : 'week offs'} ${s.weekOffs}`, `साप्ताहिक छुट्टी ${s.weekOffs}`);
  add(offPaid(settings.holidaysPaid) ? paid : unpaid, s.holidays, `${offPaid(settings.holidaysPaid) ? 'Holidays' : 'holidays'} ${s.holidays}`, `त्योहार छुट्टी ${s.holidays}`);
  add(unpaid, s.absent, `absent ${s.absent}`, `गैरहाज़िर ${s.absent}`);
  add(unpaid, s.unpaidLeave, `unpaid leave ${s.unpaidLeave}`, `बिना वेतन छुट्टी ${s.unpaidLeave}`);
  add(unpaid, s.unmarked, `not marked ${s.unmarked}`, `हाज़िरी नहीं ${s.unmarked}`);
  const join = (l: Bilingual[], k: 'en' | 'hi') => l.map((x) => x[k]).join(', ');
  return {
    en: (join(paid, 'en') || 'No paid days') + (unpaid.length ? `; not paid: ${join(unpaid, 'en')}` : ''),
    hi: (join(paid, 'hi') || 'कोई देय दिन नहीं') + (unpaid.length ? `; वेतन नहीं: ${join(unpaid, 'hi')}` : ''),
  };
}
