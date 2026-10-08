import { formatMoney, parseAmountToPaise } from '../../lib/money.js';
import { normalizePhone } from '../../lib/phone.js';
import { readTable } from '../imports/parse.js';

const norm = (s: string) => s.toLowerCase().replace(/[^a-zऀ-ॿ0-9]/g, '');

const COLS = {
  name: ['name', 'employee', 'employeename', 'staff', 'staffname', 'naam', 'नाम', 'कर्मचारी'],
  phone: ['phone', 'mobile', 'mobileno', 'phoneno', 'contact', 'number', 'मोबाइल'],
  net: ['net', 'netpay', 'netsalary', 'netpayable', 'payable', 'inhand', 'takehome', 'finalsalary', 'amountpaid', 'totalpayable', 'salarypayable', 'कुलवेतन'],
  gross: ['gross', 'grosssalary', 'grosspay', 'earned', 'totalearnings', 'earnedsalary'],
  days: ['payabledays', 'paiddays', 'presentdays', 'workingdays', 'present', 'days', 'हाज़िरी'],
  deductions: ['deductions', 'totaldeductions', 'advance', 'advancededucted', 'kataut', 'कटौती'],
};

function findCol(headers: string[], keys: string[]) {
  const nh = headers.map(norm);
  for (const k of keys) {
    const i = nh.indexOf(norm(k));
    if (i >= 0) return headers[i];
  }
  for (const k of keys) {
    const i = nh.findIndex((h) => h.includes(norm(k)));
    if (i >= 0) return headers[i];
  }
  return null;
}

/** Parallel-run compare (PRD F8): line-by-line diff of our run vs the old app's report, with plain reasons. */
export async function compareWithReport(file: { buffer: Buffer; originalname: string }, payslips: any[], divisorSetting: string) {
  const { headers, rows } = await readTable(file.buffer, file.originalname);
  const col = Object.fromEntries(Object.entries(COLS).map(([k, keys]) => [k, findCol(headers, keys)])) as Record<keyof typeof COLS, string | null>;
  if (!col.net && !col.gross) throw Object.assign(new Error('Could not find a net/gross salary column in the file'), { code: 'VALIDATION_ERROR' });
  const out: any[] = [];
  const matchedIds = new Set<string>();
  for (const row of rows) {
    const name = col.name ? String(row[col.name] ?? '').trim() : '';
    const phone = col.phone ? normalizePhone(row[col.phone]) : null;
    if (!name && !phone) continue;
    const slip = payslips.find((p) => phone && p.employeePhone === phone) ?? payslips.find((p) => name && norm(p.employeeName) === norm(name)) ?? payslips.find((p) => name && norm(p.employeeName).startsWith(norm(name).slice(0, 4)) && norm(name).length >= 4);
    const theirNet = col.net ? parseAmountToPaise(row[col.net]) : null;
    const theirGross = col.gross ? parseAmountToPaise(row[col.gross]) : null;
    const theirDays = col.days ? Number(String(row[col.days]).replace(/[^\d.]/g, '')) : null;
    const theirDed = col.deductions ? parseAmountToPaise(row[col.deductions]) : null;
    if (!slip) {
      out.push({ employeeName: name || phone, ours: null, theirs: theirNet ?? theirGross, diffPaise: null, reasons: ['Not found in StaffMint — add this employee or check the name/phone'] });
      continue;
    }
    matchedIds.add(String(slip.employeeId));
    const theirs = theirNet ?? theirGross!;
    const ours = theirNet !== null ? slip.netPaise : slip.grossPaise;
    const diff = ours - theirs;
    const reasons: string[] = [];
    if (Math.abs(diff) < 100) reasons.push(diff === 0 ? 'Matches' : 'Rounding difference only');
    else {
      if (theirDays !== null && !Number.isNaN(theirDays) && Math.abs(theirDays - slip.payableDays) >= 0.5) {
        reasons.push(`Payable days differ: old app ${theirDays}, StaffMint ${slip.payableDays}. Check absent/half-day/leave entries.`);
      }
      if (slip.wageType === 'monthly' && theirDays !== null && theirDays > 0 && theirGross) {
        for (const div of [30, 26, slip.daysInMonth]) {
          if (div === slip.divisor) continue;
          const est = Math.round((slip.ratePaise * theirDays) / div);
          if (Math.abs(est - theirGross) <= 200) reasons.push(`Old app seems to divide by ${div} days; StaffMint divides by ${slip.divisor} (${divisorSetting}). Change it in Settings if needed.`);
        }
      }
      if (theirGross !== null && Math.abs(theirGross - slip.grossPaise) < 100 && theirNet !== null) {
        reasons.push(`Same gross, different deductions: old app ${theirDed !== null ? formatMoney(theirDed) : formatMoney(theirGross - theirNet)}, StaffMint ${formatMoney(slip.deductionsPaise)} (advances/deductions).`);
      }
      if (!reasons.length) reasons.push(`StaffMint is ${diff > 0 ? 'higher' : 'lower'} by ${formatMoney(Math.abs(diff))}. Compare attendance for this month.`);
    }
    out.push({ employeeId: String(slip.employeeId), employeeName: slip.employeeName, ours, theirs, diffPaise: diff, reasons });
  }
  for (const p of payslips) if (!matchedIds.has(String(p.employeeId))) out.push({ employeeId: String(p.employeeId), employeeName: p.employeeName, ours: p.netPaise, theirs: null, diffPaise: null, reasons: ['Missing in the old app report'] });
  return { columns: col, rows: out, matched: matchedIds.size, unmatched: out.filter((r) => r.diffPaise === null).length };
}
