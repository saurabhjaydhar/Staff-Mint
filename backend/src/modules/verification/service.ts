import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { todayIn } from '../../lib/dates.js';
import { decryptField, encryptField } from '../../lib/crypto.js';
import type { Ctx } from '../../lib/context.js';
import { logger } from '../../lib/logger.js';
import { Company, Employee, VerificationCheck, VerificationRequest, type VerificationKind } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import type { VerifyRecord } from '../../providers/types.js';
import { assertEmployeeInScope } from '../employees/service.js';
import { audit } from '../audit/service.js';
import { notifyEmployee, notifyOwners } from '../notifications/service.js';
import { companyPlan } from '../billing/plans.js';
import { getConfig } from '../config/service.js';
import { setBank } from '../profile/service.js';

/** Bumped when the consent wording changes; each request records which version the person agreed to. */
export const CONSENT_VERSION = '2026-10';

export const CONSENT_TEXT = {
  en: [
    'Your employer will check your documents against government records.',
    'Aadhaar: your name and date of birth, with an OTP sent to your Aadhaar mobile. We never save your full Aadhaar number, only the last 4 digits.',
    'PAN: that it is valid and the name on it.',
    'Bank account: we send ₹1 to check the account is yours. Your salary goes here.',
    'Only the owner sees the results. They are deleted 180 days after you leave.',
  ],
  hi: [
    'आपके मालिक आपके दस्तावेज़ सरकारी रिकॉर्ड से जाँचेंगे।',
    'आधार: आपका नाम और जन्म तारीख़, आधार वाले मोबाइल पर OTP से। पूरा आधार नंबर कभी सेव नहीं होता, सिर्फ़ आख़िरी 4 अंक।',
    'PAN: कि वह सही है और उस पर किसका नाम है।',
    'बैंक खाता: खाता आपका है यह जाँचने के लिए ₹1 भेजते हैं। सैलरी इसी में आएगी।',
    'नतीजे सिर्फ़ मालिक देखते हैं। काम छोड़ने के 180 दिन बाद हटा दिए जाते हैं।',
  ],
};

const OPEN = ['asked', 'in_progress'] as const;
const MAX_ATTEMPTS = 5;

// ---------------------------------------------------------------- names

const TITLES = new Set(['mr', 'mrs', 'ms', 'miss', 'shri', 'sri', 'smt', 'kumari', 'km', 'dr']);
const tokens = (s: string) =>
  s
    .toLowerCase()
    .replace(/[^a-zऀ-ॿ ]/g, ' ')
    .split(/\s+/)
    .filter((t) => t && !TITLES.has(t));

/** How alike two names are, 0–100. Initials count ("R Kumar" ~ "Rajesh Kumar"); order doesn't. */
export function nameMatch(a: string, b: string): number {
  const [A, B] = [tokens(a), tokens(b)];
  if (!A.length || !B.length) return 0;
  const used = new Set<number>();
  let common = 0;
  for (const t of A) {
    const i = B.findIndex((u, j) => !used.has(j) && (u === t || (t.length === 1 && u.startsWith(t)) || (u.length === 1 && t.startsWith(u))));
    if (i >= 0) {
      used.add(i);
      common++;
    }
  }
  return Math.round((200 * common) / (A.length + B.length));
}

// ---------------------------------------------------------------- views

const terminal = (c: { status: string }) => ['verified', 'mismatch', 'not_found'].includes(c.status);
const settled = (c: { status: string; override?: unknown }) => c.status === 'verified' || (c.status === 'mismatch' && !!c.override);

