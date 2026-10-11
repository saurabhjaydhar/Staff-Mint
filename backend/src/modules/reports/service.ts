import ExcelJS from 'exceljs';
import type { Ctx } from '../../lib/context.js';
import { formatMoney } from '../../lib/money.js';
import { monthLabel, monthDays } from '../../lib/dates.js';
import { AppError } from '../../lib/errors.js';
import { Attendance, Company, Employee, PayrollRun, Payslip } from '../../models/index.js';
import { monthGrid } from '../attendance/service.js';
import { listAdvances } from '../advances/service.js';
import { employeeScope } from '../employees/service.js';
import { tableReportHtml } from '../payslips/templates.js';
import { provider } from '../../providers/registry.js';

export type ReportKind = 'attendance' | 'salary' | 'advances' | 'late';

interface ReportTable {
  title: string;
  subtitle: string;
  headers: string[];
  rows: (string | number)[][];
  landscape?: boolean;
}

export async function buildReport(ctx: Ctx, kind: ReportKind, month: string): Promise<ReportTable> {
  const company = await Company.findById(ctx.companyId).lean();
  const money = (p: number) => formatMoney(p, company!.currency);
  switch (kind) {
    case 'attendance': {
      const g = await monthGrid(ctx, month);
      const days = g.days.map((d) => d.slice(8));
      return {
        title: 'Monthly attendance / मासिक हाज़िरी',
        subtitle: monthLabel(month),
        headers: ['Name', ...days, 'P', 'A', 'HD', 'L', 'WO/H'],
        rows: g.rows.map((r) => [r.employee.name, ...g.days.map((d) => r.codes[d] ?? ''), r.totals.present, r.totals.absent, r.totals.halfDay, r.totals.leave, r.totals.weekOff + r.totals.holiday]),
        landscape: true,
      };
    }
    case 'salary': {
      const run = await PayrollRun.findOne({ companyId: ctx.companyId, month, status: { $ne: 'superseded' } }).sort({ revision: -1 }).lean();
      if (!run) throw new AppError('NOT_FOUND', `No salary run for ${month}. Create one first.`);
      const slips = await Payslip.find({ companyId: ctx.companyId, runId: run._id }).sort({ employeeName: 1 }).lean();
      const sum = (...codes: string[]) => (s: any) => s.lines.filter((l: any) => codes.includes(l.code)).reduce((a: number, l: any) => a + l.amountPaise, 0);
      // PF / ESI / PT columns only when this month has them (most small shops don't).
      const statutory = (['pf', 'esi', 'pt'] as const).filter((c) => slips.some((s: any) => sum(c)(s) > 0));
      const label = { pf: 'PF', esi: 'ESI', pt: 'Prof. tax' };
      const rows = slips.map((s: any) => [
        s.employeeName,
        s.wageType,
        money(s.ratePaise),
        s.payableDays,
        money(sum('basic', 'allowance')(s)),
        money(sum('bonus')(s)),
        money(s.grossPaise ?? 0),
        ...statutory.map((c) => money(sum(c)(s))),
        money(sum('deduction')(s)),
        money(sum('advance')(s)),
        money(s.netPaise),
      ]);
      const total = (f: (s: any) => number) => money(slips.reduce((a: number, s: any) => a + f(s), 0));
      rows.push(['TOTAL', '', '', '', total(sum('basic', 'allowance')), total(sum('bonus')), total((s) => s.grossPaise ?? 0), ...statutory.map((c) => total(sum(c))), total(sum('deduction')), total(sum('advance')), money(run.totals?.netPaise ?? 0)]);
      return {
        title: 'Salary register / वेतन रजिस्टर',
        subtitle: `${monthLabel(month)} · ${run.status} · rev ${run.revision}`,
        headers: ['Name', 'Type', 'Rate', 'Paid days', 'Earned', 'Bonus', 'Gross', ...statutory.map((c) => label[c]), 'Deductions', 'Advance', 'Net pay'],
        rows,
        landscape: true,
      };
    }
    case 'advances': {
      const list = await listAdvances(ctx, {});
      return {
        title: 'Advances / एडवांस',
        subtitle: `As of ${new Date().toISOString().slice(0, 10)}`,
        headers: ['Name', 'Date', 'Amount', 'Mode', 'Repaid', 'Balance', 'Status'],
        rows: list.map((a) => [a.employeeName ?? '', a.date, money(a.amountPaise), a.mode === 'full_next' ? 'Full next salary' : `${a.installments} installments`, money(a.repaidPaise), money(a.balancePaise), a.status]),
      };
    }
    case 'late': {
      const days = monthDays(month);
      const emps = await Employee.find(employeeScope(ctx)).lean();
      const names = new Map(emps.map((e) => [String(e._id), e.name]));
      const recs = await Attendance.find({ companyId: ctx.companyId, employeeId: { $in: emps.map((e) => e._id) }, date: { $gte: days[0], $lte: days[days.length - 1] }, lateMinutes: { $gt: 0 } })
        .sort({ date: 1 })
        .lean();
      const counts = new Map<string, number>();
      for (const r of recs) counts.set(String(r.employeeId), (counts.get(String(r.employeeId)) ?? 0) + 1);
      return {
        title: 'Late arrivals / देर से आए',
        subtitle: monthLabel(month),
        headers: ['Date', 'Name', 'Late by (min)', 'Times late this month'],
        rows: recs.map((r) => [r.date, names.get(String(r.employeeId)) ?? '', r.lateMinutes, counts.get(String(r.employeeId)) ?? 0]),
      };
    }
  }
}

export async function toXlsx(sheets: { name: string; headers: string[]; rows: (string | number | null)[][] }[]): Promise<Buffer> {
  const wb = new ExcelJS.Workbook();
  wb.creator = 'StaffMint';
  for (const s of sheets) {
    const ws = wb.addWorksheet(s.name.slice(0, 31));
    ws.addRow(s.headers).font = { bold: true };
    for (const r of s.rows) ws.addRow(r);
    ws.columns.forEach((c) => (c.width = 14));
    ws.getColumn(1).width = 24;
  }
  return Buffer.from(await wb.xlsx.writeBuffer());
}

export async function renderReport(ctx: Ctx, kind: ReportKind, month: string, format: 'pdf' | 'xlsx') {
  const t = await buildReport(ctx, kind, month);
  const company = await Company.findById(ctx.companyId).lean();
  const filename = `${kind}-${month}.${format}`;
  if (format === 'xlsx') return { filename, contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', data: await toXlsx([{ name: kind, headers: t.headers, rows: t.rows }]) };
  const pdf = await (await provider('pdf')).render(tableReportHtml(t.title, company!.name, t.headers, t.rows, t.subtitle), { landscape: t.landscape });
  return { filename, contentType: 'application/pdf', data: pdf };
}
