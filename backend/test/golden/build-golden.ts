/**
 * Generates golden payroll inputs. Expected values are hand-computed (see comments) — the test
 * fails if the engine ever disagrees. Regenerate: `npx tsx test/golden/build-golden.ts`.
 */
import fs from 'node:fs';
import path from 'node:path';
import { DateTime } from 'luxon';

type Status = 'present' | 'absent' | 'half_day' | 'leave' | 'holiday' | 'week_off' | null;
const dir = path.dirname(new URL(import.meta.url).pathname) + '/payroll';

const base = { monthDivisor: 'days_in_month', weekOffsPaid: true, holidaysPaid: true, sickLeavePaid: true, dailyPaysOffDays: false, roundToRupee: true };

function days(month: string, fn: (d: string, dow: number, i: number) => { status: Status; leaveType?: string } | Status) {
  const n = DateTime.fromISO(`${month}-01`).daysInMonth!;
  return Array.from({ length: n }, (_, i) => {
    const d = `${month}-${String(i + 1).padStart(2, '0')}`;
    const dow = DateTime.fromISO(d).weekday % 7;
    const r = fn(d, dow, i + 1);
    return typeof r === 'object' && r !== null ? { date: d, status: r.status, leaveType: r.leaveType ?? null } : { date: d, status: r, leaveType: null };
  });
}

// October 2026: Sundays 4,11,18,25; holidays 2 (Gandhi Jayanti), 20 (Dussehra).
const oct = (d: string, dow: number, day: number): any => {
  if (dow === 0) return 'week_off';
  if (day === 2 || day === 20) return 'holiday';
  if (day === 6 || day === 13) return 'absent';
  if (day === 7 || day === 14) return 'half_day';
  if (day === 21) return { status: 'leave', leaveType: 'paid' };
  return 'present';
};
// February 2026: Sundays 1,8,15,22.
const febFull = (_d: string, dow: number): any => (dow === 0 ? 'week_off' : 'present');

const emp = (over: any) => ({ employeeId: 'e1', name: 'Ramesh', wageType: 'monthly', ratePaise: 1200000, joiningDate: null, exitDate: null, adjustments: [], advances: [], lastNetPaise: null, ...over });