function checkView(c: any, withDetails: boolean) {
  let details: Record<string, string> | null = null;
  if (withDetails && c.detailsEnc) {
    try {
      details = JSON.parse(decryptField(c.detailsEnc));
    } catch {
      details = null;
    }
  }
  return {
    id: String(c._id),
    kind: c.kind as VerificationKind,
    status: c.status as string,
    last4: c.last4 ?? null,
    nameOnRecord: c.nameOnRecord ?? null,
    matchScore: c.matchScore ?? null,
    override: c.override ? { reason: c.override.reason ?? '', at: c.override.at } : null,
    details,
    attempts: c.attempts ?? 0,
    checkedAt: c.checkedAt ?? null,
  };
}

function requestView(r: any) {
  return {
    id: String(r._id),
    kinds: r.kinds as VerificationKind[],
    status: r.status as string,
    consented: !!r.consent?.acceptedAt,
    consentAt: r.consent?.acceptedAt ?? null,
    createdAt: r.createdAt,
    doneAt: r.doneAt ?? null,
  };
}

// ---------------------------------------------------------------- owner

async function monthOf(companyId: Types.ObjectId) {
  return todayIn((await Company.findById(companyId).select('timezone').lean())!.timezone).slice(0, 7);
}

/** Checks included this month and how many are used. */
export async function quota(ctx: Ctx) {
  const [{ plan }, monthly, extra, month] = await Promise.all([
    companyPlan({ _id: ctx.companyId }),
    getConfig<Record<string, number>>('verification.monthly', ctx.companyId),
    getConfig<number>('verification.extraPricePaise', ctx.companyId),
    monthOf(ctx.companyId),
  ]);
  const used = await VerificationRequest.countDocuments({ companyId: ctx.companyId, month, status: { $ne: 'cancelled' } });
  return { used, limit: plan.features.includes('verification') ? (monthly?.[plan.code] ?? 0) : 0, extraPricePaise: extra };
}

/** The owner's view of one person's verification: the latest request, its checks, and this month's allowance. */
export async function ownerView(ctx: Ctx, employeeId: string) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  const r = await VerificationRequest.findOne({ companyId: ctx.companyId, employeeId: emp._id, status: { $ne: 'cancelled' } }).sort({ createdAt: -1 }).lean();
  const checks = r ? await VerificationCheck.find({ companyId: ctx.companyId, requestId: r._id }).lean() : [];
  return {
    badge: emp.verification?.status ?? 'none',
    request: r ? requestView(r) : null,
    checks: order(checks).map((c) => checkView(c, true)),
    quota: await quota(ctx),
  };
}

const KIND_ORDER: VerificationKind[] = ['aadhaar', 'pan', 'bank'];
const order = <T extends { kind: string }>(list: T[]) => [...list].sort((a, b) => KIND_ORDER.indexOf(a.kind as VerificationKind) - KIND_ORDER.indexOf(b.kind as VerificationKind));

/** Ask a staff member to verify their documents. Counts against the month's allowance. */
export async function requestVerification(ctx: Ctx, employeeId: string, kinds: VerificationKind[]) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  if (await VerificationRequest.exists({ companyId: ctx.companyId, employeeId: emp._id, status: { $in: OPEN } })) {
    throw new AppError('CONFLICT', 'Already asked. Wait for them to finish, or cancel it first.');
  }
  const q = await quota(ctx);
  if (q.used >= q.limit) {
    throw new AppError('PLAN_LIMIT', `You've used all ${q.limit} checks for this month.`, { used: q.used, limit: q.limit, extraPricePaise: q.extraPricePaise });
  }
  const company = (await Company.findById(ctx.companyId).lean())!;
  const r = await VerificationRequest.create({
    companyId: ctx.companyId,
    employeeId: emp._id,
    kinds: KIND_ORDER.filter((k) => kinds.includes(k)),
    requestedBy: ctx.userId,
    month: todayIn(company.timezone).slice(0, 7),
  });
  await VerificationCheck.insertMany(r.kinds.map((kind) => ({ companyId: ctx.companyId, requestId: r._id, employeeId: emp._id, kind })));
  await Employee.updateOne({ _id: emp._id, companyId: ctx.companyId }, { $set: { verification: { status: 'asked', at: new Date() } } });
  await notifyEmployee(
    ctx.companyId,
    emp._id,
    {
      template: 'verification_request',
      title: `${company.name} asked you to verify your documents`,
      titleHi: `${company.name} ने आपके दस्तावेज़ जाँचने को कहा है`,
      body: 'It takes about 3 minutes in the app: Aadhaar OTP, PAN and bank account.',
      bodyHi: 'ऐप में लगभग 3 मिनट लगेंगे: आधार OTP, PAN और बैंक खाता।',
      data: { type: 'verification' },
      whatsapp: { template: 'verification_request', params: [emp.name, company.name] },
    },
    // Staff without the app hear on WhatsApp (with the app link); others get a push.
    { whatsapp: !emp.userId },
  );
  await audit(ctx, { action: 'verification.request', entity: 'employee', entityId: emp._id, after: { kinds: r.kinds } });
  return ownerView(ctx, employeeId);
}

