import { formatMoney } from '../../lib/money.js';
import { monthLabel } from '../../lib/dates.js';
import { rupeesInWordsEn, rupeesInWordsHi } from '../../lib/words.js';

const esc = (s: unknown) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);

export const BASE_CSS = `
  @import url('https://fonts.googleapis.com/css2?family=Noto+Sans:wght@400;600&family=Noto+Sans+Devanagari:wght@400;600&display=swap');
  * { box-sizing: border-box; }
  body { font-family: 'Noto Sans', 'Noto Sans Devanagari', 'Lohit Devanagari', sans-serif; color: #1f2933; font-size: 12px; margin: 0; }
  .brand { color: #2BB673; font-weight: 600; font-size: 18px; }
  h1 { font-size: 16px; margin: 4px 0; }
  table { width: 100%; border-collapse: collapse; margin-top: 8px; }
  th, td { border: 1px solid #d9e2ec; padding: 5px 6px; text-align: left; vertical-align: top; }
  th { background: #e9f7f0; }
  .num { text-align: right; white-space: nowrap; }
  .muted { color: #627d98; font-size: 10px; }
  .total td { font-weight: 600; background: #f0fbf6; }
  .hdr { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #2BB673; padding-bottom: 6px; }
`;

type Lang = 'en' | 'hi';

const SLIP_TEXT = {
  title: { en: 'Salary Slip', hi: 'सैलरी स्लिप' },
  employee: { en: 'Employee', hi: 'स्टाफ़' },
  code: { en: 'Employee ID', hi: 'स्टाफ़ ID' },
  designation: { en: 'Designation', hi: 'पद' },
  joining: { en: 'Date of joining', hi: 'जॉइनिंग की तारीख़' },
  phone: { en: 'Phone', hi: 'फ़ोन' },
  bank: { en: 'Paid to', hi: 'पैसे इस खाते में' },
  uan: { en: 'PF UAN', hi: 'PF UAN' },
  esic: { en: 'ESIC No.', hi: 'ESIC नंबर' },
  pan: { en: 'PAN', hi: 'PAN' },
  salary: { en: 'Salary', hi: 'सैलरी' },
  perMonth: { en: 'per month', hi: 'प्रति माह' },
  perDay: { en: 'per day', hi: 'प्रति दिन' },
  daysInMonth: { en: 'Days in month', hi: 'महीने के दिन' },
  paidDays: { en: 'Paid days', hi: 'पैसे वाले दिन' },
  lopDays: { en: 'Unpaid days (LOP)', hi: 'बिना पैसे के दिन' },
  present: { en: 'Present', hi: 'हाज़िर' },
  halfDay: { en: 'Half day', hi: 'आधा दिन' },
  absent: { en: 'Absent', hi: 'ग़ैरहाज़िर' },
  paidLeave: { en: 'Paid leave', hi: 'पेड छुट्टी' },
  unpaidLeave: { en: 'Unpaid leave', hi: 'बिना पैसे की छुट्टी' },
  holidays: { en: 'Holidays', hi: 'त्योहार' },
  weekOffs: { en: 'Week off', hi: 'साप्ताहिक छुट्टी' },
  earnings: { en: 'Earnings', hi: 'कमाई' },
  deductions: { en: 'Deductions', hi: 'कटौती' },
  amount: { en: 'Amount', hi: 'राशि' },
  gross: { en: 'Gross earnings', hi: 'कुल कमाई' },
  totalDeductions: { en: 'Total deductions', hi: 'कुल कटौती' },
  none: { en: 'No deductions', hi: 'कोई कटौती नहीं' },
  net: { en: 'Net pay (in hand)', hi: 'हाथ में सैलरी' },
  paid: { en: 'Paid', hi: 'पैसे दे दिए' },
  notPaid: { en: 'Not paid yet', hi: 'अभी पैसे नहीं दिए' },
  employer: { en: 'Paid by the employer on top of salary', hi: 'सैलरी के अलावा मालिक जमा करते हैं' },
  how: { en: 'How this was worked out', hi: 'हिसाब कैसे बना' },
  updated: { en: 'Updated slip: replaces the earlier one for this month', hi: 'नई स्लिप: इस महीने की पुरानी स्लिप की जगह' },
  footer: { en: 'This is a computer-generated salary slip and does not need a signature.', hi: 'यह कंप्यूटर से बनी सैलरी स्लिप है, इस पर हस्ताक्षर की ज़रूरत नहीं।' },
  questions: { en: 'Questions? Ask your employer, or ask in the StaffMint app.', hi: 'सवाल हो तो मालिक से पूछें, या StaffMint ऐप में पूछें।' },
} as const;

