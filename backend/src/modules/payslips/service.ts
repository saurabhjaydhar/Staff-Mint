import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { formatMoney } from '../../lib/money.js';
import { monthLabel } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Company, PayrollRun, Payslip } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import { audit } from '../audit/service.js';
import { payslipHtml } from './templates.js';
import { notifyEmployee } from '../notifications/service.js';
import { companyPlan } from '../billing/plans.js';
import { employeeScope } from '../employees/service.js';
import { Employee } from '../../models/index.js';

export async function listPayslips(ctx: Ctx, q: { month?: string; employeeId?: string }) {
  const f: any = { companyId: ctx.companyId, deletedAt: null };
  if (ctx.role === 'employee') {
    f.employeeId = ctx.employeeId;
    f.status = { $in: ['final', 'sent'] };
  } else {
    const scopeIds = (await Employee.find(employeeScope(ctx)).select('_id').lean()).map((e) => e._id);
    f.employeeId = q.employeeId ? new Types.ObjectId(q.employeeId) : { $in: scopeIds };
  }
  if (q.month) f.month = q.month;
  // Hide payslips of superseded runs from employees.
  const slips = await Payslip.find(f).sort({ month: -1, revision: -1 }).limit(200).lean();
  if (ctx.role !== 'employee') return slips;
  const latest = new Map<string, any>();
  for (const s of slips) if (!latest.has(s.month)) latest.set(s.month, s);
  return [...latest.values()];
}

export async function getPayslip(ctx: Ctx, id: string) {
  const s = await Payslip.findOne({ _id: id, companyId: ctx.companyId, deletedAt: null }).lean();
  if (!s) throw notFound('Salary slip');
  if (ctx.role === 'employee' && (String(s.employeeId) !== String(ctx.employeeId) || s.status === 'draft')) throw notFound('Salary slip');
  if (ctx.role === 'manager') {
    const ok = await Employee.exists({ ...employeeScope(ctx), _id: s.employeeId });
    if (!ok) throw notFound('Salary slip');
  }
  return s;
}

/** Plain-language explanation (PRD principle 4, F9 "Meri salary kam kyun?"). */
export function explain(s: any, lang: 'en' | 'hi') {
  const m = (x: number) => formatMoney(x, 'INR');
  const lines: string[] = s.lines.map((l: any) => `${l.kind === 'deduction' ? '−' : '+'} ${l.label?.[lang] ?? l.label?.en}: ${m(l.amountPaise)} — ${l.explanation?.[lang] ?? l.explanation?.en}`);
  const head =
    lang === 'hi'
      ? `${monthLabel(s.month, 'hi')} में ${s.employeeName} का हाथ में सैलरी ${m(s.netPaise)} है (कुल कमाई ${m(s.grossPaise)}, कटौती ${m(s.deductionsPaise)}).`
      : `${s.employeeName}'s net pay for ${monthLabel(s.month, 'en')} is ${m(s.netPaise)} (gross ${m(s.grossPaise)}, deductions ${m(s.deductionsPaise)}).`;
  const less: string[] = [];
  const sm = s.summary ?? {};
  if (sm.absent) less.push(lang === 'hi' ? `${sm.absent} दिन गैरहाज़िर` : `${sm.absent} day(s) absent`);
  if (sm.halfDay) less.push(lang === 'hi' ? `${sm.halfDay} आधे दिन` : `${sm.halfDay} half day(s)`);
  if (sm.unpaidLeave) less.push(lang === 'hi' ? `${sm.unpaidLeave} दिन बिना पैसे की छुट्टी` : `${sm.unpaidLeave} day(s) unpaid leave`);
  if (sm.unmarked) less.push(lang === 'hi' ? `${sm.unmarked} दिन हाज़िरी नहीं लगी` : `${sm.unmarked} day(s) without attendance`);
  const adv = s.lines.filter((l: any) => l.code === 'advance').reduce((a: number, l: any) => a + l.amountPaise, 0);
  if (adv) less.push(lang === 'hi' ? `${m(adv)} एडवांस वापसी` : `${m(adv)} advance recovery`);
  const why = less.length ? (lang === 'hi' ? `कम होने की वजह: ${less.join(', ')}.` : `Reduced because of: ${less.join(', ')}.`) : '';
  return { text: [head, why].filter(Boolean).join(' '), lines };
}

