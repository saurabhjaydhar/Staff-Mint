import { formatMoney } from '../../lib/money.js';

/**
 * Turns raw audit entries into one plain sentence for a shop owner, in English or Hindi,
 * plus a short "what changed" list. The raw before/after stay in the API for exports.
 */

type Lang = 'en' | 'hi';
export type HistoryCategory = 'attendance' | 'leave' | 'salary' | 'staff' | 'settings' | 'team' | 'billing' | 'other';
export interface HistoryChange {
  label: string;
  from?: string | null;
  to?: string | null;
}
export interface HistoryText {
  text: string;
  category: HistoryCategory;
  changes: HistoryChange[];
}
/** What the describer needs to know besides the entry itself. */
export interface HistoryLookup {
  employeeName(id: unknown): string | null;
}

const MONTHS = {
  en: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
  hi: ['जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर'],
};
const MONTHS_LONG_EN = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/** `2026-10-12` → `12 Oct` / `12 अक्टूबर`. */
export function dayText(d: unknown, lang: Lang): string {
  const m = typeof d === 'string' ? d.match(/^(\d{4})-(\d{2})-(\d{2})/) : null;
  if (!m) return '';
  return `${Number(m[3])} ${MONTHS[lang][Number(m[2]) - 1]}`;
}
/** `2026-10` → `October 2026` / `अक्टूबर 2026`. */
export function monthText(mo: unknown, lang: Lang): string {
  const m = typeof mo === 'string' ? mo.match(/^(\d{4})-(\d{2})/) : null;
  if (!m) return '';
  return `${lang === 'hi' ? MONTHS.hi[Number(m[2]) - 1] : MONTHS_LONG_EN[Number(m[2]) - 1]} ${m[1]}`;
}
const range = (from: unknown, to: unknown, lang: Lang) =>
  !to || from === to ? dayText(from, lang) : `${dayText(from, lang)} – ${dayText(to, lang)}`;
const money = (p: unknown) => (typeof p === 'number' ? formatMoney(Math.abs(p)) : '');
const hhmm = (t: unknown) => {
  const m = typeof t === 'string' ? t.match(/^(\d{2}):(\d{2})$/) : null;
  if (!m) return String(t ?? '');
  const h = Number(m[1]);
  return `${h % 12 || 12}:${m[2]} ${h < 12 ? 'AM' : 'PM'}`;
};