/** Take back a request nobody finished. It no longer counts against the month. */
export async function cancelRequest(ctx: Ctx, employeeId: string) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  const r = await VerificationRequest.findOne({ companyId: ctx.companyId, employeeId: emp._id, status: { $in: OPEN } });
  if (!r) throw notFound('Request');
  r.status = 'cancelled';
  await r.save();
  await Employee.updateOne({ _id: emp._id, companyId: ctx.companyId }, { $set: { verification: { status: 'none', at: new Date() } } });
  await audit(ctx, { action: 'verification.cancel', entity: 'employee', entityId: emp._id });
  return ownerView(ctx, employeeId);
}

async function loadCheckForOwner(ctx: Ctx, checkId: string) {
  if (!Types.ObjectId.isValid(checkId)) throw notFound('Check');
  const c = await VerificationCheck.findOne({ _id: checkId, companyId: ctx.companyId });
  if (!c) throw notFound('Check');
  await assertEmployeeInScope(ctx, String(c.employeeId));
  return c;
}

/** The owner looked at a name that doesn't quite match ("Rajesh" vs "Rajesh Kumar") and it's fine. */
export async function acceptMismatch(ctx: Ctx, checkId: string, reason: string) {
  const c = await loadCheckForOwner(ctx, checkId);
  if (c.status !== 'mismatch') throw new AppError('CONFLICT', 'Only a name mismatch can be accepted');
  c.override = { by: ctx.userId ?? undefined, reason, at: new Date() };
  await c.save();
  await audit(ctx, { action: 'verification.accept', entity: 'employee', entityId: c.employeeId, after: { kind: c.kind, reason, nameOnRecord: c.nameOnRecord } });
  await refresh(ctx.companyId, c.requestId, { notify: false });
  return ownerView(ctx, String(c.employeeId));
}

/** Send one check back to the staff member to do again (wrong number, other account…). */
export async function askAgain(ctx: Ctx, checkId: string) {
  const c = await loadCheckForOwner(ctx, checkId);
  if (c.status === 'verified' || c.override) throw new AppError('CONFLICT', 'This check is already fine');
  Object.assign(c, { status: 'waiting', nameOnRecord: null, matchScore: null, detailsEnc: null, last4: null, providerRef: null, checkedAt: null });
  await c.save();
  await VerificationRequest.updateOne({ _id: c.requestId, companyId: ctx.companyId }, { $set: { status: 'in_progress', doneAt: null } });
  await refresh(ctx.companyId, c.requestId, { notify: false });
  const label = { aadhaar: ['Aadhaar', 'आधार'], pan: ['PAN', 'PAN'], bank: ['bank account', 'बैंक खाता'] }[c.kind as VerificationKind];
  await notifyEmployee(ctx.companyId, c.employeeId, {
    template: 'verification_again',
    title: `Please check your ${label[0]} again`,
    titleHi: `कृपया अपना ${label[1]} फिर से जाँचें`,
    body: 'Your employer asked you to do this step again in the app.',
    bodyHi: 'आपके मालिक ने ऐप में यह क़दम फिर से करने को कहा है।',
    data: { type: 'verification' },
  });
  await audit(ctx, { action: 'verification.ask_again', entity: 'employee', entityId: c.employeeId, after: { kind: c.kind } });
  return ownerView(ctx, String(c.employeeId));
}