export async function renderPayslipPdf(companyId: Types.ObjectId, payslipId: Types.ObjectId) {
  const s = await Payslip.findOne({ _id: payslipId, companyId }).lean();
  if (!s) return null;
  const company = await Company.findById(companyId).lean();
  const st = (company!.settings as any)?.statutory ?? {};
  const html = payslipHtml(s, { name: company!.name, currency: company!.currency, address: company!.location?.address, pfNumber: st.pfEnabled ? st.pfNumber : null, esiNumber: st.esiEnabled ? st.esiNumber : null });
  const pdf = await (await provider('pdf')).render(html);
  const key = `payslips/${companyId}/${s.month}/r${s.revision}/${s.employeeId}.pdf`;
  await (await provider('storage')).put(key, pdf, 'application/pdf');
  await Payslip.updateOne({ _id: s._id, companyId }, { $set: { pdfKey: key } });
  return key;
}

export async function generateRunPdfs(companyId: Types.ObjectId, runId: Types.ObjectId) {
  const slips = await Payslip.find({ companyId, runId, pdfKey: null }).select('_id').lean();
  for (const s of slips) await renderPayslipPdf(companyId, s._id);
  return slips.length;
}

/** Deliver salary slips to staff: app push always; WhatsApp document when the plan includes it. */
export async function sendPayslips(ctx: Ctx, runId: string, payslipIds?: string[]) {
  const run = await PayrollRun.findOne({ _id: runId, companyId: ctx.companyId });
  if (!run) throw notFound('Payroll run');
  if (!['approved', 'paid'].includes(run.status)) throw new AppError('CONFLICT', 'Approve the salary before sending salary slips');
  const f: any = { companyId: ctx.companyId, runId: run._id };
  if (payslipIds?.length) f._id = { $in: payslipIds };
  const slips = await Payslip.find(f).lean();
  const { plan } = await companyPlan({ _id: ctx.companyId });
  const viaWhatsApp = plan.features.includes('whatsapp_payslips');
  const storage = await provider('storage');
  let sent = 0;
  for (const s of slips) {
    const key = s.pdfKey ?? (await renderPayslipPdf(ctx.companyId, s._id));
    const url = key ? await storage.signedUrl(key, 24 * 3600, { filename: `salary-slip-${s.month}.pdf` }) : undefined;
    await notifyEmployee(
      ctx.companyId,
      s.employeeId,
      {
        template: 'payslip_ready',
        title: `Salary slip for ${monthLabel(s.month, 'en')}`,
        titleHi: `${monthLabel(s.month, 'hi')} की सैलरी स्लिप`,
        body: `In hand ${formatMoney(s.netPaise ?? 0)}${s.paidOn ? ' · paid' : ''}`,
        bodyHi: `हाथ में सैलरी ${formatMoney(s.netPaise ?? 0)}${s.paidOn ? ' · पैसे दे दिए' : ''}`,
        data: { type: 'payslip', payslipId: String(s._id), month: s.month },
        whatsapp: { template: 'payslip_ready', params: [s.employeeName ?? '', monthLabel(s.month, 'en'), formatMoney(s.netPaise ?? 0)], documentUrl: url, filename: `salary-slip-${s.month}.pdf` },
      },
      { whatsapp: viaWhatsApp },
    );
    await Payslip.updateOne({ _id: s._id, companyId: ctx.companyId }, { $set: { status: 'sent', sentAt: new Date() } });
    sent++;
  }
  await audit(ctx, { action: 'payslips.send', entity: 'payroll_run', entityId: run._id, after: { sent, viaWhatsApp } });
  return { queued: sent, viaWhatsApp };
}
