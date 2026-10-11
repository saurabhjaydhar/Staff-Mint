import { Types } from 'mongoose';
import { monthDays, previousMonth } from '../../lib/dates.js';
import { Adjustment, Attendance, Company, Employee, PayrollRun, Payslip } from '../../models/index.js';
import { dayContext, implicitStatus } from '../attendance/service.js';
import { advancesForMonth, outstandingOf } from '../advances/service.js';
import { rateOn } from '../employees/service.js';
import { DEFAULT_STATUTORY, type EngineInput, type PayrollSettings, type StatutorySettings } from './engine.js';

export function payrollSettingsOf(company: any): PayrollSettings {
  const s = company.settings ?? {};
  return {
    monthDivisor: s.monthDivisor ?? 'days_in_month',
    weekOffsPaid: s.weekOffsPaid ?? true,
    holidaysPaid: s.holidaysPaid ?? true,
    sickLeavePaid: s.sickLeavePaid ?? true,
    dailyPaysOffDays: s.dailyPaysOffDays ?? false,
    roundToRupee: s.roundToRupee ?? true,
    statutory: statutoryOf(company),
  };
}

/** The engine's statutory settings, or null when the shop uses none of PF / ESI / PT. */
export function statutoryOf(company: any): StatutorySettings | null {
  const st = company?.settings?.statutory;
  if (!st || !(st.pfEnabled || st.esiEnabled || st.ptEnabled)) return null;
  return {
    pfEnabled: !!st.pfEnabled,
    basicPercent: st.basicPercent ?? DEFAULT_STATUTORY.basicPercent,
    pfRatePercent: st.pfRatePercent ?? DEFAULT_STATUTORY.pfRatePercent,
    pfWageCeilingPaise: st.pfWageCeilingPaise ?? DEFAULT_STATUTORY.pfWageCeilingPaise,
    pfCapAtCeiling: st.pfCapAtCeiling ?? true,
    esiEnabled: !!st.esiEnabled,
    esiEmployeePercent: st.esiEmployeePercent ?? DEFAULT_STATUTORY.esiEmployeePercent,
    esiEmployerPercent: st.esiEmployerPercent ?? DEFAULT_STATUTORY.esiEmployerPercent,
    esiWageLimitPaise: st.esiWageLimitPaise ?? DEFAULT_STATUTORY.esiWageLimitPaise,
    ptEnabled: !!st.ptEnabled,
    ptMonthlyPaise: st.ptMonthlyPaise ?? DEFAULT_STATUTORY.ptMonthlyPaise,
    ptMinGrossPaise: st.ptMinGrossPaise ?? 0,
  };
}

/** Employees on payroll for a month: active and joined by month end, or exited during the month. */
export async function payrollEmployees(companyId: Types.ObjectId, month: string, employeeIds?: Types.ObjectId[]) {
  const days = monthDays(month);
  const first = days[0];
  const last = days[days.length - 1];
  const f: any = { companyId, deletedAt: null };
  if (employeeIds) f._id = { $in: employeeIds };
  const emps = await Employee.find(f).sort({ name: 1 }).lean();
  return emps.filter((e) => (!e.joiningDate || e.joiningDate <= last) && (e.status === 'active' || (e.exitDate && e.exitDate >= first)));
}

/** Snapshot every input the engine needs (also stored on the payslip for reproducibility). */
export async function buildEngineInputs(companyId: Types.ObjectId, month: string, opts: { employeeIds?: Types.ObjectId[]; asOfDate?: string } = {}): Promise<EngineInput[]> {
  const company = await Company.findById(companyId).lean();
  const days = monthDays(month);
  const emps = await payrollEmployees(companyId, month, opts.employeeIds);
  const ids = emps.map((e) => e._id);
  const [records, adjustments, advances, dc, prevRuns] = await Promise.all([
    Attendance.find({ companyId, employeeId: { $in: ids }, date: { $gte: days[0], $lte: days[days.length - 1] } }).lean(),
    Adjustment.find({ companyId, month, employeeId: { $in: ids }, deletedAt: null }).lean(),
    advancesForMonth(companyId, ids, month),
    dayContext(companyId, days[0], days[days.length - 1], ids),
    PayrollRun.find({ companyId, month: previousMonth(month), status: { $in: ['approved', 'paid'] } }).sort({ revision: -1 }).limit(1).lean(),
  ]);
  const prevSlips = prevRuns[0] ? await Payslip.find({ companyId, runId: prevRuns[0]._id }).lean() : [];
  const lastNet = new Map(prevSlips.map((p) => [String(p.employeeId), p.netPaise ?? null]));
  const rec = new Map(records.map((r) => [`${r.employeeId}:${r.date}`, r]));
  const settings = payrollSettingsOf(company);
  const out: EngineInput[] = [];
  for (const e of emps) {
    const rate = await rateOn(companyId, e as any, opts.asOfDate ?? days[days.length - 1]);
    out.push({
      month,
      currency: company!.currency,
      settings,
      asOfDate: opts.asOfDate ?? null,
      employee: {
        employeeId: String(e._id),
        name: e.name,
        wageType: rate.wageType,
        ratePaise: rate.ratePaise,
        joiningDate: e.joiningDate ?? null,
        exitDate: e.exitDate ?? null,
        days: days.map((d) => {
          const r = rec.get(`${e._id}:${d}`);
          if (r?.status) return { date: d, status: r.status as any, leaveType: (r.leaveType as any) ?? null };
          const imp = implicitStatus(dc, e, d);
          return { date: d, status: imp?.status ?? null, leaveType: imp?.leaveType ?? null };
        }),
        adjustments: adjustments.filter((a) => String(a.employeeId) === String(e._id)).map((a) => ({ id: String(a._id), type: a.type as any, amountPaise: a.amountPaise, note: a.note ?? undefined })),
        advances: advances
          .filter((a) => String(a.employeeId) === String(e._id))
          .map((a) => ({ id: String(a._id), date: a.date, amountPaise: a.amountPaise, mode: a.mode as any, installments: a.installments, outstandingPaise: outstandingOf(a, month), skip: a.skipMonths.includes(month) })),
        lastNetPaise: lastNet.get(String(e._id)) ?? (e as any).openingLastNetPaise ?? null,
        pfExempt: !!(e as any).pfExempt,
        esiExempt: !!(e as any).esiExempt,
      },
    });
  }
  return out;
}
