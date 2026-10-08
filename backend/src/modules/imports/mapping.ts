import { parseAmountToPaise } from '../../lib/money.js';
import { normalizePhone } from '../../lib/phone.js';
import { parseDateLoose } from './parse.js';

export const STAFF_FIELDS = ['name', 'phone', 'ratePaise', 'wageType', 'designation', 'joiningDate', 'branch', 'advanceBalancePaise', 'paidLeaveBalance', 'sickLeaveBalance', 'lastSalaryPaise'] as const;
export type StaffField = (typeof STAFF_FIELDS)[number];
export type Mapping = Record<string, StaffField | null>;
export type MappingMethod = Record<string, 'template' | 'synonym' | 'sniff' | 'llm' | 'manual'>;

const norm = (s: string) => s.toLowerCase().replace(/[^a-zऀ-ॿ0-9]/g, '');

/** Hindi/English synonym list (PRD F2). */
export const SYNONYMS: Record<StaffField, string[]> = {
  name: ['name', 'naam', 'नाम', 'employeename', 'staffname', 'fullname', 'employee', 'staff', 'karmchari', 'कर्मचारी', 'worker', 'workername', 'empname'],
  phone: ['phone', 'mobile', 'mob', 'mobileno', 'mobilenumber', 'phoneno', 'phonenumber', 'contact', 'contactno', 'contactnumber', 'whatsapp', 'whatsappno', 'number', 'फ़ोन', 'फोन', 'मोबाइल', 'nambar'],
  ratePaise: ['salary', 'monthlysalary', 'salaryamount', 'basicsalary', 'basic', 'pay', 'wage', 'wages', 'dailywage', 'perday', 'rate', 'ctc', 'amount', 'tankhwah', 'tankha', 'tankhwa', 'vetan', 'वेतन', 'तनख्वाह', 'पगार', 'pagar', 'grosssalary', 'fixedsalary'],
  wageType: ['salarytype', 'wagetype', 'paytype', 'paymenttype', 'type', 'salarybasis', 'paymode'],
  designation: ['designation', 'role', 'post', 'position', 'job', 'jobtitle', 'title', 'kaam', 'पद', 'department'],
  joiningDate: ['doj', 'dateofjoining', 'joiningdate', 'joined', 'joinedon', 'startdate', 'joining', 'dateofjoin'],
  branch: ['branch', 'location', 'shop', 'store', 'outlet', 'site', 'office'],
  advanceBalancePaise: ['advance', 'advancebalance', 'advancedue', 'udhaar', 'udhar', 'उधार', 'एडवांस', 'loan', 'loanbalance', 'pendingadvance'],
  paidLeaveBalance: ['paidleave', 'pl', 'leavebalance', 'earnedleave', 'el', 'casualleave', 'cl', 'paidleavebalance'],
  sickLeaveBalance: ['sickleave', 'sl', 'sickleavebalance'],
  lastSalaryPaise: ['lastsalary', 'previoussalary', 'lastmonthsalary', 'lastnetpay', 'lastpaid'],
};

/** Competitor export templates. Header names to be verified against real sample files (see docs). */
export const TEMPLATES: { source: string; signature: string[]; mapping: Record<string, StaffField> }[] = [
  {
    source: 'salarybox',
    signature: ['staffname', 'phonenumber', 'salarytype'],
    mapping: { staffname: 'name', phonenumber: 'phone', salarytype: 'wageType', salaryamount: 'ratePaise', salary: 'ratePaise', dateofjoining: 'joiningDate', designation: 'designation', branch: 'branch', advance: 'advanceBalancePaise' },
  },
  {
    source: 'pagarbook',
    signature: ['name', 'mobilenumber', 'salary'],
    mapping: { name: 'name', mobilenumber: 'phone', salary: 'ratePaise', salarytype: 'wageType', paymenttype: 'wageType', joiningdate: 'joiningDate', designation: 'designation', advancebalance: 'advanceBalancePaise' },
  },
];

export function detectTemplate(headers: string[]) {
  const nh = new Set(headers.map(norm));
  return TEMPLATES.find((t) => t.signature.every((s) => nh.has(s))) ?? null;
}

