/**
 * Pure, deterministic payroll engine (PRD F8). No I/O, no clock, no randomness.
 * "AI suggests, code calculates, owner confirms." Every number carries a plain-language reason.
 * Bump ENGINE_VERSION whenever output for the same input could change.
 */
import { formatMoney, roundToRupee } from '../../lib/money.js';

export const ENGINE_VERSION = '1.1.0';

export type DayStatus = 'present' | 'absent' | 'half_day' | 'leave' | 'holiday' | 'week_off' | null;
export type LeaveType = 'paid' | 'sick' | 'unpaid';

export interface PayrollSettings {
  monthDivisor: 'days_in_month' | '30' | '26';
  weekOffsPaid: boolean;
  holidaysPaid: boolean;
  sickLeavePaid: boolean;
  dailyPaysOffDays: boolean;
  roundToRupee: boolean;
  /** PF / ESI / Professional Tax. Absent or all off = the simple shop salary slip (most small shops). */
  statutory?: StatutorySettings | null;
}

/** Indian statutory deductions. Rates and limits are settings so they can follow rule changes without a release. */
export interface StatutorySettings {
  pfEnabled: boolean;
  /** Part of the earned salary shown as Basic (PF is on Basic); the rest is "HRA & allowances". */
  basicPercent: number;
  pfRatePercent: number;
  pfWageCeilingPaise: number;
  /** Calculate PF on at most the wage ceiling (the usual choice). */
  pfCapAtCeiling: boolean;
  esiEnabled: boolean;
  esiEmployeePercent: number;
  esiEmployerPercent: number;
  /** ESI applies when the month's ESI wages are at or below this. */
  esiWageLimitPaise: number;
  ptEnabled: boolean;
  /** State Professional Tax for the month (owner enters their state's amount). */
  ptMonthlyPaise: number;
  /** Charge PT only when gross is at least this (state slab). */
  ptMinGrossPaise: number;
}