/** Recompute the request and the staff list badge after a check changes; tell the owner once everything is done. */
async function refresh(companyId: Types.ObjectId, requestId: Types.ObjectId, opts: { notify: boolean }) {
  const r = await VerificationRequest.findOne({ _id: requestId, companyId });
  if (!r || r.status === 'cancelled') return;
  const checks = await VerificationCheck.find({ companyId, requestId }).lean();
  const done = checks.every(terminal);
  const allGood = done && checks.every(settled);
  const badge = !r.consent?.acceptedAt ? 'asked' : done ? (allGood ? 'verified' : 'needs_attention') : 'in_progress';
  const wasDone = r.status === 'done';
  r.status = done ? 'done' : r.consent?.acceptedAt ? 'in_progress' : 'asked';
  r.doneAt = done ? (r.doneAt ?? new Date()) : null;
  await r.save();
  await Employee.updateOne({ _id: r.employeeId, companyId }, { $set: { verification: { status: badge, at: new Date() } } });
  if (done && !wasDone && opts.notify) {
    const emp = (await Employee.findOne({ _id: r.employeeId, companyId }).select('name').lean())!;
    const attention = checks.filter((c) => !settled(c)).length;
    await notifyOwners(
      companyId,
      {
        template: 'verification_done',
        title: attention ? `${emp.name}'s documents: ${attention} need a look` : `${emp.name}'s documents are verified`,
        titleHi: attention ? `${emp.name} के दस्तावेज़: ${attention} पर ध्यान दें` : `${emp.name} के दस्तावेज़ सही निकले`,
        body: attention ? 'Open their profile to see what didn’t match.' : 'Aadhaar, PAN and bank account checked against government records.',
        bodyHi: attention ? 'क्या नहीं मिला, उनकी प्रोफ़ाइल में देखें।' : 'आधार, PAN और बैंक खाता सरकारी रिकॉर्ड से जाँचे गए।',
        data: { type: 'verification', employeeId: String(r.employeeId) },
      },
      { includeManagers: false },
    );
  }
}

// ---------------------------------------------------------------- staff

async function myOpen(ctx: Ctx) {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Staff only');
  const r = await VerificationRequest.findOne({ companyId: ctx.companyId, employeeId: ctx.employeeId, status: { $ne: 'cancelled' } }).sort({ createdAt: -1 });
  if (!r) throw notFound('Request');
  return r;
}

/** Staff: what the owner asked for, whether they agreed, and how each step went. */
export async function myVerification(ctx: Ctx) {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Staff only');
  const r = await VerificationRequest.findOne({ companyId: ctx.companyId, employeeId: ctx.employeeId, status: { $ne: 'cancelled' } }).sort({ createdAt: -1 }).lean();
  const company = (await Company.findById(ctx.companyId).select('name').lean())!;
  const emp = (await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId }).select('bankDetailsEnc').lean())!;
  let savedBank: { last4: string; ifsc: string } | null = null;
  if (emp.bankDetailsEnc) {
    try {
      const b = JSON.parse(decryptField(emp.bankDetailsEnc));
      if (b.accountNumber && b.ifsc) savedBank = { last4: String(b.accountNumber).slice(-4), ifsc: b.ifsc };
    } catch {
      savedBank = null;
    }
  }
  const checks = r ? await VerificationCheck.find({ companyId: ctx.companyId, requestId: r._id }).lean() : [];
  return {
    businessName: company.name,
    request: r ? requestView(r) : null,
    checks: order(checks).map((c) => checkView(c, false)),
    consentText: CONSENT_TEXT,
    savedBank,
  };
}