const STATUS: Record<string, [string, string]> = {
  present: ['Present', 'हाज़िर'],
  absent: ['Absent', 'ग़ैरहाज़िर'],
  half_day: ['Half day', 'आधा दिन'],
  late: ['Late', 'लेट'],
  leave: ['On leave', 'छुट्टी'],
  holiday: ['Holiday', 'त्योहार की छुट्टी'],
  week_off: ['Weekly off', 'साप्ताहिक छुट्टी'],
  checked_in: ['At work', 'काम पर'],
};
const LEAVE_TYPE: Record<string, [string, string]> = {
  paid: ['paid leave', 'पेड छुट्टी'],
  sick: ['sick leave', 'बीमारी की छुट्टी'],
  unpaid: ['unpaid leave', 'बिना पैसे की छुट्टी'],
};
const METHOD: Record<string, [string, string]> = {
  cash: ['cash', 'नकद'],
  upi: ['UPI', 'UPI'],
  bank: ['bank transfer', 'बैंक ट्रांसफ़र'],
  mixed: ['mixed', 'मिला-जुला'],
};
/** Shop rule names for "Shop rules changed". */
const SETTING: Record<string, [string, string]> = {
  graceMinutes: ['Late after (minutes)', 'कितने मिनट बाद लेट'],
  halfDayHours: ['Half day under (hours)', 'इतने घंटे से कम = आधा दिन'],
  monthDivisor: ['Salary per day: divide by', 'एक दिन की सैलरी: इससे भाग दें'],
  missingCheckoutPolicy: ['Forgot to check out', 'चेक-आउट भूल जाएँ तो'],
  weekOffsPaid: ['Weekly offs are paid', 'साप्ताहिक छुट्टी के पैसे'],
  holidaysPaid: ['Holidays are paid', 'त्योहार की छुट्टी के पैसे'],
  sickLeavePaid: ['Sick leave is paid', 'बीमारी की छुट्टी के पैसे'],
  outsideGeofencePolicy: ['Check-in away from shop', 'दुकान से दूर चेक-इन'],
  phoneLockPolicy: ['Phone lock at check-in', 'चेक-इन पर फ़ोन लॉक'],
  faceMatchPolicy: ['Face check', 'चेहरा पहचान'],
  selfieRequired: ['Selfie at check-in', 'चेक-इन पर सेल्फ़ी'],
  attendanceMarking: ['Who marks attendance', 'हाज़िरी कौन लगाएगा'],
  presentByDefault: ['Present by default', 'अपने-आप हाज़िर'],
  roundToRupee: ['Round salary to rupee', 'सैलरी पूरे रुपये में'],
  whatsappAlerts: ['Alerts on WhatsApp', 'WhatsApp पर अलर्ट'],
  exStaffPayslips: ['Old staff can see old slips', 'पुराने स्टाफ़ पुरानी स्लिप देख सकें'],
  digestTime: ['Morning summary time', 'सुबह की रिपोर्ट का समय'],
  language: ['Language', 'भाषा'],
};
const VALUE: Record<string, [string, string]> = {
  half_day: ['half day', 'आधा दिन'],
  present: ['present', 'हाज़िर'],
  flag: ['present, marked to check', 'हाज़िर, देखने के लिए निशान'],
  block: ['not allowed', 'नहीं होगा'],
  approve: ['needs your OK', 'आपकी मंज़ूरी से'],
  allow: ['allowed', 'होगा'],
  off: ['off', 'बंद'],
  recommended: ['asked, not required', 'पूछा जाएगा, ज़रूरी नहीं'],
  required: ['required', 'ज़रूरी'],
  review: ['on', 'चालू'],
  self: ['staff check in themselves', 'स्टाफ़ ख़ुद चेक-इन करेगा'],
  owner: ['owner or manager marks', 'मालिक या मैनेजर लगाएगा'],
  days_in_month: ['days in that month', 'उस महीने के दिन'],
  en: ['English', 'English'],
  hi: ['Hindi', 'हिन्दी'],
};
const EMPLOYEE_FIELD: Record<string, [string, string]> = {
  name: ['Name', 'नाम'],
  phone: ['Phone', 'फ़ोन'],
  designation: ['Job', 'काम'],
  ratePaise: ['Salary', 'सैलरी'],
  wageType: ['Paid', 'सैलरी कैसे'],
  joiningDate: ['Joining date', 'जुड़ने की तारीख़'],
  shiftId: ['Shift', 'शिफ़्ट'],
  branchId: ['Branch', 'ब्रांच'],
  attendanceMarking: ['Who marks attendance', 'हाज़िरी कौन लगाएगा'],
};

function pick(pair: [string, string] | undefined, lang: Lang, fallback = ''): string {
  return pair ? pair[lang === 'hi' ? 1 : 0] : fallback;
}
function valueText(v: unknown, lang: Lang): string {
  if (v === true) return lang === 'hi' ? 'चालू' : 'On';
  if (v === false) return lang === 'hi' ? 'बंद' : 'Off';
  if (v === null || v === undefined || v === '') return '—';
  if (typeof v === 'string' && VALUE[v]) return pick(VALUE[v], lang);
  return String(v);
}

/** Field-by-field differences for the keys we know how to name. */
function diff(
  before: any,
  after: any,
  labels: Record<string, [string, string]>,
  lang: Lang,
  fmt: (k: string, v: unknown) => string = (_k, v) => valueText(v, lang),
): HistoryChange[] {
  const out: HistoryChange[] = [];
  for (const k of Object.keys(labels)) {
    const a = before?.[k];
    const b = after?.[k];
    if (b === undefined || JSON.stringify(a) === JSON.stringify(b)) continue;
    out.push({ label: pick(labels[k], lang), from: a === undefined ? null : fmt(k, a), to: fmt(k, b) });
  }
  return out;
}

const DOC_KIND: Record<string, [string, string]> = { aadhaar: ['Aadhaar', 'आधार'], pan: ['PAN', 'PAN'], bank: ['bank account', 'बैंक खाता'] };
const FILE_KIND: Record<string, [string, string]> = {
  aadhaar: ['Aadhaar', 'आधार'],
  pan: ['PAN', 'PAN'],
  dl: ['driving licence', 'ड्राइविंग लाइसेंस'],
  voter: ['voter ID', 'वोटर आईडी'],
  passport: ['passport', 'पासपोर्ट'],
  bank_proof: ['bank passbook', 'बैंक पासबुक'],
  address: ['address proof', 'पते का सबूत'],
  police: ['police verification', 'पुलिस वेरिफ़िकेशन'],
  experience: ['experience letter', 'अनुभव पत्र'],
  other: ['a document', 'एक दस्तावेज़'],
};
const DOC_RESULT: Record<string, [string, string]> = {
  verified: ['verified', 'सही निकला'],
  mismatch: ['name doesn’t match', 'नाम नहीं मिला'],
  not_found: ['not found', 'नहीं मिला'],
  failed: ['couldn’t be checked', 'जाँच नहीं हो पाई'],
};

