import { notFound } from '../../lib/errors.js';
import { DateTime } from 'luxon';
import { localDateOf } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Company, VerificationRequest } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import { BASE_CSS } from '../payslips/templates.js';
import { audit } from '../audit/service.js';
import { assertEmployeeInScope } from '../employees/service.js';
import { ownerView } from './service.js';

type Lang = 'en' | 'hi';
/** "12 Oct 2026" / "12 अक्टूबर 2026" */
const formatDate = (ymd: string, lang: Lang) => {
  const d = DateTime.fromISO(ymd.slice(0, 10));
  return d.isValid ? (lang === 'hi' ? d.setLocale('hi').toFormat('d LLLL yyyy') : d.toFormat('d LLL yyyy')) : ymd;
};
const esc = (s: unknown) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);

const T = {
  title: { en: 'Documents check report', hi: 'दस्तावेज़ जाँच रिपोर्ट' },
  staff: { en: 'Staff member', hi: 'स्टाफ़' },
  phone: { en: 'Phone', hi: 'फ़ोन' },
  asked: { en: 'Asked on', hi: 'कब कहा' },
  agreed: { en: 'Agreed', hi: 'अनुमति' },
  inApp: { en: 'in the app on', hi: 'ऐप में,' },
  onPaper: { en: 'on paper (signed slip) on', hi: 'काग़ज़ पर (साइन की हुई पर्ची),' },
  notYet: { en: 'not yet', hi: 'अभी नहीं' },
  overall: { en: 'Result', hi: 'नतीजा' },
  check: { en: 'Check', hi: 'जाँच' },
  result: { en: 'Result', hi: 'नतीजा' },
  details: { en: 'Details', hi: 'जानकारी' },
  checkedOn: { en: 'Checked on', hi: 'कब जाँचा' },
  ending: { en: 'ending', hi: 'आख़िरी अंक' },
  onRecord: { en: 'Name on record', hi: 'रिकॉर्ड में नाम' },
  match: { en: 'match', hi: 'मेल' },
  accepted: { en: 'Accepted by owner', hi: 'मालिक ने माना' },
  validTill: { en: 'Valid till', hi: 'कब तक' },
  pastJobs: { en: 'Past jobs (PF record)', hi: 'पहले की नौकरियाँ (PF रिकॉर्ड)' },
  now: { en: 'now', hi: 'अभी तक' },
  idUsed: { en: 'Matched with', hi: 'किससे मिलाया' },
  foot: {
    en: 'Checked against government records through StaffMint. Only the last 4 digits of Aadhaar, licence, voter ID, UAN and account numbers are kept. Generated on',
    hi: 'StaffMint से सरकारी रिकॉर्ड पर जाँचा गया। आधार, लाइसेंस, वोटर कार्ड, UAN और खाता नंबर के सिर्फ़ आख़िरी 4 अंक रखे जाते हैं। बनाई गई:',
  },
};

const KIND: Record<string, [string, string]> = {
  aadhaar: ['Aadhaar', 'आधार'],
  pan: ['PAN', 'PAN'],
  dl: ['Driving licence', 'ड्राइविंग लाइसेंस'],
  voter: ['Voter ID', 'वोटर कार्ड'],
  bank: ['Bank account (₹1 test)', 'बैंक खाता (₹1 जाँच)'],
  uan: ['PF number (UAN)', 'PF नंबर (UAN)'],
  face: ['Selfie vs ID photo', 'सेल्फ़ी और पहचान पत्र की फ़ोटो'],
};
const RESULT: Record<string, [string, string]> = {
  verified: ['Verified ✓', 'सही ✓'],
  mismatch: ['Name doesn’t match', 'नाम नहीं मिला'],
  not_found: ['Not found', 'नहीं मिला'],
  failed: ['Couldn’t check', 'जाँच नहीं हो पाई'],
  waiting: ['Not done yet', 'अभी बाक़ी'],
  otp_sent: ['Not done yet', 'अभी बाक़ी'],
};
const BADGE: Record<string, [string, string]> = {
  verified: ['Verified', 'सब सही'],
  needs_attention: ['Needs a look', 'ध्यान दें'],
  in_progress: ['In progress', 'चल रही है'],
  asked: ['Waiting for them to agree', 'अनुमति का इंतज़ार'],
  none: ['Not checked', 'जाँच नहीं हुई'],
};
const DOC: Record<string, [string, string]> = { aadhaar: ['Aadhaar', 'आधार'], pan: ['PAN', 'PAN'], dl: ['driving licence', 'ड्राइविंग लाइसेंस'], voter: ['voter ID', 'वोटर कार्ड'], passport: ['passport', 'पासपोर्ट'] };