export const DEFAULT_STATUTORY: StatutorySettings = {
  pfEnabled: false,
  basicPercent: 50,
  pfRatePercent: 12,
  pfWageCeilingPaise: 1500000,
  pfCapAtCeiling: true,
  esiEnabled: false,
  esiEmployeePercent: 0.75,
  esiEmployerPercent: 3.25,
  esiWageLimitPaise: 2100000,
  ptEnabled: false,
  ptMonthlyPaise: 20000,
  ptMinGrossPaise: 0,
};

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
  /** This person is outside PF / ESI (e.g. opted out, or covered elsewhere). */
  pfExempt?: boolean;
  esiExempt?: boolean;
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
  code: 'basic' | 'allowance' | 'bonus' | 'deduction' | 'advance' | 'pf' | 'esi' | 'pt';
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
  /** Paid by the employer on top of salary (not cut from the staff member). Shown on the slip for PF/ESI. */
  employerContributions: { code: 'pf' | 'esi'; amountPaise: number; label: Bilingual; explanation: Bilingual }[];
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
      hi: `${parts.hi} → ${fmtDays(payable)} पैसे वाले दिन। ${money(e.ratePaise)}/दिन × ${fmtDays(payable)} = ${money(basic)}`,
    };
  } else {
    const raw = (e.ratePaise * payable) / divisor;
    const capped = Math.min(raw, e.ratePaise);
    basic = round(capped);
    const capNote = raw > e.ratePaise ? { en: ' (capped at full monthly salary)', hi: ' (पूरी महीने की सैलरी तक सीमित)' } : { en: '', hi: '' };
    basicExplain = {
      en: `${parts.en} → ${fmtDays(payable)} payable days of ${divisor}. ${money(e.ratePaise)} ÷ ${divisor} × ${fmtDays(payable)} = ${money(basic)}${capNote.en}`,
      hi: `${parts.hi} → ${divisor} में से ${fmtDays(payable)} पैसे वाले दिन। ${money(e.ratePaise)} ÷ ${divisor} × ${fmtDays(payable)} = ${money(basic)}${capNote.hi}`,
    };
  }

  const st = settings.statutory ?? null;
  const pfOn = !!st?.pfEnabled && !e.pfExempt;
  const esiOn = !!st?.esiEnabled && !e.esiExempt;
  const ptOn = !!st?.ptEnabled && (st?.ptMonthlyPaise ?? 0) > 0;
  // With PF, the earned salary is shown as Basic + HRA & allowances (PF is calculated on Basic).
  const basicPercent = pfOn ? Math.min(100, Math.max(1, st!.basicPercent)) : 100;
  const basicPart = basicPercent < 100 ? round((basic * basicPercent) / 100) : basic;
  const allowancePart = basic - basicPart;
  const lines: EngineLine[] = [
    {
      code: 'basic',
      kind: 'earning',
      amountPaise: basicPart,
      label:
        allowancePart > 0
          ? { en: `Basic (${fmtDays(payable)} days)`, hi: `बेसिक (${fmtDays(payable)} दिन)` }
          : { en: `Salary for ${fmtDays(payable)} days`, hi: `${fmtDays(payable)} दिन की सैलरी` },
      explanation:
        allowancePart > 0
          ? { en: `${basicExplain.en}. ${basicPercent}% of it is Basic.`, hi: `${basicExplain.hi}। इसका ${basicPercent}% बेसिक है।` }
          : basicExplain,
    },
  ];
  if (allowancePart > 0) {
    lines.push({
      code: 'allowance',
      kind: 'earning',
      amountPaise: allowancePart,
      label: { en: 'HRA & allowances', hi: 'मकान किराया भत्ता व अन्य भत्ते' },
      explanation: { en: `The other ${100 - basicPercent}% of the salary earned (${money(basic)}).`, hi: `कमाई गई सैलरी (${money(basic)}) का बाकी ${100 - basicPercent}%।` },
    });
  }

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

  // ---- Statutory deductions (PF, ESI, Professional Tax): before advances, never below zero ----
  const employerContributions: EngineResult['employerContributions'] = [];
  const toRupee = (p: number) => Math.round(p / 100) * 100;
  const upToRupee = (p: number) => Math.ceil(p / 100) * 100;
  const addStatutory = (code: 'pf' | 'esi' | 'pt', amount: number, label: Bilingual, explanation: Bilingual) => {
    const take = Math.min(amount, Math.max(0, gross - deductions));
    if (take <= 0) return;
    deductions += take;
    lines.push({ code, kind: 'deduction', amountPaise: take, label, explanation });
  };
  if (st && pfOn && basicPart > 0) {
    const base = st.pfCapAtCeiling ? Math.min(basicPart, st.pfWageCeilingPaise) : basicPart;
    const pf = toRupee((base * st.pfRatePercent) / 100);
    const capped = st.pfCapAtCeiling && basicPart > st.pfWageCeilingPaise;
    addStatutory(
      'pf',
      pf,
      { en: 'Provident Fund (PF)', hi: 'भविष्य निधि (PF)' },
      {
        en: `${st.pfRatePercent}% of Basic ${money(base)}${capped ? ` (capped at ${money(st.pfWageCeilingPaise)})` : ''}. Saved in your PF account.`,
        hi: `बेसिक ${money(base)} का ${st.pfRatePercent}%${capped ? ` (${money(st.pfWageCeilingPaise)} तक)` : ''}। आपके PF खाते में जमा।`,
      },
    );
    if (pf > 0)
      employerContributions.push({
        code: 'pf',
        amountPaise: pf,
        label: { en: 'Employer PF', hi: 'मालिक का PF' },
        explanation: { en: `${st.pfRatePercent}% of Basic, paid by the employer (EPF + pension)`, hi: `बेसिक का ${st.pfRatePercent}%, मालिक देता है (EPF + पेंशन)` },
      });
  }
  const esiWages = lines.filter((l) => l.kind === 'earning' && l.code !== 'bonus').reduce((a, l) => a + l.amountPaise, 0);
  if (st && esiOn && esiWages > 0 && esiWages <= st.esiWageLimitPaise) {
    const esi = upToRupee((esiWages * st.esiEmployeePercent) / 100);
    addStatutory(
      'esi',
      esi,
      { en: 'ESI', hi: 'ESI (स्टाफ़ का सरकारी बीमा)' },
      { en: `${st.esiEmployeePercent}% of ${money(esiWages)}. Covers medical care for you and your family.`, hi: `${money(esiWages)} का ${st.esiEmployeePercent}%। आपके और परिवार के इलाज के लिए।` },
    );
    employerContributions.push({
      code: 'esi',
      amountPaise: upToRupee((esiWages * st.esiEmployerPercent) / 100),
      label: { en: 'Employer ESI', hi: 'मालिक का ESI' },
      explanation: { en: `${st.esiEmployerPercent}% of ${money(esiWages)}, paid by the employer`, hi: `${money(esiWages)} का ${st.esiEmployerPercent}%, मालिक देता है` },
    });
  }
  if (st && ptOn && gross > 0 && gross >= st.ptMinGrossPaise) {
    addStatutory(
      'pt',
      st.ptMonthlyPaise,
      { en: 'Professional Tax', hi: 'प्रोफ़ेशनल टैक्स' },
      { en: `State Professional Tax for the month: ${money(st.ptMonthlyPaise)}`, hi: `इस महीने का राज्य प्रोफ़ेशनल टैक्स: ${money(st.ptMonthlyPaise)}` },
    );
  }

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

  if (capped) anomalies.push({ code: 'advance_capped', message: { en: 'Advance deduction reduced so salary does not go negative', hi: 'सैलरी माइनस न हो, इसलिए एडवांस कटौती कम की गई' } });
  if (e.ratePaise <= 0) anomalies.push({ code: 'zero_rate', message: { en: 'Salary amount is not set', hi: 'सैलरी सेट नहीं है' } });
  if (summary.unmarked > 0)
    anomalies.push({ code: 'unmarked_days', message: { en: `${summary.unmarked} day(s) have no attendance`, hi: `${summary.unmarked} दिन की हाज़िरी नहीं लगी` } });
  if (payable === 0 && !input.asOfDate) anomalies.push({ code: 'no_payable_days', message: { en: 'No payable days this month', hi: 'इस महीने कोई पैसे वाला दिन नहीं' } });
  if (net < 0) anomalies.push({ code: 'negative_net', message: { en: `Net salary is negative (${money(net)})`, hi: `कुल सैलरी माइनस में है (${money(net)})` } });
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
    employerContributions,
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
  add(paid, s.paidLeave, `Paid leave ${s.paidLeave}`, `पेड छुट्टी ${s.paidLeave}`);
  add(offPaid(settings.weekOffsPaid) ? paid : unpaid, s.weekOffs, `${offPaid(settings.weekOffsPaid) ? 'Week offs' : 'week offs'} ${s.weekOffs}`, `साप्ताहिक छुट्टी ${s.weekOffs}`);
  add(offPaid(settings.holidaysPaid) ? paid : unpaid, s.holidays, `${offPaid(settings.holidaysPaid) ? 'Holidays' : 'holidays'} ${s.holidays}`, `त्योहार छुट्टी ${s.holidays}`);
  add(unpaid, s.absent, `absent ${s.absent}`, `गैरहाज़िर ${s.absent}`);
  add(unpaid, s.unpaidLeave, `unpaid leave ${s.unpaidLeave}`, `बिना पैसे की छुट्टी ${s.unpaidLeave}`);
  add(unpaid, s.unmarked, `not marked ${s.unmarked}`, `हाज़िरी नहीं ${s.unmarked}`);
  const join = (l: Bilingual[], k: 'en' | 'hi') => l.map((x) => x[k]).join(', ');
  return {
    en: (join(paid, 'en') || 'No paid days') + (unpaid.length ? `; not paid: ${join(unpaid, 'en')}` : ''),
    hi: (join(paid, 'hi') || 'कोई पैसे वाला दिन नहीं') + (unpaid.length ? `; पैसे नहीं: ${join(unpaid, 'hi')}` : ''),
  };
}
