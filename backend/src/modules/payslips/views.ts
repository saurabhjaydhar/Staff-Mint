import { provider } from '../../providers/registry.js';
import { env } from '../../config/env.js';

export async function payslipView(s: any, lang: 'en' | 'hi' = 'en') {
  const pdfUrl = s.pdfKey ? await (await provider('storage')).signedUrl(s.pdfKey, env.SIGNED_URL_TTL_SEC, { filename: `salary-slip-${s.month}-${s.employeeName}.pdf` }) : null;
  return {
    id: s._id ? String(s._id) : null,
    runId: s.runId ? String(s.runId) : null,
    employeeId: String(s.employeeId),
    employeeName: s.employeeName,
    month: s.month,
    revision: s.revision ?? 1,
    wageType: s.wageType,
    ratePaise: s.ratePaise,
    payableDays: s.payableDays,
    daysInMonth: s.daysInMonth,
    divisor: s.divisor,
    summary: s.summary,
    lines: (s.lines ?? []).map((l: any) => ({ code: l.code, kind: l.kind, amountPaise: l.amountPaise, label: l.label?.[lang] ?? l.label?.en, explanation: l.explanation?.[lang] ?? l.explanation?.en })),
    grossPaise: s.grossPaise,
    deductionsPaise: s.deductionsPaise,
    netPaise: s.netPaise,
    employerContributions: (s.employerContributions ?? []).map((c: any) => ({ code: c.code, amountPaise: c.amountPaise, label: c.label?.[lang] ?? c.label?.en, explanation: c.explanation?.[lang] ?? c.explanation?.en })),
    employeeInfo: s.employeeInfo ?? null,
    paidOn: s.paidOn ?? null,
    paymentMethod: s.paymentMethod ?? null,
    status: s.status ?? 'draft',
    pdfUrl,
    sentAt: s.sentAt ?? null,
  };
}