/** One page for the owner's records: who was checked, how they agreed, and each result. */
export async function reportPdf(ctx: Ctx, employeeId: string) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  const view = await ownerView(ctx, employeeId);
  if (!view.request) throw notFound('Documents check');
  const lang: Lang = ctx.language === 'hi' ? 'hi' : 'en';
  const t = (k: keyof typeof T) => T[k][lang];
  const pick = (m: Record<string, [string, string]>, k: string) => (m[k] ?? [k, k])[lang === 'hi' ? 1 : 0];
  const company = (await Company.findById(ctx.companyId).select('name timezone').lean())!;
  const req = (await VerificationRequest.findOne({ _id: view.request.id, companyId: ctx.companyId }).select('createdAt').lean())!;
  const date = (d: Date | string | null | undefined) => (d ? formatDate(localDateOf(new Date(d), company.timezone), lang) : '');

  const consent = view.request.consentAt ? `${view.request.consentBy === 'owner_on_behalf' ? t('onPaper') : t('inApp')} ${date(view.request.consentAt)}` : t('notYet');
  const rows = view.checks.map((c) => {
    const lines: string[] = [];
    if (c.last4) lines.push(`${t('ending')} ${esc(c.last4)}`);
    if (c.nameOnRecord) lines.push(`${t('onRecord')}: ${esc(c.nameOnRecord)}${c.matchScore != null ? ` (${c.matchScore}% ${t('match')})` : ''}`);
    if (c.kind === 'face' && c.matchScore != null) lines.push(`${c.matchScore}% ${t('match')}`);
    if (c.kind === 'face' && c.details?.idKind) lines.push(`${t('idUsed')}: ${esc(pick(DOC, c.details.idKind))}`);
    if (c.details?.validTill) lines.push(`${t('validTill')}: ${esc(formatDate(c.details.validTill, lang))}`);
    if (c.details?.bankName) lines.push(esc(c.details.bankName));
    if (c.employers?.length) {
      lines.push(
        `${t('pastJobs')}:<ul>${c.employers
          .map((e) => `<li>${esc(e.name)} · ${e.joined ? esc(formatDate(e.joined, lang)) : '?'} – ${e.left ? esc(formatDate(e.left, lang)) : t('now')}</li>`)
          .join('')}</ul>`,
      );
    }
    if (c.override) lines.push(`${t('accepted')}: ${esc(c.override.reason)}`);
    const result = c.override ? `${pick(RESULT, c.status)} · ${t('accepted')}` : c.kind === 'face' && c.status === 'mismatch' ? (lang === 'hi' ? 'चेहरा नहीं मिला' : 'Doesn’t look like the ID photo') : pick(RESULT, c.status);
    return `<tr><td>${esc(pick(KIND, c.kind))}</td><td class="${c.status === 'verified' || c.override ? 'ok' : c.status === 'mismatch' || c.status === 'not_found' ? 'bad' : ''}">${esc(result)}</td><td>${lines.join('<br/>')}</td><td>${esc(date(c.checkedAt))}</td></tr>`;
  });

  const html = `<!doctype html><html><head><meta charset="utf-8"/><style>${BASE_CSS}
  .grid td { border: none; padding: 2px 8px 2px 0; } .ok { color: #157a4c; font-weight: 600; } .bad { color: #b42318; font-weight: 600; }
  ul { margin: 2px 0 0; padding-left: 16px; } .foot { margin-top: 16px; padding-top: 8px; border-top: 1px solid #d9e2ec; color: #829ab1; font-size: 10px; }
  </style></head><body>
  <div class="hdr"><div><div class="brand">StaffMint</div><h1>${esc(company.name)}</h1></div><div style="text-align:right"><h1>${t('title')}</h1></div></div>
  <table class="grid" style="width:auto">
    <tr><td class="muted">${t('staff')}</td><td><b>${esc(emp.name)}</b></td></tr>
    <tr><td class="muted">${t('phone')}</td><td>${esc(emp.phone ?? '')}</td></tr>
    <tr><td class="muted">${t('asked')}</td><td>${esc(date(req.createdAt))}</td></tr>
    <tr><td class="muted">${t('agreed')}</td><td>${esc(consent)}</td></tr>
    <tr><td class="muted">${t('overall')}</td><td><b>${esc(pick(BADGE, view.badge))}</b></td></tr>
  </table>
  <table><tr><th>${t('check')}</th><th>${t('result')}</th><th>${t('details')}</th><th>${t('checkedOn')}</th></tr>${rows.join('')}</table>
  <div class="foot">${t('foot')} ${esc(date(new Date()))}.</div>
  </body></html>`;

  const data = await (await provider('pdf')).render(html);
  await audit(ctx, { action: 'verification.report', entity: 'employee', entityId: emp._id });
  const slug = emp.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'staff';
  return { filename: `documents-check-${slug}.pdf`, data };
}
