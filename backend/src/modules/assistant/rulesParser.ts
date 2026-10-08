/**
 * Deterministic Hinglish / English command parser for Mint (PRD F5, §10).
 * Extracts intent + entities only — never executes anything. Used as the zero-cost
 * fast path before the LLM, as offline fallback, and in tests.
 */
import { DateTime } from 'luxon';
import { parseAmountToPaise } from '../../lib/money.js';

export interface ParseResult {
  intent: string | null;
  args: Record<string, unknown>;
  confidence: number;
}

export interface ParseContext {
  today: string;
  employeeNames: string[];
  role: string;
}

const MONTHS: Record<string, number> = {
  jan: 1, january: 1, janvari: 1, जनवरी: 1,
  feb: 2, february: 2, farvari: 2, फरवरी: 2,
  mar: 3, march: 3, maarch: 3, मार्च: 3,
  apr: 4, april: 4, aprail: 4, अप्रैल: 4,
  may: 5, मई: 5,
  jun: 6, june: 6, joon: 6, जून: 6,
  jul: 7, july: 7, julai: 7, जुलाई: 7,
  aug: 8, august: 8, agast: 8, अगस्त: 8,
  sep: 9, sept: 9, september: 9, सितंबर: 9,
  oct: 10, october: 10, aktubar: 10, अक्टूबर: 10,
  nov: 11, november: 11, navambar: 11, नवंबर: 11,
  dec: 12, december: 12, disambar: 12, दिसंबर: 12,
};

const STOP = new Set(
  'ko ka ki ke ne se me mein par aaj kal parso laga lagao lagado lag do de dena karo kardo kar diya diye hai hain tha thi the mark please pls plz aur ji bhai sir sab sabki sabko sabhi uska uski iska iski usko isko half full day din aadha present absent nahi nahin aaya aayi aaye leave chutti chhutti advance udhaar udhar bonus diya diye rupaye rupees rs salary payslip ka ek is us yeh ye wo woh tha today yesterday tomorrow ho gaya gayi gaye gya hua bhi toh to na naya nayi new staff employee banda bandi add hajir haazir hazir mat and the a an for of on in at was is give gave paid de diya kaat kato katoti deduction fine penalty jurmana incentive inaam installment installments kisht mahine mahina month months me mujhe meri mera'.split(
    ' ',
  ),
);