export async function giveConsent(ctx: Ctx) {
  const r = await myOpen(ctx);
  if (!OPEN.includes(r.status as (typeof OPEN)[number])) throw new AppError('CONFLICT', 'Nothing to agree to');
  if (!r.consent?.acceptedAt) {
    r.consent = { textVersion: CONSENT_VERSION, acceptedAt: new Date(), userId: ctx.userId ?? undefined, by: 'staff' };
    await r.save();
    await audit(ctx, { action: 'verification.consent', entity: 'employee', entityId: r.employeeId, after: { version: CONSENT_VERSION } });
  }
  await refresh(ctx.companyId, r._id, { notify: false });
  return myVerification(ctx);
}

async function myCheck(ctx: Ctx, kind: VerificationKind) {
  const r = await myOpen(ctx);
  if (!OPEN.includes(r.status as (typeof OPEN)[number]) && r.status !== 'done') throw new AppError('CONFLICT', 'Nothing to check');
  if (!r.consent?.acceptedAt) throw new AppError('FORBIDDEN', 'Please agree first');
  const c = await VerificationCheck.findOne({ companyId: ctx.companyId, requestId: r._id, kind });
  if (!c) throw new AppError('VALIDATION_ERROR', 'Your employer didn’t ask for this one');
  if (c.status === 'verified' || c.override) throw new AppError('CONFLICT', 'Already verified');
  // "Not found" or a name mismatch can be tried again (a typo, another account), a few times.
  if ((c.attempts ?? 0) >= MAX_ATTEMPTS) throw new AppError('RATE_LIMITED', 'Too many tries. Ask your employer to help.');
  return c;
}

/** Turn what the record says into a result: not found, name doesn't match, or verified. */
async function finish(ctx: Ctx, c: any, rec: VerifyRecord, providerName: string) {
  const emp = (await Employee.findOne({ _id: c.employeeId, companyId: ctx.companyId }).select('name').lean())!;
  const min = await getConfig<number>('verification.nameMatchMin', ctx.companyId);
  const score = rec.nameOnRecord ? nameMatch(emp.name, rec.nameOnRecord) : null;
  c.status = !rec.found ? 'not_found' : score === null || score >= min ? 'verified' : 'mismatch';
  Object.assign(c, {
    nameOnRecord: rec.nameOnRecord,
    matchScore: score,
    detailsEnc: rec.details && Object.keys(rec.details).length ? encryptField(JSON.stringify(rec.details)) : null,
    provider: providerName,
    providerRef: rec.providerRef,
    costPaise: (c.costPaise ?? 0) + rec.costPaise,
    checkedAt: new Date(),
  });
  await c.save();
  await audit(ctx, { action: 'verification.check', entity: 'employee', entityId: c.employeeId, after: { kind: c.kind, status: c.status, last4: c.last4 } });
  await refresh(ctx.companyId, c.requestId, { notify: true });
}

/** The provider couldn't answer (down, timeout): staff can try again. */
async function failed(ctx: Ctx, c: any, err: unknown) {
  logger.warn({ err, kind: c.kind }, 'verification provider call failed');
  c.status = 'failed';
  await c.save();
  await refresh(ctx.companyId, c.requestId, { notify: false });
}

const AADHAAR_RE = /^[2-9]\d{11}$/;
const PAN_RE = /^[A-Z]{5}\d{4}[A-Z]$/;
const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;

export async function aadhaarSendOtp(ctx: Ctx, aadhaarRaw: string) {
  const aadhaar = aadhaarRaw.replace(/\s/g, '');
  if (!AADHAAR_RE.test(aadhaar)) throw new AppError('VALIDATION_ERROR', 'Enter the 12-digit Aadhaar number');
  const c = await myCheck(ctx, 'aadhaar');
  const p = await provider('verification');
  c.attempts = (c.attempts ?? 0) + 1;
  try {
    const { ref } = await p.aadhaarSendOtp({ aadhaar });
    // Only the last 4 digits are ever kept (UIDAI rule).
    Object.assign(c, { status: 'otp_sent', providerRef: ref, last4: aadhaar.slice(-4), provider: p.name });
    await c.save();
  } catch (err) {
    await failed(ctx, c, err);
  }
  return myVerification(ctx);
}