const cases: Record<string, { input: any; expected: any }> = {
  // 20 P + 2 HD(=1) + 1 PL + 4 WO + 2 H = 28 of 31 → 12000 × 28/31 = 10838.71 → ₹10,839
  'monthly-days-in-month': {
    input: { month: '2026-10', currency: 'INR', settings: base, employee: emp({ days: days('2026-10', oct) }) },
    expected: { payableDays: 28, grossPaise: 1083900, deductionsPaise: 0, netPaise: 1083900, summary: { present: 20, halfDay: 2, absent: 2, paidLeave: 1, unpaidLeave: 0, holidays: 2, weekOffs: 4, unmarked: 0 }, anomalies: [], explainIncludes: ['÷ 31 × 28'] },
  },
  // Same month, exact paise: 1200000 × 28 / 31 = 1083870.97 → 1083871
  'monthly-no-rounding': {
    input: { month: '2026-10', currency: 'INR', settings: { ...base, roundToRupee: false }, employee: emp({ days: days('2026-10', oct) }) },
    expected: { payableDays: 28, grossPaise: 1083871, netPaise: 1083871, anomalies: [] },
  },
  // Divisor 26, week offs unpaid: 20 + 1 + 1 + 2 H = 24 → 12000 × 24/26 = 11076.92 → ₹11,077
  'monthly-divisor-26': {
    input: { month: '2026-10', currency: 'INR', settings: { ...base, monthDivisor: '26', weekOffsPaid: false }, employee: emp({ days: days('2026-10', oct) }) },
    expected: { payableDays: 24, grossPaise: 1107700, netPaise: 1107700, anomalies: [], explainIncludes: ['÷ 26 × 24'] },
  },
  // Divisor 30 with full month (31 payable) → capped at monthly rate
  'monthly-divisor-30-capped': {
    input: { month: '2026-10', currency: 'INR', settings: { ...base, monthDivisor: '30' }, employee: emp({ days: days('2026-10', (d, dow, day) => (dow === 0 ? 'week_off' : day === 2 || day === 20 ? 'holiday' : 'present')) }) },
    expected: { payableDays: 31, grossPaise: 1200000, netPaise: 1200000, anomalies: [], explainIncludes: ['capped'] },
  },
  // Daily ₹600: 20 P + 2 HD = 21 payable (week offs/holidays/leave... PL counts) → 20 + 1 + 1 PL = 22 → ₹13,200
  'daily-wage': {
    input: { month: '2026-10', currency: 'INR', settings: base, employee: emp({ wageType: 'daily', ratePaise: 60000, days: days('2026-10', oct) }) },
    expected: { payableDays: 22, grossPaise: 1320000, netPaise: 1320000, anomalies: [] },
  },
  // Daily wage with off days paid: 22 + 4 WO + 2 H = 28 → ₹16,800
  'daily-wage-off-days-paid': {
    input: { month: '2026-10', currency: 'INR', settings: { ...base, dailyPaysOffDays: true }, employee: emp({ wageType: 'daily', ratePaise: 60000, days: days('2026-10', oct) }) },
    expected: { payableDays: 28, grossPaise: 1680000, netPaise: 1680000, anomalies: [] },
  },
  // Feb 2026 ₹28,000 (₹1000/day): 2 sick leave unpaid → 22 P + 4 WO = 26 → ₹26,000
  'sick-leave-unpaid': {
    input: { month: '2026-02', currency: 'INR', settings: { ...base, sickLeavePaid: false }, employee: emp({ ratePaise: 2800000, days: days('2026-02', (d, dow, day) => (dow === 0 ? 'week_off' : day === 10 || day === 11 ? { status: 'leave', leaveType: 'sick' } : 'present')) }) },
    expected: { payableDays: 26, grossPaise: 2600000, netPaise: 2600000, summary: { present: 22, halfDay: 0, absent: 0, paidLeave: 0, unpaidLeave: 2, holidays: 0, weekOffs: 4, unmarked: 0 }, anomalies: [] },
  },
  // Joined 15 Feb: days 15–28 → 12 P + 2 WO = 14 of 28 → ₹14,000; days before joining ignored
  'joined-mid-month': {
    input: { month: '2026-02', currency: 'INR', settings: base, employee: emp({ ratePaise: 2800000, joiningDate: '2026-02-15', days: days('2026-02', (d, dow, day) => (day < 15 ? null : dow === 0 ? 'week_off' : 'present')) }) },
    expected: { payableDays: 14, grossPaise: 1400000, netPaise: 1400000, anomalies: [] },
  },
  // Full Feb ₹28,000 + ₹500 bonus − ₹200 deduction − advances (₹2,500 installment of ₹10,000 in 4; ₹3,000 full) → net ₹22,800
  'advances-bonus-deduction': {
    input: {
      month: '2026-02',
      currency: 'INR',
      settings: base,
      employee: emp({
        ratePaise: 2800000,
        days: days('2026-02', febFull),
        adjustments: [
          { id: 'b1', type: 'bonus', amountPaise: 50000, note: 'Diwali' },
          { id: 'd1', type: 'deduction', amountPaise: 20000, note: 'Broken glass' },
        ],
        advances: [
          { id: 'a1', date: '2026-01-05', amountPaise: 1000000, mode: 'installments', installments: 4, outstandingPaise: 1000000, skip: false },
          { id: 'a2', date: '2026-02-03', amountPaise: 300000, mode: 'full_next', installments: 1, outstandingPaise: 300000, skip: false },
          { id: 'a3', date: '2026-02-04', amountPaise: 100000, mode: 'full_next', installments: 1, outstandingPaise: 100000, skip: true },
        ],
      }),
    },
    expected: { payableDays: 28, grossPaise: 2850000, deductionsPaise: 570000, netPaise: 2280000, lines: [['basic', 2800000], ['bonus', 50000], ['deduction', 20000], ['advance', 250000], ['advance', 300000]], advanceDeductions: [['a1', 250000], ['a2', 300000]], anomalies: [] },
  },
  // ₹5,000/month, 5 P + 4 WO = 9 → ₹1,607; ₹3,000 advance capped at ₹1,607 → net 0
  'advance-capped': {
    input: {
      month: '2026-02',
      currency: 'INR',
      settings: base,
      employee: emp({ ratePaise: 500000, days: days('2026-02', (d, dow, day) => (dow === 0 ? 'week_off' : day <= 6 ? 'present' : 'absent')), advances: [{ id: 'a1', date: '2026-02-01', amountPaise: 300000, mode: 'full_next', installments: 1, outstandingPaise: 300000, skip: false }] }),
    },
    expected: { payableDays: 9, grossPaise: 160700, deductionsPaise: 160700, netPaise: 0, advanceDeductions: [['a1', 160700]], anomalies: ['advance_capped'] },
  },
  // 4 WO only → ₹714; ₹1,000 manual deduction → net −₹286 flagged
  'negative-net': {
    input: { month: '2026-02', currency: 'INR', settings: base, employee: emp({ ratePaise: 500000, days: days('2026-02', (d, dow) => (dow === 0 ? 'week_off' : 'absent')), adjustments: [{ id: 'd1', type: 'deduction', amountPaise: 100000 }] }) },
    expected: { payableDays: 4, grossPaise: 71400, deductionsPaise: 100000, netPaise: -28600, anomalies: ['negative_net'] },
  },
  // Net halves vs last month → big_change
  'big-change-vs-last-month': {
    input: { month: '2026-02', currency: 'INR', settings: base, employee: emp({ ratePaise: 2800000, lastNetPaise: 2800000, days: days('2026-02', (d, dow, day) => (dow === 0 ? 'week_off' : day <= 15 ? 'present' : 'absent')) }) },
    // Sundays 1,8,15 (≤15) and 22 → WO 4; present days ≤15 excluding Sundays = 12 → payable 16 → ₹16,000
    expected: { payableDays: 16, grossPaise: 1600000, netPaise: 1600000, anomalies: ['big_change'] },
  },
  // Days with no attendance are unpaid and flagged
  'unmarked-days': {
    input: { month: '2026-02', currency: 'INR', settings: base, employee: emp({ ratePaise: 2800000, days: days('2026-02', (d, dow, day) => (dow === 0 ? 'week_off' : day <= 20 ? 'present' : null)) }) },
    // ≤20: Sundays 1,8,15 → 3 WO + 17 P; after 20: Sun 22 WO, 7 unmarked → payable 21 → ₹21,000
    expected: { payableDays: 21, grossPaise: 2100000, netPaise: 2100000, summary: { present: 17, halfDay: 0, absent: 0, paidLeave: 0, unpaidLeave: 0, holidays: 0, weekOffs: 4, unmarked: 7 }, anomalies: ['unmarked_days'] },
  },
  // Running estimate as of 10 Feb: 8 P + 2 WO = 10 → ₹10,000 (later days ignored, no anomalies)
  'running-estimate': {
    input: { month: '2026-02', currency: 'INR', settings: base, asOfDate: '2026-02-10', employee: emp({ ratePaise: 2800000, days: days('2026-02', (d, dow, day) => (day > 10 ? null : dow === 0 ? 'week_off' : 'present')) }) },
    expected: { payableDays: 10, grossPaise: 1000000, netPaise: 1000000, anomalies: [] },
  },
};

fs.mkdirSync(dir, { recursive: true });
for (const [name, c] of Object.entries(cases)) fs.writeFileSync(`${dir}/${name}.json`, JSON.stringify(c, null, 2) + '\n');
console.log(`wrote ${Object.keys(cases).length} golden files to ${dir}`);