export function describe(
  log: { action: string; entity: string; entityId?: unknown; before?: any; after?: any },
  lang: Lang,
  look: HistoryLookup,
): HistoryText | null {
  const hi = lang === 'hi';
  const t = (en: string, h: string) => (hi ? h : en);
  const a = log.after ?? {};
  const b = log.before ?? {};
  const empId = a.employeeId ?? b.employeeId ?? (log.entity === 'employee' ? log.entityId : null);
  const emp = look.employeeName(empId) ?? a.name ?? b.name ?? t('A staff member', 'एक स्टाफ़');
  const note = (label: [string, string], v: unknown): HistoryChange[] =>
    typeof v === 'string' && v.trim() ? [{ label: pick(label, lang), to: v.trim() }] : [];
  const reasonLabel: [string, string] = ['Reason', 'कारण'];
  const r = (text: string, category: HistoryCategory, changes: HistoryChange[] = []): HistoryText => ({ text, category, changes });

  switch (log.action) {
    // ---------------------------------------------------------------- attendance
    case 'attendance.override': {
      const st = pick(STATUS[a.status], lang, a.status);
      return r(t(`${emp}: ${dayText(a.date, lang)} set to ${st}`, `${emp}: ${dayText(a.date, lang)} को ${st} किया`), 'attendance', [
        ...(b.status && b.status !== a.status
          ? [{ label: t('Status', 'हाज़िरी'), from: pick(STATUS[b.status], lang, b.status), to: st }]
          : []),
        ...note(reasonLabel, a.overrideReason ?? a.reason),
      ]);
    }
    case 'attendance.override.clear':
      return r(t(`${emp}: change on ${dayText(a.date, lang)} undone`, `${emp}: ${dayText(a.date, lang)} का बदलाव हटाया`), 'attendance', note(reasonLabel, a.reason));
    case 'attendance.punch.approve':
      return r(t(`${emp}: check-in on ${dayText(a.date, lang)} counted`, `${emp}: ${dayText(a.date, lang)} का चेक-इन माना`), 'attendance');
    case 'attendance.punch.reject':
      return r(t(`${emp}: check-in on ${dayText(a.date, lang)} not counted`, `${emp}: ${dayText(a.date, lang)} का चेक-इन नहीं माना`), 'attendance');
    case 'attendance.fix_request':
      return r(t(`${emp} asked to fix ${dayText(a.date, lang)}`, `${emp} ने ${dayText(a.date, lang)} ठीक करने को कहा`), 'attendance', note(['Note', 'बात'], a.note));

    // --------------------------------------------------------------------- leave
    case 'leave.apply':
      return r(t(`${emp} asked for leave: ${range(a.from, a.to, lang)}`, `${emp} ने छुट्टी माँगी: ${range(a.from, a.to, lang)}`), 'leave', [
        { label: t('Type', 'छुट्टी'), to: pick(LEAVE_TYPE[a.type], lang, a.type) },
        ...note(reasonLabel, a.reason),
      ]);
    case 'leave.approved':
      return r(
        t(`${emp}: leave approved, ${range(a.from, a.to, lang)}`, `${emp}: छुट्टी मंज़ूर, ${range(a.from, a.to, lang)}`),
        'leave',
        [
          ...(b.type && b.type !== a.type
            ? [{ label: t('Type', 'छुट्टी'), from: pick(LEAVE_TYPE[b.type], lang), to: pick(LEAVE_TYPE[a.type], lang) }]
            : [{ label: t('Type', 'छुट्टी'), to: pick(LEAVE_TYPE[a.type], lang, a.type) }]),
          ...note(['Note', 'बात'], a.note),
        ],
      );
    case 'leave.rejected':
      return r(t(`${emp}: leave refused, ${range(a.from, a.to, lang)}`, `${emp}: छुट्टी नामंज़ूर, ${range(a.from, a.to, lang)}`), 'leave', note(['Note', 'बात'], a.note));
    case 'leave.cancel':
      return r(t(`${emp}: leave cancelled, ${range(a.from, a.to, lang)}`, `${emp}: छुट्टी रद्द, ${range(a.from, a.to, lang)}`), 'leave');
    case 'leave_balance.set':
      return r(
        t(`${emp}: leaves for ${a.year ?? ''} set to ${a.paid ?? 0} paid, ${a.sick ?? 0} sick`, `${emp}: ${a.year ?? ''} की छुट्टियाँ ${a.paid ?? 0} पेड, ${a.sick ?? 0} बीमारी`),
        'leave',
      );

    // -------------------------------------------------------------------- salary
    case 'advance.create':
      return r(t(`${emp}: advance of ${money(a.amountPaise)} given`, `${emp} को ${money(a.amountPaise)} एडवांस दिया`), 'salary', note(['Note', 'बात'], a.note));
    case 'advance.skip':
      return r(t(`${emp}: advance cut skipped this month`, `${emp}: इस महीने एडवांस नहीं कटेगा`), 'salary');
    case 'adjustment.bonus':
      return r(t(`${emp}: bonus of ${money(a.amountPaise)}`, `${emp}: ${money(a.amountPaise)} बोनस`), 'salary', note(reasonLabel, a.reason ?? a.note));
    case 'adjustment.deduction':
      return r(t(`${emp}: cut of ${money(a.amountPaise)}`, `${emp}: ${money(a.amountPaise)} कटौती`), 'salary', note(reasonLabel, a.reason ?? a.note));
    case 'adjustment.delete':
      return r(
        t(`${emp}: ${b.type === 'bonus' ? 'bonus' : 'cut'} of ${money(b.amountPaise)} removed`, `${emp}: ${money(b.amountPaise)} ${b.type === 'bonus' ? 'बोनस' : 'कटौती'} हटाई`),
        'salary',
      );
    case 'payroll.draft':
    case 'payroll.recompute':
      return r(
        t(`Salary worked out${a.month ? ` for ${monthText(a.month, lang)}` : ''}`, `${a.month ? `${monthText(a.month, lang)} की ` : ''}सैलरी का हिसाब बना`),
        'salary',
        typeof a.totals?.netPaise === 'number' ? [{ label: t('Total to pay', 'कुल देना है'), to: money(a.totals.netPaise) }] : [],
      );
    case 'payroll.approve':
      return r(
        t(`Salary for ${monthText(a.month, lang)} approved`, `${monthText(a.month, lang)} की सैलरी मंज़ूर`),
        'salary',
        typeof a.totals?.netPaise === 'number' ? [{ label: t('Total to pay', 'कुल देना है'), to: money(a.totals.netPaise) }] : [],
      );
    case 'payroll.paid':
      return r(
        t(`Salary for ${monthText(a.month, lang)} marked paid`, `${monthText(a.month, lang)} की सैलरी दे दी`),
        'salary',
        [
          ...(a.method ? [{ label: t('Paid by', 'कैसे दी'), to: pick(METHOD[a.method], lang, a.method) }] : []),
          ...(a.paidOn ? [{ label: t('Paid on', 'किस दिन'), to: dayText(a.paidOn, lang) }] : []),
        ],
      );
    case 'payroll.revise':
      return r(t(`Salary for ${monthText(a.month, lang)} opened to change`, `${monthText(a.month, lang)} की सैलरी बदलने के लिए खोली`), 'salary');
    case 'payslips.send':
      return r(t(`Salary slips sent to ${a.sent ?? 0} staff`, `${a.sent ?? 0} स्टाफ़ को सैलरी स्लिप भेजी`), 'salary');

    // --------------------------------------------------------------------- staff
    case 'employee.create':
      return r(t(`${emp} added`, `${emp} जोड़े गए`), 'staff', [
        ...(typeof a.ratePaise === 'number' && a.ratePaise > 0
          ? [{ label: t('Salary', 'सैलरी'), to: `${money(a.ratePaise)}${a.wageType === 'daily' ? t(' / day', ' / दिन') : t(' / month', ' / महीना')}` }]
          : []),
        ...note(['Job', 'काम'], a.designation),
      ]);
    case 'employee.update': {
      const changes = diff(b, a, EMPLOYEE_FIELD, lang, (k, v) =>
        k === 'ratePaise'
          ? money(v)
          : k === 'wageType'
            ? v === 'daily'
              ? t('Every day', 'हर दिन')
              : t('Every month', 'हर महीने')
            : k === 'joiningDate'
              ? dayText(v, lang)
              : k === 'shiftId' || k === 'branchId'
                ? t('changed', 'बदली')
                : valueText(v, lang),
      );
      return r(t(`${emp}: details changed`, `${emp}: जानकारी बदली`), 'staff', changes);
    }
    case 'employee.deactivate':
      return r(t(`${emp} marked as left`, `${emp} ने काम छोड़ा`), 'staff', note(reasonLabel, a.reason));
    case 'employee.reactivate':
      return r(t(`${emp} is back at work`, `${emp} फिर से काम पर`), 'staff');
    case 'employee.reset_device':
      return r(t(`${emp}: phone reset, can log in on a new phone`, `${emp}: फ़ोन रीसेट, नए फ़ोन पर लॉगिन कर सकते हैं`), 'staff');
    case 'employee.role':
      return r(
        a.appRole === 'manager' ? t(`${emp} made a manager`, `${emp} मैनेजर बनाए गए`) : t(`${emp} is staff again`, `${emp} फिर से स्टाफ़`),
        'team',
      );
    case 'employee.invite':
      return r(t(`App invite sent to ${emp}`, `${emp} को ऐप का बुलावा भेजा`), 'staff');
    case 'employee.invite_all':
      return r(t(`App invite sent to ${a.sent ?? 0} staff`, `${a.sent ?? 0} स्टाफ़ को ऐप का बुलावा भेजा`), 'staff');
    case 'employee.login.attach':
      return r(t(`${emp} joined the app`, `${emp} ऐप से जुड़े`), 'staff');
    case 'employee.consent':
      return r(t(`${emp} agreed to location and selfie at check-in`, `${emp} ने चेक-इन पर लोकेशन और सेल्फ़ी की सहमति दी`), 'staff');
    case 'employee.face.enroll':
      return r(t(`${emp} added a face photo`, `${emp} ने चेहरे की फ़ोटो लगाई`), 'staff');
    case 'employee.face.approve':
      return r(t(`${emp}: face photo approved`, `${emp}: चेहरे की फ़ोटो मंज़ूर`), 'staff');
    case 'employee.face.reset':
      return r(t(`${emp}: face photo removed, new one asked for`, `${emp}: चेहरे की फ़ोटो हटाई, नई माँगी`), 'staff');
    case 'employee.face.withdraw':
      return r(t(`${emp} removed their face photo`, `${emp} ने चेहरे की फ़ोटो हटाई`), 'staff');
    case 'employee.statutory.update':
      return r(t(`${emp}: salary slip details changed`, `${emp}: सैलरी स्लिप की जानकारी बदली`), 'staff');
    case 'employee.bank.update':
      return r(t(`${emp}: salary account saved`, `${emp}: सैलरी खाता सेव हुआ`), 'staff');
    case 'verification.request':
      return r(t(`${emp}: asked to verify documents`, `${emp}: दस्तावेज़ जाँचने को कहा`), 'staff');
    case 'verification.cancel':
      return r(t(`${emp}: document check cancelled`, `${emp}: दस्तावेज़ जाँच रद्द की`), 'staff');
    case 'verification.consent':
      return r(t(`${emp} agreed to the document check`, `${emp} ने दस्तावेज़ जाँच की अनुमति दी`), 'staff');
    case 'verification.check': {
      const kind = pick(DOC_KIND[a.kind] ?? [a.kind, a.kind], lang);
      const result = pick(DOC_RESULT[a.status] ?? [a.status, a.status], lang);
      return r(t(`${emp}: ${kind} ${result}`, `${emp}: ${kind} ${result}`), 'staff');
    }
    case 'verification.accept':
      return r(
        t(`${emp}: ${pick(DOC_KIND[a.kind] ?? [a.kind, a.kind], lang)} name accepted`, `${emp}: ${pick(DOC_KIND[a.kind] ?? [a.kind, a.kind], lang)} का नाम मान लिया`),
        'staff',
        [...note(reasonLabel, a.reason), ...(a.nameOnRecord ? [{ label: t('Name on record', 'रिकॉर्ड में नाम'), to: String(a.nameOnRecord) }] : [])],
      );
    case 'verification.ask_again':
      return r(t(`${emp}: asked to check ${pick(DOC_KIND[a.kind] ?? [a.kind, a.kind], lang)} again`, `${emp}: ${pick(DOC_KIND[a.kind] ?? [a.kind, a.kind], lang)} फिर से जाँचने को कहा`), 'staff');
    case 'document.add':
    case 'document.view':
    case 'document.update':
    case 'document.delete': {
      const d = { ...b, ...a };
      const what = d.kind === 'other' && d.label ? String(d.label) : pick(FILE_KIND[d.kind] ?? [String(d.kind), String(d.kind)], lang);
      if (log.action === 'document.view') return r(t(`${emp}: ${what} opened`, `${emp}: ${what} खोला`), 'staff');
      if (log.action === 'document.delete') return r(t(`${emp}: ${what} removed`, `${emp}: ${what} हटाया`), 'staff');
      if (log.action === 'document.update') {
        return r(t(`${emp}: ${what} updated`, `${emp}: ${what} बदला`), 'staff', diff(b, a, { expiresOn: ['Valid till', 'कब तक मान्य'] }, lang));
      }
      const changes = a.by === 'owner_on_behalf' ? [{ label: t('Consent', 'सहमति'), to: a.slip ? t('Signed slip added', 'साइन की हुई पर्ची लगाई') : t('Agreed earlier', 'पहले से सहमति') }] : [];
      return r(t(`${emp}: ${what} added`, `${emp}: ${what} जोड़ा`), 'staff', changes);
    }
    case 'employee.bank.remove':
      return r(t(`${emp}: salary account removed`, `${emp}: सैलरी खाता हटाया`), 'staff');
    case 'employee.phone_recycled':
      return r(t(`${emp}: their number now belongs to someone else`, `${emp}: उनका नंबर अब किसी और का है`), 'staff');
    case 'device.request':
      return r(t(`${emp} asked to use a new phone`, `${emp} ने नए फ़ोन के लिए कहा`), 'staff', note(['Phone', 'फ़ोन'], a.deviceName));
    case 'device.approve':
      return r(t(`${emp}: new phone allowed`, `${emp}: नया फ़ोन मंज़ूर`), 'staff', note(['Phone', 'फ़ोन'], a.deviceName));
    case 'device.reject':
      return r(t(`${emp}: new phone not allowed`, `${emp}: नया फ़ोन नामंज़ूर`), 'staff', note(['Phone', 'फ़ोन'], a.deviceName));

    // ------------------------------------------------------------------ settings
    case 'company.create':
      return r(t('Business created', 'बिज़नेस बनाया'), 'settings', note(['Name', 'नाम'], a.name));
    case 'company.update':
      return r(t('Business details changed', 'बिज़नेस की जानकारी बदली'), 'settings', diff(b, a, { name: ['Name', 'नाम'], businessType: ['Type', 'प्रकार'] }, lang));
    case 'company.settings.update':
      return r(t('Shop rules changed', 'दुकान के नियम बदले'), 'settings', diff(b.settings, a.settings, SETTING, lang));
    case 'company.statutory.update':
      return r(t('PF / ESI settings changed', 'PF / ESI की सेटिंग बदली'), 'settings');
    case 'company.close':
      return r(t('Business closed', 'बिज़नेस बंद किया'), 'settings');
    case 'company.restore':
      return r(t('Business opened again', 'बिज़नेस फिर से खोला'), 'settings');
    case 'company.export':
      return r(t('All data downloaded', 'सारा डेटा डाउनलोड किया'), 'other');
    case 'branch.create':
      return r(t(`Branch added: ${a.name ?? ''}`, `ब्रांच जोड़ी: ${a.name ?? ''}`), 'settings', a.radiusM ? [{ label: t('Check-in area', 'चेक-इन का घेरा'), to: `${a.radiusM} m` }] : []);
    case 'branch.update':
      return r(t(`Branch changed: ${a.name ?? b.name ?? ''}`, `ब्रांच बदली: ${a.name ?? b.name ?? ''}`), 'settings', [
        ...diff(b, a, { name: ['Name', 'नाम'] }, lang),
        ...(a.radiusM !== b.radiusM && a.radiusM ? [{ label: t('Check-in area', 'चेक-इन का घेरा'), from: b.radiusM ? `${b.radiusM} m` : null, to: `${a.radiusM} m` }] : []),
        ...(JSON.stringify(a.location) !== JSON.stringify(b.location) && a.location ? [{ label: t('Shop location', 'दुकान की लोकेशन'), to: a.location.address || t('moved', 'बदली') }] : []),
      ]);
    case 'shift.create':
      return r(t(`Shift added: ${a.name ?? ''}`, `शिफ़्ट जोड़ी: ${a.name ?? ''}`), 'settings', [{ label: t('Time', 'समय'), to: `${hhmm(a.start)} – ${hhmm(a.end)}` }]);
    case 'shift.update':
      return r(t(`Shift changed: ${a.name ?? b.name ?? ''}`, `शिफ़्ट बदली: ${a.name ?? b.name ?? ''}`), 'settings', [
        ...(a.start !== b.start || a.end !== b.end ? [{ label: t('Time', 'समय'), from: b.start ? `${hhmm(b.start)} – ${hhmm(b.end)}` : null, to: `${hhmm(a.start)} – ${hhmm(a.end)}` }] : []),
        ...diff(b, a, { name: ['Name', 'नाम'], graceMinutes: SETTING.graceMinutes }, lang),
      ]);
    case 'holiday.create':
      return r(t(`Holiday added: ${a.name ?? ''}, ${dayText(a.date, lang)}`, `छुट्टी जोड़ी: ${a.name ?? ''}, ${dayText(a.date, lang)}`), 'settings');
    case 'holiday.delete':
      return r(t(`Holiday removed: ${b.name ?? ''}, ${dayText(b.date, lang)}`, `छुट्टी हटाई: ${b.name ?? ''}, ${dayText(b.date, lang)}`), 'settings');

    // ---------------------------------------------------------------------- team
    case 'user.ca.add':
      return r(t(`CA added: ${a.name ?? ''}`, `CA जोड़े: ${a.name ?? ''}`), 'team');
    case 'user.ca.remove':
      return r(t('CA removed', 'CA हटाए'), 'team');
    case 'owner.add':
      return r(t('Co-owner added', 'पार्टनर जोड़े'), 'team');
    case 'owner.remove':
      return r(t('Co-owner removed', 'पार्टनर हटाए'), 'team');
    case 'owner.billing':
      return r(a.canManageBilling ? t('Co-owner can now handle payments', 'पार्टनर अब पेमेंट देख सकते हैं') : t('Co-owner can no longer handle payments', 'पार्टनर अब पेमेंट नहीं देख सकते'), 'team');
    case 'owner.transfer.start':
      return r(t('Handing over the business started', 'बिज़नेस सौंपना शुरू किया'), 'team');
    case 'owner.transfer.cancel':
      return r(t('Handing over the business stopped', 'बिज़नेस सौंपना रोका'), 'team');
    case 'owner.transfer.decline':
      return r(t('Handover of the business declined', 'बिज़नेस लेने से मना किया'), 'team');
    case 'owner.transfer.accept':
      return r(t('Business handed over to a new owner', 'बिज़नेस नए मालिक को सौंपा'), 'team');
    case 'owner.recovery.start':
      return r(t('Account recovery started', 'अकाउंट वापस पाने की प्रक्रिया शुरू'), 'team');
    case 'owner.recovery.accept':
      return r(t('Account recovered on a new number', 'नए नंबर पर अकाउंट वापस मिला'), 'team');
    case 'account.leave':
      return r(t('Left this business', 'यह बिज़नेस छोड़ा'), 'team');
    case 'account.number_moved':
      return r(t('Login number changed', 'लॉगिन नंबर बदला'), 'team');
    case 'account.recovery.hold':
      return r(t('Account recovery is waiting', 'अकाउंट वापस पाना रुका है'), 'team');

    // ------------------------------------------------------------------- profile
    case 'profile.update':
      return r(t('Profile details changed', 'प्रोफ़ाइल की जानकारी बदली'), 'other', diff(b, a, { name: ['Name', 'नाम'], email: ['Email', 'ईमेल'], language: ['Language', 'भाषा'] }, lang));
    case 'profile.photo':
      return r(t('Profile photo changed', 'प्रोफ़ाइल फ़ोटो बदली'), 'other');
    case 'profile.photo.remove':
      return r(t('Profile photo removed', 'प्रोफ़ाइल फ़ोटो हटाई'), 'other');
    case 'profile.phone':
      return r(t('Mobile number changed', 'मोबाइल नंबर बदला'), 'other');
    case 'profile.logout_all':
      return r(t('Logged out on all phones', 'सभी फ़ोन से लॉग आउट किया'), 'other');

    // ------------------------------------------------------------------- roster
    case 'roster.send':
      return r(
        t(`Roster sent to ${Number(a.staff ?? 0)} staff`, `${Number(a.staff ?? 0)} स्टाफ़ को रोस्टर भेजा`),
        'attendance',
        [{ label: t('Days changed', 'बदले दिन'), to: String(a.days ?? 0) }],
      );
    case 'roster.repeat_on':
      return r(
        a.mode === 'rotate'
          ? t(`Roster set to swap shifts every week (${Number(a.staff ?? 0)} staff)`, `रोस्टर हर हफ़्ते शिफ़्ट बदलेगा (${Number(a.staff ?? 0)} स्टाफ़)`)
          : t(`Roster set to repeat every week (${Number(a.staff ?? 0)} staff)`, `रोस्टर हर हफ़्ते दोहराया जाएगा (${Number(a.staff ?? 0)} स्टाफ़)`),
        'attendance',
        a.autoSend ? [{ label: t('Sent to staff', 'स्टाफ़ को भेजना'), to: t('On its own', 'अपने-आप') }] : [],
      );
    case 'roster.swap_approved':
    case 'roster.swap_rejected':
      return r(
        log.action === 'roster.swap_approved'
          ? t(`Swap approved: ${a.from} and ${a.to} on ${a.date}`, `अदला-बदली मंज़ूर: ${a.from} और ${a.to}, ${a.date}`)
          : t(`Swap not approved: ${a.from} and ${a.to} on ${a.date}`, `अदला-बदली नामंज़ूर: ${a.from} और ${a.to}, ${a.date}`),
        'attendance',
        [],
      );
    case 'roster.repeat_off':
      return r(t('Roster repeat turned off', 'रोस्टर दोहराना बंद किया'), 'attendance', []);

    // ------------------------------------------------------------------- billing
    case 'billing.subscribe':
      return r(t(`Plan bought: ${String(a.planCode ?? '')}`, `प्लान लिया: ${String(a.planCode ?? '')}`), 'billing', typeof a.amountPaise === 'number' ? [{ label: t('Amount', 'रकम'), to: money(a.amountPaise) }] : []);
    case 'billing.cancel':
      return r(t('Plan cancelled', 'प्लान रद्द किया'), 'billing');
    case 'billing.group.add':
      return r(t('Payments moved to the main business', 'पेमेंट मुख्य बिज़नेस से होगा'), 'billing');
    case 'billing.group.remove':
      return r(t('Payments separated from the main business', 'पेमेंट मुख्य बिज़नेस से अलग हुआ'), 'billing');

    // ------------------------------------------------------------- import / misc
    case 'admin.login':
      return null; // StaffMint support only; not shown to the owner.
  }
  if (log.action.startsWith('billing.')) return r(t('Plan or payment updated', 'प्लान या पेमेंट अपडेट हुआ'), 'billing');
  if (log.action.startsWith('import.') && log.action.endsWith('.commit')) return r(t('Data added from a file', 'फ़ाइल से डेटा जोड़ा'), 'other', importSummary(a, lang));
  if (log.action.startsWith('import.') && log.action.endsWith('.rollback')) return r(t('File import undone', 'फ़ाइल से जोड़ा डेटा वापस लिया'), 'other');
  // Anything new we don't have words for yet: still readable, never raw codes.
  return r(t('A change was made', 'एक बदलाव किया गया'), 'other');
}

function importSummary(a: any, lang: Lang): HistoryChange[] {
  const out: HistoryChange[] = [];
  const add = (v: unknown, en: string, hi: string) => {
    if (typeof v === 'number' && v > 0) out.push({ label: lang === 'hi' ? hi : en, to: String(v) });
  };
  add(a?.created ?? a?.added, 'Added', 'जोड़े');
  add(a?.updated, 'Updated', 'बदले');
  add(a?.skipped, 'Skipped', 'छोड़े');
  return out;
}

/** Category of an action without building the sentence (used to filter in the database). */
export const CATEGORY_ACTIONS: Record<Exclude<HistoryCategory, 'other'>, RegExp> = {
  attendance: /^(attendance|roster)\./,
  leave: /^leave(_balance)?\./,
  salary: /^(advance|adjustment|payroll|payslips)\./,
  staff: /^(employee|device|verification|document)\.(?!role$)/,
  settings: /^(company\.(create|update|settings\.update|statutory\.update|close|restore)|branch\.|shift\.|holiday\.)/,
  team: /^(employee\.role$|user\.ca\.|owner\.|account\.)/,
  billing: /^billing\./,
};