export async function aadhaarVerifyOtp(ctx: Ctx, otp: string) {
  const c = await myCheck(ctx, 'aadhaar');
  if (c.status !== 'otp_sent' || !c.providerRef) throw new AppError('CONFLICT', 'Ask for the OTP first');
  const p = await provider('verification');
  let rec: VerifyRecord;
  try {
    rec = await p.aadhaarVerifyOtp({ ref: c.providerRef, otp });
  } catch (err: any) {
    if (String(err?.message).includes('OTP_INVALID') || err?.status === 400) throw new AppError('OTP_INVALID', 'That OTP is wrong. Check the SMS and try again.');
    await failed(ctx, c, err);
    return myVerification(ctx);
  }
  await finish(ctx, c, rec, p.name);
  return myVerification(ctx);
}

export async function verifyPan(ctx: Ctx, panRaw: string) {
  const pan = panRaw.replace(/\s/g, '').toUpperCase();
  if (!PAN_RE.test(pan)) throw new AppError('VALIDATION_ERROR', 'Enter the 10-character PAN, like ABCDE1234F');
  const c = await myCheck(ctx, 'pan');
  const emp = (await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId }))!;
  const p = await provider('verification');
  c.attempts = (c.attempts ?? 0) + 1;
  c.last4 = pan.slice(-4);
  try {
    const rec = await p.verifyPan({ pan, name: emp.name });
    await finish(ctx, c, rec, p.name);
    // A verified PAN fills the profile's PAN (shown on salary slips) if it was empty.
    if (c.status === 'verified' && !emp.panEnc) await Employee.updateOne({ _id: emp._id, companyId: ctx.companyId }, { $set: { panEnc: encryptField(pan) } });
  } catch (err) {
    await failed(ctx, c, err);
  }
  return myVerification(ctx);
}

/** ₹1 test on the salary account: the one in their profile, or a new one they type (which then becomes their salary account). */
export async function verifyBank(ctx: Ctx, input: { accountNumber?: string; ifsc?: string }) {
  const c = await myCheck(ctx, 'bank');
  const emp = (await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId }))!;
  let accountNumber = input.accountNumber?.replace(/\s/g, '') ?? '';
  let ifsc = input.ifsc?.replace(/\s/g, '').toUpperCase() ?? '';
  const typed = !!accountNumber;
  if (!typed && emp.bankDetailsEnc) {
    const saved = JSON.parse(decryptField(emp.bankDetailsEnc));
    accountNumber = saved.accountNumber ?? '';
    ifsc = saved.ifsc ?? '';
  }
  if (!/^\d{9,18}$/.test(accountNumber)) throw new AppError('VALIDATION_ERROR', 'Enter the bank account number');
  if (!IFSC_RE.test(ifsc)) throw new AppError('VALIDATION_ERROR', 'Enter the 11-character IFSC, like SBIN0001234');
  const p = await provider('verification');
  c.attempts = (c.attempts ?? 0) + 1;
  c.last4 = accountNumber.slice(-4);
  try {
    const rec = await p.verifyBank({ accountNumber, ifsc, name: emp.name, phone: emp.phone });
    await finish(ctx, c, rec, p.name);
    // Only an account in their own name becomes the salary account.
    if (c.status === 'verified' && typed) await setBank(ctx, emp._id, { holderName: rec.nameOnRecord ?? emp.name, accountNumber, ifsc });
  } catch (err) {
    await failed(ctx, c, err);
  }
  return myVerification(ctx);
}