const METHOD = { cash: { en: 'cash', hi: 'नकद' }, upi: { en: 'UPI', hi: 'UPI' }, bank: { en: 'bank transfer', hi: 'बैंक ट्रांसफ़र' }, mixed: { en: 'cash + UPI/bank', hi: 'नकद + UPI/बैंक' } } as Record<string, { en: string; hi: string }>;

const fmtDays = (n: number) => (Number.isInteger(n) ? String(n) : n.toFixed(1));

function prettyDate(ymd: string | null | undefined, lang: Lang) {
  if (!ymd) return '';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(ymd);
  if (!m) return ymd;
  const mon = monthLabel(`${m[1]}-${m[2]}`, lang).split(' ')[0];
  return `${Number(m[3])} ${mon} ${m[1]}`;
}

export interface SlipCompany {
  name: string;
  currency: string;
  address?: string | null;
  pfNumber?: string | null;
  esiNumber?: string | null;
}

/**
 * Formal salary slip: employee details, paid/unpaid days, Earnings | Deductions side by side,
 * Gross, Total deductions, Net pay in figures and words, paid date and method. PF/ESI/PT and the
 * employer contribution box appear only when the shop uses them. Printed in the staff member's
 * language; in Hindi, headings also carry the English word.
 */
export function payslipHtml(p: any, company: SlipCompany) {
  const lang: Lang = p.employeeInfo?.language === 'en' ? 'en' : 'hi';
  const t = (k: keyof typeof SLIP_TEXT) => (lang === 'hi' ? `${SLIP_TEXT[k].hi} <span class="en">${SLIP_TEXT[k].en}</span>` : SLIP_TEXT[k].en);
  const tt = (k: keyof typeof SLIP_TEXT) => SLIP_TEXT[k][lang];
  const m = (x: number) => formatMoney(x ?? 0, company.currency);
  const info = p.employeeInfo ?? {};
  const s = p.summary ?? {};
  const earnings = (p.lines ?? []).filter((l: any) => l.kind === 'earning');
  const deductions = (p.lines ?? []).filter((l: any) => l.kind === 'deduction');
  const rows = Math.max(earnings.length, deductions.length, 1);
  const label = (l: any) => esc(l.label?.[lang] ?? l.label?.en);
  const daysInMonth = p.daysInMonth ?? 0;
  const lop = p.wageType === 'monthly' ? Math.max(0, daysInMonth - (p.payableDays ?? 0)) : null;
  const initials = company.name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  const words = lang === 'hi' ? rupeesInWordsHi(p.netPaise ?? 0) : rupeesInWordsEn(p.netPaise ?? 0);
  const method = p.paymentMethod ? METHOD[p.paymentMethod]?.[lang] ?? p.paymentMethod : null;
  const detail = (k: keyof typeof SLIP_TEXT, v: unknown) => (v ? `<div class="kv"><span>${t(k)}</span><b>${esc(v)}</b></div>` : '');
  const paidTo = info.bankLast4 ? `A/c XXXX${info.bankLast4}` : info.upiId ? `UPI ${info.upiId}` : '';
  const rate = `${m(p.ratePaise)} ${p.wageType === 'daily' ? tt('perDay') : tt('perMonth')}`;
  const chips = (
    [
      ['present', s.present],
      ['halfDay', s.halfDay],
      ['paidLeave', s.paidLeave],
      ['unpaidLeave', s.unpaidLeave],
      ['holidays', s.holidays],
      ['weekOffs', s.weekOffs],
      ['absent', s.absent],
    ] as [keyof typeof SLIP_TEXT, number][]
  )
    .filter(([, n]) => n)
    .map(([k, n]) => `<span class="chip ${k}">${tt(k)}: ${fmtDays(n)}</span>`)
    .join('');
  const employer = p.employerContributions ?? [];
  const tableRows = Array.from({ length: rows }, (_, i) => {
    const e = earnings[i];
    const d = deductions[i];
    return `<tr><td>${e ? label(e) : ''}</td><td class="num">${e ? m(e.amountPaise) : ''}</td><td class="sep">${d ? label(d) : i === 0 ? `<span class="muted">${tt('none')}</span>` : ''}</td><td class="num">${d ? m(d.amountPaise) : ''}</td></tr>`;
  }).join('');
  const how = (p.lines ?? [])
    .filter((l: any) => l.explanation?.[lang] || l.explanation?.en)
    .map((l: any) => `<li><b>${label(l)}:</b> ${esc(l.explanation?.[lang] ?? l.explanation?.en)}</li>`)
    .join('');

  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"/><style>${BASE_CSS}${SLIP_CSS}</style></head><body><div class="slip">
  <div class="head">
    <div class="logo">${esc(initials)}</div>
    <div class="co"><div class="coname">${esc(company.name)}</div><div class="muted">${esc(company.address ?? '')}</div>
      ${company.pfNumber || company.esiNumber ? `<div class="muted">${company.pfNumber ? `PF: ${esc(company.pfNumber)}` : ''}${company.pfNumber && company.esiNumber ? ' · ' : ''}${company.esiNumber ? `ESI: ${esc(company.esiNumber)}` : ''}</div>` : ''}</div>
    <div class="ttl"><div class="title">${t('title')}</div><div class="month">${esc(monthLabel(p.month, lang))}</div></div>
  </div>
  ${p.revision > 1 ? `<div class="updated">${tt('updated')}</div>` : ''}
  <div class="emp">
    <div class="ename">${esc(p.employeeName)}</div>
    <div class="grid">
      ${detail('code', info.code)}${detail('designation', info.designation)}${detail('joining', prettyDate(info.joiningDate, lang))}${detail('phone', p.employeePhone)}
      ${detail('salary', rate)}${detail('bank', paidTo)}${detail('uan', info.uan)}${detail('esic', info.esicNumber)}${detail('pan', info.panMasked)}
    </div>
  </div>
  <div class="days">
    <div><span>${t('daysInMonth')}</span><b>${daysInMonth}</b></div>
    <div><span>${t('paidDays')}</span><b>${fmtDays(p.payableDays ?? 0)}</b></div>
    ${lop !== null ? `<div><span>${t('lopDays')}</span><b>${fmtDays(lop)}</b></div>` : ''}
  </div>
  ${chips ? `<div class="chips">${chips}</div>` : ''}
  <table class="money">
    <thead><tr><th>${t('earnings')}</th><th class="num">${tt('amount')}</th><th class="sep">${t('deductions')}</th><th class="num">${tt('amount')}</th></tr></thead>
    <tbody>${tableRows}</tbody>
    <tfoot><tr><td>${t('gross')}</td><td class="num">${m(p.grossPaise)}</td><td class="sep">${t('totalDeductions')}</td><td class="num">${m(p.deductionsPaise)}</td></tr></tfoot>
  </table>
  <div class="net">
    <div><div class="netlabel">${t('net')}</div><div class="netamt">${m(p.netPaise)}</div><div class="words">${esc(words)}</div></div>
    <div class="paid">${p.paidOn ? `<div class="paidchip">✓ ${tt('paid')}</div><div class="muted">${esc(prettyDate(p.paidOn, lang))}${method ? ` · ${esc(method)}` : ''}</div>` : `<div class="unpaid">${tt('notPaid')}</div>`}</div>
  </div>
  ${employer.length ? `<div class="employer"><div class="ehead">${t('employer')}</div>${employer.map((c: any) => `<div class="kv"><span>${esc(c.label?.[lang] ?? c.label?.en)}</span><b>${m(c.amountPaise)}</b></div>`).join('')}</div>` : ''}
  ${how ? `<div class="how"><div class="hhead">${t('how')}</div><ul>${how}</ul></div>` : ''}
  <div class="foot"><div>${tt('footer')}</div><div>${tt('questions')}</div><div class="brand-small">Made with StaffMint</div></div>
  </div></body></html>`;
}

const SLIP_CSS = `
  @page { size: A4; margin: 14mm; }
  body { font-size: 12.5px; line-height: 1.45; }
  .slip { max-width: 760px; margin: 0 auto; }
  .en { color: #627d98; font-weight: 400; font-size: 0.82em; }
  .head { display: flex; gap: 12px; align-items: flex-start; border-bottom: 2px solid #2BB673; padding-bottom: 10px; }
  .logo { width: 44px; height: 44px; border-radius: 10px; background: #e9f7f0; color: #157a4c; font-weight: 700; font-size: 16px; display: flex; align-items: center; justify-content: center; flex: 0 0 auto; }
  .co { flex: 1; } .coname { font-size: 17px; font-weight: 600; }
  .ttl { text-align: right; } .title { font-size: 16px; font-weight: 600; } .month { color: #334e68; }
  .updated { margin-top: 8px; background: #fff7e6; border: 1px solid #f6d58a; border-radius: 8px; padding: 6px 10px; font-size: 11.5px; }
  .emp { margin-top: 12px; } .ename { font-size: 16px; font-weight: 600; margin-bottom: 6px; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 3px 22px; }
  .kv { display: flex; justify-content: space-between; gap: 10px; border-bottom: 1px dotted #d9e2ec; padding: 3px 0; }
  .kv span { color: #627d98; } .kv b { font-weight: 600; text-align: right; }
  .days { display: flex; gap: 10px; margin-top: 12px; }
  .days div { flex: 1; background: #f5f7fa; border-radius: 8px; padding: 6px 10px; display: flex; justify-content: space-between; align-items: center; }
  .days span { color: #627d98; font-size: 11.5px; } .days b { font-size: 15px; }
  .chips { margin-top: 8px; display: flex; flex-wrap: wrap; gap: 6px; }
  .chip { background: #f0f4f8; border-radius: 999px; padding: 2px 9px; font-size: 11px; }
  .chip.present, .chip.paidLeave { background: #e9f7f0; color: #157a4c; } .chip.absent, .chip.unpaidLeave { background: #fce9e7; color: #b33a3a; } .chip.halfDay { background: #ffe9d6; color: #a1490a; }
  table.money { margin-top: 12px; border: 1px solid #d9e2ec; border-radius: 8px; }
  table.money th, table.money td { border: none; border-bottom: 1px solid #edf1f5; padding: 7px 10px; }
  table.money th { background: #e9f7f0; } table.money .sep { border-left: 1px solid #d9e2ec; }
  table.money tfoot td { font-weight: 600; background: #f0fbf6; border-bottom: none; }
  .net { margin-top: 12px; display: flex; justify-content: space-between; align-items: center; gap: 12px; border: 2px solid #2BB673; border-radius: 12px; padding: 12px 16px; background: #f0fbf6; }
  .netlabel { color: #334e68; } .netamt { font-size: 26px; font-weight: 700; color: #157a4c; } .words { color: #486581; font-size: 11.5px; }
  .paid { text-align: right; } .paidchip { display: inline-block; background: #2BB673; color: #fff; border-radius: 999px; padding: 3px 10px; font-weight: 600; } .unpaid { color: #a86e00; font-weight: 600; }
  .employer { margin-top: 12px; border: 1px dashed #bcccdc; border-radius: 8px; padding: 8px 12px; } .ehead { font-weight: 600; margin-bottom: 4px; }
  .how { margin-top: 12px; font-size: 11px; color: #486581; } .hhead { font-weight: 600; color: #334e68; } .how ul { margin: 4px 0 0; padding-left: 16px; }
  .foot { margin-top: 16px; padding-top: 8px; border-top: 1px solid #d9e2ec; color: #829ab1; font-size: 10.5px; text-align: center; }
  .brand-small { margin-top: 3px; color: #2BB673; }
`;

export function tableReportHtml(title: string, company: string, headers: string[], rows: (string | number)[][], subtitle = '') {
  return `<!doctype html><html><head><meta charset="utf-8"/><style>${BASE_CSS} td,th{font-size:10px}</style></head><body>
  <div class="hdr"><div><div class="brand">StaffMint</div><h1>${esc(company)}</h1></div><div style="text-align:right"><h1>${esc(title)}</h1><div class="muted">${esc(subtitle)}</div></div></div>
  <table><tr>${headers.map((h) => `<th>${esc(h)}</th>`).join('')}</tr>${rows.map((r) => `<tr>${r.map((c) => `<td${typeof c === 'number' ? ' class="num"' : ''}>${esc(c)}</td>`).join('')}</tr>`).join('')}</table>
  </body></html>`;
}