function sniff(values: unknown[]): StaffField | null {
  const vals = values.map((v) => (v instanceof Date ? v : String(v ?? '').trim())).filter((v) => v !== '');
  if (vals.length === 0) return null;
  const ratio = (fn: (v: any) => boolean) => vals.filter(fn).length / vals.length;
  if (ratio((v) => typeof v === 'string' && normalizePhone(v) !== null && v.replace(/\D/g, '').length >= 10) > 0.7) return 'phone';
  if (ratio((v) => /^(monthly|daily|month|day|mahina|mahine|din|dihadi|मासिक|दैनिक)$/i.test(String(v))) > 0.7) return 'wageType';
  if (ratio((v) => v instanceof Date || (typeof v === 'string' && /[/\-.]/.test(v) && parseDateLoose(v) !== null)) > 0.7) return 'joiningDate';
  if (ratio((v) => {
    const p = parseAmountToPaise(v);
    return p !== null && p >= 20000 && p <= 100_000_00;
  }) > 0.7)
    return 'ratePaise';
  if (ratio((v) => typeof v === 'string' && /^[a-zऀ-ॿ .']{2,40}$/i.test(v) && /[a-zऀ-ॿ]/i.test(v)) > 0.8) return 'name';
  return null;
}

export function autoMap(headers: string[], rows: Record<string, unknown>[]): { mapping: Mapping; method: MappingMethod; template: string | null } {
  const mapping: Mapping = Object.fromEntries(headers.map((h) => [h, null]));
  const method: MappingMethod = {};
  const used = new Set<StaffField>();
  const assign = (h: string, f: StaffField, m: MappingMethod[string]) => {
    if (used.has(f) || mapping[h]) return;
    mapping[h] = f;
    method[h] = m;
    used.add(f);
  };
  const tpl = detectTemplate(headers);
  if (tpl) for (const h of headers) if (tpl.mapping[norm(h)]) assign(h, tpl.mapping[norm(h)], 'template');
  // exact synonym, then contains-synonym
  for (const h of headers) for (const f of STAFF_FIELDS) if (SYNONYMS[f].includes(norm(h))) assign(h, f, 'synonym');
  for (const h of headers) {
    if (mapping[h]) continue;
    const n = norm(h);
    for (const f of STAFF_FIELDS) if (n.length >= 3 && SYNONYMS[f].some((s) => s.length >= 4 && n.includes(s))) assign(h, f, 'synonym');
  }
  for (const h of headers) {
    if (mapping[h]) continue;
    const f = sniff(rows.slice(0, 50).map((r) => r[h]));
    if (f) assign(h, f, 'sniff');
  }
  return { mapping, method, template: tpl?.source ?? null };
}

export interface RowIssue {
  field: string;
  message: string;
  severity: 'error' | 'warning';
}

export interface CleanRow {
  index: number;
  values: Partial<Record<StaffField, any>>;
  issues: RowIssue[];
}

export function normalizeWageType(v: unknown): 'monthly' | 'daily' | null {
  const s = String(v ?? '').trim().toLowerCase();
  if (!s) return null;
  if (/^(daily|day|per ?day|din|dihadi|दैनिक|daily wage)/.test(s)) return 'daily';
  if (/^(monthly|month|per ?month|mahina|mahine|मासिक|fixed)/.test(s)) return 'monthly';
  return null;
}

/** Apply mapping + owner fixes and validate each row. */
export function cleanRows(rows: Record<string, unknown>[], mapping: Mapping, fixes: { row: number; field: string; value: unknown }[], country: string, existingPhones: Set<string>): CleanRow[] {
  const fixMap = new Map(fixes.map((f) => [`${f.row}:${f.field}`, f.value]));
  const seen = new Map<string, number>();
  const out: CleanRow[] = rows.map((raw, index) => {
    const pick = (f: StaffField) => {
      if (fixMap.has(`${index}:${f}`)) return fixMap.get(`${index}:${f}`);
      const h = Object.keys(mapping).find((k) => mapping[k] === f);
      return h ? raw[h] : undefined;
    };
    const issues: RowIssue[] = [];
    const values: CleanRow['values'] = {};
    const name = String(pick('name') ?? '').trim().replace(/\s+/g, ' ');
    if (!name) issues.push({ field: 'name', message: 'Name is missing', severity: 'error' });
    values.name = name;
    const phoneRaw = pick('phone');
    const phone = normalizePhone(phoneRaw, country);
    if (!phone) issues.push({ field: 'phone', message: phoneRaw ? `"${phoneRaw}" is not a valid mobile number` : 'Phone is missing', severity: 'error' });
    values.phone = phone ?? String(phoneRaw ?? '');
    const rateRaw = pick('ratePaise');
    if (rateRaw !== undefined && String(rateRaw).trim() !== '') {
      const p = typeof rateRaw === 'number' && fixMap.has(`${index}:ratePaise`) ? rateRaw : parseAmountToPaise(rateRaw);
      if (p === null) issues.push({ field: 'ratePaise', message: `Could not read salary "${rateRaw}"`, severity: 'error' });
      values.ratePaise = p ?? 0;
    } else {
      values.ratePaise = 0;
      issues.push({ field: 'ratePaise', message: 'Salary is missing (can be added later)', severity: 'warning' });
    }
    const wt = normalizeWageType(pick('wageType'));
    values.wageType = wt ?? (values.ratePaise && values.ratePaise <= 150000 ? 'daily' : 'monthly');
    if (!wt && values.ratePaise && values.ratePaise <= 150000) issues.push({ field: 'wageType', message: 'Salary looks like a daily wage — check type', severity: 'warning' });
    const desig = pick('designation');
    if (desig) values.designation = String(desig).trim();
    const branch = pick('branch');
    if (branch) values.branch = String(branch).trim();
    const doj = pick('joiningDate');
    if (doj !== undefined && String(doj).trim() !== '') {
      const d = parseDateLoose(doj);
      if (!d) issues.push({ field: 'joiningDate', message: `Could not read date "${doj}" (use DD/MM/YYYY)`, severity: 'error' });
      else values.joiningDate = d;
    }
    for (const f of ['advanceBalancePaise', 'lastSalaryPaise'] as const) {
      const v = pick(f);
      if (v !== undefined && String(v).trim() !== '') {
        const p = parseAmountToPaise(v);
        if (p === null) issues.push({ field: f, message: `Could not read amount "${v}"`, severity: 'error' });
        else values[f] = p;
      }
    }
    for (const f of ['paidLeaveBalance', 'sickLeaveBalance'] as const) {
      const v = pick(f);
      if (v !== undefined && String(v).trim() !== '') {
        const n = Number(String(v).replace(/[^\d.]/g, ''));
        if (Number.isNaN(n)) issues.push({ field: f, message: `Could not read "${v}"`, severity: 'error' });
        else values[f] = n;
      }
    }
    if (phone) {
      if (seen.has(phone)) issues.push({ field: 'phone', message: `Same phone as row ${seen.get(phone)! + 1}`, severity: 'error' });
      else seen.set(phone, index);
      if (existingPhones.has(phone)) issues.push({ field: 'phone', message: 'Already in your staff list — will be skipped unless you choose to update existing', severity: 'warning' });
    }
    return { index, values, issues };
  });
  return out;
}

// ---- Attendance history grid ----
const CODE_MAP: Record<string, { status: string; leaveType?: string }> = {
  p: { status: 'present' },
  pr: { status: 'present' },
  present: { status: 'present' },
  '1': { status: 'present' },
  a: { status: 'absent' },
  ab: { status: 'absent' },
  absent: { status: 'absent' },
  '0': { status: 'absent' },
  hd: { status: 'half_day' },
  h_d: { status: 'half_day' },
  half: { status: 'half_day' },
  '0.5': { status: 'half_day' },
  l: { status: 'leave', leaveType: 'paid' },
  pl: { status: 'leave', leaveType: 'paid' },
  cl: { status: 'leave', leaveType: 'paid' },
  sl: { status: 'leave', leaveType: 'sick' },
  ul: { status: 'leave', leaveType: 'unpaid' },
  lwp: { status: 'leave', leaveType: 'unpaid' },
  wo: { status: 'week_off' },
  w: { status: 'week_off' },
  off: { status: 'week_off' },
  h: { status: 'holiday' },
  ph: { status: 'holiday' },
  प: { status: 'present' },
  अ: { status: 'absent' },
};

export function parseAttendanceCode(v: unknown) {
  const s = String(v ?? '').trim().toLowerCase().replace(/\s+/g, '').replace('/', '_');
  if (!s || s === '-') return null;
  return CODE_MAP[s] ?? undefined;
}

/** Map grid headers to dates of `month`: "1".."31", "01/10", "2026-10-01", Excel dates. */
export function dayColumns(headers: string[], month: string): Record<string, string> {
  const [y, m] = month.split('-').map(Number);
  const dim = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const out: Record<string, string> = {};
  for (const h of headers) {
    const t = h.trim();
    let day: number | null = null;
    if (/^\d{1,2}$/.test(t)) day = Number(t);
    else if (/^\d{1,2}[/\-.]\d{1,2}([/\-.]\d{2,4})?$/.test(t)) day = Number(t.split(/[/\-.]/)[0]);
    else {
      const d = parseDateLoose(t);
      if (d && d.startsWith(month)) day = Number(d.slice(8, 10));
    }
    if (day && day >= 1 && day <= dim) out[h] = `${month}-${String(day).padStart(2, '0')}`;
  }
  return out;
}