const clean = (s: string) =>
  s
    .toLowerCase()
    .replace(/[₹]/g, ' rs ')
    .replace(/[?!,;:"“”'’]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

const has = (t: string, ...words: (string | RegExp)[]) => words.some((w) => (typeof w === 'string' ? new RegExp(`(^|\\s)${w}(\\s|$)`).test(t) : w.test(t)));

function resolveDate(t: string, today: string, futureBias: boolean): string | null {
  const d = DateTime.fromISO(today);
  if (has(t, 'aaj', 'today', 'abhi', 'आज')) return today;
  if (has(t, 'parso')) return d.plus({ days: futureBias ? 2 : -2 }).toISODate();
  if (has(t, 'yesterday', 'kal raat')) return d.minus({ days: 1 }).toISODate();
  if (has(t, 'tomorrow')) return d.plus({ days: 1 }).toISODate();
  if (has(t, 'kal', 'कल')) return d.plus({ days: futureBias ? 1 : -1 }).toISODate();
  // "15 oct", "15 october", "oct 15"
  let m = t.match(/(\d{1,2})(?:st|nd|rd|th)?\s+([a-zऀ-ॿ]+)/);
  if (m && MONTHS[m[2]]) return safeDate(d.year, MONTHS[m[2]], Number(m[1]), today, futureBias);
  m = t.match(/([a-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?(\s|$)/);
  if (m && MONTHS[m[1]]) return safeDate(d.year, MONTHS[m[1]], Number(m[2]), today, futureBias);
  // dd/mm or dd-mm(-yyyy)
  m = t.match(/(^|\s)(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?(\s|$)/);
  if (m) {
    const y = m[4] ? (m[4].length === 2 ? 2000 + Number(m[4]) : Number(m[4])) : d.year;
    return safeDate(y, Number(m[3]), Number(m[2]), today, futureBias, !!m[4]);
  }
  // "15 tarikh" / "15th"
  m = t.match(/(^|\s)(\d{1,2})(?:st|nd|rd|th|\s*tarikh|\s*tareekh|\s*tariq)(\s|$)/);
  if (m) return safeDate(d.year, d.month, Number(m[2]), today, futureBias);
  return null;
}

function safeDate(y: number, mo: number, day: number, today: string, futureBias: boolean, explicitYear = false): string | null {
  let dt = DateTime.fromObject({ year: y, month: mo, day });
  if (!dt.isValid) return null;
  if (!explicitYear && !futureBias && dt.toISODate()! > today) dt = dt.minus({ years: 1 });
  return dt.toISODate();
}

export function resolveMonth(t: string, today: string): string | null {
  const d = DateTime.fromISO(today);
  if (has(t, 'is month', 'is mahine', 'is mahina', 'this month', 'current month', 'iss mahine', 'is maheene')) return d.toFormat('yyyy-MM');
  if (has(t, 'pichle mahine', 'pichhle mahine', 'last month', 'previous month', 'pichla mahina', 'pichhla mahina', 'pichle month')) return d.minus({ months: 1 }).toFormat('yyyy-MM');
  for (const w of t.split(' ')) {
    if (MONTHS[w]) {
      let dt = DateTime.fromObject({ year: d.year, month: MONTHS[w], day: 1 });
      if (dt > d) dt = dt.minus({ years: 1 });
      return dt.toFormat('yyyy-MM');
    }
  }
  const m = t.match(/(20\d{2})-(0[1-9]|1[0-2])/);
  if (m) return `${m[1]}-${m[2]}`;
  return null;
}

function extractAmount(t: string): number | null {
  const m = t.match(/(?:rs\.?\s*)?(\d+(?:[.,]\d+)*)\s*(k|hazaar|hazar|hajar|thousand|lakh|lac)?(?=\s|$|\/)/);
  if (!m) return null;
  const digits = m[1].replace(/,/g, '');
  if (digits.length >= 10) return null; // phone number, not money
  const paise = parseAmountToPaise(`${digits}${m[2] ? ' ' + m[2] : ''}`);
  return paise === null ? null : paise / 100;
}

const PHONE_RE = /(?:\+?\d{1,3}[\s-]?)?[6-9]\d{4}[\s-]?\d{5}(?!\d)/g;

function extractPhone(t: string): string | null {
  const m = t.match(PHONE_RE);
  return m ? m[0].replace(/[\s-]/g, '') : null;
}

const withoutPhones = (t: string) => t.replace(PHONE_RE, ' ');

/** Find a known employee name (full or first name) inside the text. */
function findKnownName(t: string, names: string[]): string | null {
  const tokens = t.split(' ');
  let best: { name: string; score: number } | null = null;
  for (const full of names) {
    const lower = full.toLowerCase();
    if (lower.length >= 3 && t.includes(lower)) {
      if (!best || lower.length + 100 > best.score) best = { name: full, score: lower.length + 100 };
      continue;
    }
    const first = lower.split(' ')[0];
    if (first.length >= 3 && tokens.includes(first) && (!best || first.length > best.score)) best = { name: first.charAt(0).toUpperCase() + first.slice(1), score: first.length };
  }
  return best?.name ?? null;
}

/** Guess a name: first non-stopword alphabetic token, preferring the one before "ko/ka/ki/ne". */
function guessName(t: string): string | null {
  const m = t.match(/([a-zऀ-ॿ]{3,})\s+(ko|ka|ki|ke|ne)(\s|$)/);
  if (m && !STOP.has(m[1])) return m[1].charAt(0).toUpperCase() + m[1].slice(1);
  const tok = t.split(' ').find((w) => /^[a-zऀ-ॿ]{3,}$/.test(w) && !STOP.has(w) && !MONTHS[w]);
  return tok ? tok.charAt(0).toUpperCase() + tok.slice(1) : null;
}

const capitalize = (s: string) => s.replace(/\b[a-z]/g, (c) => c.toUpperCase());

export function parseCommand(raw: string, ctx: ParseContext): ParseResult {
  const t = clean(raw);
  if (!t) return { intent: null, args: {}, confidence: 0 };
  const none: ParseResult = { intent: null, args: {}, confidence: 0 };

  if (has(t, /kya kya kar/, /what can you do/, 'help', 'madad', 'commands', /kaise use/)) return { intent: 'help', args: {}, confidence: 0.95 };

  // ---------- Employee self-service ----------
  if (ctx.role === 'employee') {
    const month = resolveMonth(t, ctx.today) ?? undefined;
    if (has(t, /kam kyu/, /kyu kam/, /kyon kam/, /kam kyon/, /why.*(less|low|cut)/, /cut kyu/, /kata kyu/, /kati kyu/)) return { intent: 'why_salary_low', args: { month }, confidence: 0.9 };
    if (has(t, /(meri|mera|my)\s+(salary|tankhwah|tankha|pagar|vetan)/, /salary kitni/, /kitni bani/, /kitna bana/, /kitni banegi/)) return { intent: 'my_salary', args: { month }, confidence: 0.9 };
    if (has(t, 'chutti', 'chhutti', 'leave', 'छुट्टी')) {
      const from = resolveDate(t, ctx.today, true) ?? undefined;
      const type = has(t, 'sick', 'bimar', 'beemar', 'tabiyat') ? 'sick' : has(t, 'unpaid', /bina (pagar|salary|paise)/) ? 'unpaid' : 'paid';
      const days = t.match(/(\d)\s*(din|days?)/);
      const to = from && days ? DateTime.fromISO(from).plus({ days: Number(days[1]) - 1 }).toISODate()! : from;
      return { intent: 'apply_leave', args: { from, to, type, reason: raw.trim().slice(0, 200) }, confidence: from ? 0.85 : 0.6 };
    }
    return none;
  }

  // ---------- Owner / manager ----------
  const month = resolveMonth(t, ctx.today) ?? undefined;

  if (has(t, 'payslip', 'payslips', /salary slip/, /salary parchi/, /parchi/, /pay slip/) && has(t, /bhej/, /send/, /share/, /de do/)) {
    return { intent: 'send_payslips', args: { month }, confidence: 0.9 };
  }
  if (has(t, 'report', 'sheet', 'register')) {
    const kind = has(t, 'attendance', 'hajiri', 'haziri', 'hazri', 'hajri') ? 'attendance' : has(t, 'advance', 'udhaar', 'udhar') ? 'advances' : has(t, 'late', 'der') ? 'late' : 'salary';
    const format = has(t, 'excel', 'xlsx', 'sheet') ? 'xlsx' : 'pdf';
    return { intent: 'report', args: { kind, month, format }, confidence: 0.9 };
  }
  if (has(t, 'salary', 'tankhwah', 'tankha', 'payroll', 'vetan', 'pagar') && has(t, /kitn[ia] (ban|ho|jay|lag)/, 'preview', 'total', /kitna (ban|ho|jay|lag)/, /how much/, /kitni hogi/, /kitna hoga/)) {
    return { intent: 'salary_preview', args: { month, employeeName: findKnownName(t, ctx.employeeNames) ?? undefined }, confidence: 0.9 };
  }

  // Who's late / absent / present / on leave
  if (has(t, 'kaun', 'kon', 'who', 'kitne', 'kis kis', 'list')) {
    const date = resolveDate(t, ctx.today, false) ?? ctx.today;
    const query = has(t, 'late', 'der', /der se/) ? 'late' : has(t, 'absent', /nahi aay/, /nahin aay/, 'gayab', /nahi aa/) ? 'absent' : has(t, 'chutti', 'chhutti', 'leave') ? 'on_leave' : has(t, /mark nahi/, /punch nahi/, /not marked/) ? 'not_marked' : has(t, 'present', 'aaya', 'aaye', 'aayi', 'hajir', 'aa gaye', 'aagaye') ? 'present' : null;
    if (query) return { intent: 'who_is', args: { query, date }, confidence: 0.9 };
  }

  const knownName = findKnownName(t, ctx.employeeNames);
  const amount = extractAmount(withoutPhones(t));

  // Add employee: "Naya banda Pooja 98765xxxxx 12000"
  if (has(t, /naya (banda|staff|karmchari|employee|aadmi|ladka)/, /nayi (ladki|staff|bandi)/, /new (employee|staff)/, /add (staff|employee)/, /staff add/, /employee add/)) {
    const phone = extractPhone(t);
    const rest = withoutPhones(t)
      .replace(/(?:rs\.?\s*)?\d+(?:[.,]\d+)*\s*(k|hazaar|hazar|thousand)?(?=\s|$)/g, ' ')
      .split(' ')
      .filter((w) => /^[a-zऀ-ॿ]+$/.test(w) && !STOP.has(w) && !['naya', 'nayi', 'banda', 'bandi', 'ladki', 'ladka', 'aadmi', 'karmchari', 'new', 'add', 'staff', 'employee', 'salary', 'mobile', 'phone', 'number', 'naam', 'name', 'per', 'day', 'daily', 'monthly'].includes(w));
    const wageType = has(t, 'daily', /per day/, 'dihadi', /roz ka/) ? 'daily' : undefined;
    const name = rest.slice(0, 3).join(' ');
    return { intent: 'add_employee', args: { name: name ? capitalize(name) : undefined, phone: phone ?? undefined, salary: amount ?? undefined, wageType }, confidence: name && phone ? 0.9 : 0.6 };
  }

  // Holiday for everyone: "Kal sabki chutti hai"
  if ((has(t, /sab(ki|ko|hi| ki| ko)? chh?utti/, 'holiday', /chh?utti (hai|rahegi|rakho|karo)/, /dukan band/, /shop band/) && !knownName) || has(t, /sabki chh?utti/)) {
    const date = resolveDate(t, ctx.today, true) ?? ctx.today;
    const nameMatch = raw.match(/(diwali|holi|eid|dussehra|christmas|rakhi|raksha bandhan|navratri|ganesh|pongal|onam|independence|republic)/i);
    return { intent: 'declare_holiday', args: { date, name: nameMatch ? capitalize(nameMatch[1].toLowerCase()) : undefined }, confidence: 0.9 };
  }

  // Leave decision: "Ramesh ki chutti approve kar do"
  if (has(t, 'chutti', 'chhutti', 'leave') && has(t, 'approve', 'manjoor', 'manzoor', 'reject', /mana kar/, /na(h)?i den/, 'cancel')) {
    const decision = has(t, 'reject', /mana kar/, /na(h)?i den/, 'cancel') ? 'rejected' : 'approved';
    return { intent: 'decide_leave', args: { employeeName: knownName ?? guessName(t) ?? undefined, decision }, confidence: knownName ? 0.85 : 0.6 };
  }

  // Advance: "Amit ko 5000 advance diya"
  if (has(t, 'advance', 'adv', 'udhaar', 'udhar', 'loan', 'एडवांस', 'उधार')) {
    const inst = t.match(/(\d{1,2})\s*(kisht|kist|installments?|emi|mahine|months)/);
    return {
      intent: 'record_advance',
      args: { employeeName: knownName ?? guessName(t) ?? undefined, amount: amount ?? undefined, date: resolveDate(t, ctx.today, false) ?? ctx.today, installments: inst ? Number(inst[1]) : undefined },
      confidence: amount && (knownName || guessName(t)) ? 0.9 : 0.55,
    };
  }

  // Bonus / deduction: "Raju ko 500 bonus"
  const isBonus = has(t, 'bonus', 'incentive', 'inaam', 'inam', 'reward');
  const isDeduction = has(t, 'deduction', 'deduct', 'kaat', 'kaato', 'kaatna', 'katoti', 'fine', 'penalty', 'jurmana', 'cut');
  if (isBonus || isDeduction) {
    return {
      intent: 'add_adjustment',
      args: { employeeName: knownName ?? guessName(t) ?? undefined, type: isBonus ? 'bonus' : 'deduction', amount: amount ?? undefined, month, note: raw.trim().slice(0, 120) },
      confidence: amount && (knownName || guessName(t)) ? 0.9 : 0.55,
    };
  }

  // Attendance: "Ramesh ko aaj half day laga do", "Suresh aaj nahi aaya"
  let status: string | null = null;
  let leaveType: string | undefined;
  if (has(t, /half ?day/, /haf ?day/, /aadha din/, /adha din/, /aadhe din/, 'hd')) status = 'half_day';
  else if (has(t, 'absent', /nahi aa/, /nahin aa/, /nai aa/, 'gayab', /nahi aaya/, /nahi aayi/)) status = 'absent';
  else if (has(t, 'chutti', 'chhutti', 'leave', 'छुट्टी')) {
    status = 'leave';
    leaveType = has(t, 'sick', 'bimar', 'beemar') ? 'sick' : has(t, 'unpaid', /bina (pagar|salary|paise)/, 'lwp') ? 'unpaid' : 'paid';
  } else if (has(t, 'present', /full ?day/, 'hajir', 'haazir', 'hazir', /aa gaya/, /aa gayi/, /aaya tha/, /aayi thi/, /aaya hai/, 'aaya', 'aayi')) status = 'present';
  if (status) {
    const employeeName = knownName ?? guessName(t);
    const date = resolveDate(t, ctx.today, false) ?? ctx.today;
    return { intent: 'mark_attendance', args: { employeeName: employeeName ?? undefined, date, status, leaveType }, confidence: employeeName ? (knownName ? 0.92 : 0.75) : 0.5 };
  }
  return none;
}
