import { DateTime } from 'luxon';
import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { addDays, todayIn } from '../../lib/dates.js';
import { decryptBuffer, encryptBuffer, hmacSha256Hex, safeEqual } from '../../lib/crypto.js';
import type { Ctx } from '../../lib/context.js';
import { env } from '../../config/env.js';
import { Company, Employee, StaffDocument, VerificationRequest, type DocumentKind } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import { assertEmployeeInScope } from '../employees/service.js';
import { audit } from '../audit/service.js';
import { notifyEmployee, notifyOwners } from '../notifications/service.js';

export interface FileInput {
  /** Base64 (a data: prefix is fine). */
  data: string;
  mime: string;
}

export interface DocumentInput {
  kind: DocumentKind;
  label?: string | null;
  number?: string | null;
  expiresOn?: string | null;
  files: FileInput[];
}

const MAX_FILE_BYTES = 4 * 1024 * 1024;
/** All files of one upload together (the request body limit is 10 MB of base64). */
const MAX_TOTAL_BYTES = 7 * 1024 * 1024;
const MIMES: Record<string, { ext: string; magic: (b: Buffer) => boolean }> = {
  'image/jpeg': { ext: 'jpg', magic: (b) => b[0] === 0xff && b[1] === 0xd8 },
  'image/png': { ext: 'png', magic: (b) => b.subarray(0, 4).toString('latin1') === '\x89PNG' },
  'application/pdf': { ext: 'pdf', magic: (b) => b.subarray(0, 4).toString('latin1') === '%PDF' },
};
/** Documents that run out; the owner and the staff member hear 30 days before. */
export const EXPIRING_KINDS: DocumentKind[] = ['dl', 'passport', 'police'];
const REMIND_DAYS = 30;
const LINK_TTL_SEC = 300;

const KIND_NAME: Record<DocumentKind, [string, string]> = {
  aadhaar: ['Aadhaar', 'आधार'],
  pan: ['PAN', 'PAN'],
  dl: ['driving licence', 'ड्राइविंग लाइसेंस'],
  voter: ['voter ID', 'वोटर आईडी'],
  passport: ['passport', 'पासपोर्ट'],
  bank_proof: ['bank passbook', 'बैंक पासबुक'],
  address: ['address proof', 'पते का सबूत'],
  police: ['police verification', 'पुलिस वेरिफ़िकेशन'],
  experience: ['experience letter', 'अनुभव पत्र'],
  other: ['document', 'दस्तावेज़'],
};
const nameOf = (d: { kind: string; label?: string | null }, lang: 'en' | 'hi' = 'en') =>
  d.kind === 'other' && d.label ? d.label : KIND_NAME[d.kind as DocumentKind][lang === 'hi' ? 1 : 0];

function decodeFile(f: FileInput): Buffer {
  const spec = MIMES[f.mime];
  if (!spec) throw new AppError('VALIDATION_ERROR', 'Only photos (JPG, PNG) and PDF files');
  const buf = Buffer.from(f.data.replace(/^data:[\w/+.-]+;base64,/, ''), 'base64');
  if (!buf.length) throw new AppError('VALIDATION_ERROR', 'File is empty');
  if (buf.length > MAX_FILE_BYTES) throw new AppError('VALIDATION_ERROR', 'File too large (max 4 MB)');
  if (!spec.magic(buf)) throw new AppError('VALIDATION_ERROR', 'The file is not a photo or PDF');
  return buf;
}

/** Encrypts and stores one file; returns where it went. */
export async function store(companyId: Types.ObjectId, employeeId: Types.ObjectId, f: FileInput, tag: string) {
  const buf = decodeFile(f);
  const key = `documents/${companyId}/${employeeId}/${tag}-${new Types.ObjectId()}.${MIMES[f.mime].ext}.enc`;
  await (await provider('storage')).put(key, encryptBuffer(buf), 'application/octet-stream');
  return { key, mime: f.mime, size: buf.length };
}

async function removeFiles(keys: (string | null | undefined)[]) {
  const storage = await provider('storage');
  for (const k of keys) if (k) await storage.delete(k).catch(() => undefined);
}

/** Only the last 4 characters of a document number are kept (never a full Aadhaar). */
function last4(kind: DocumentKind, number?: string | null) {
  const n = (number ?? '').replace(/[\s-]/g, '').toUpperCase();
  if (!n) return null;
  if (kind === 'aadhaar' && !/^[\dX]{4,12}$/.test(n)) throw new AppError('VALIDATION_ERROR', 'Aadhaar number should be digits');
  return n.slice(-4);
}

function expiry(expiresOn: string | null | undefined, today: string) {
  if (!expiresOn) return null;
  if (expiresOn < today) return 'expired';
  if (expiresOn <= addDays(today, REMIND_DAYS)) return 'soon';
  return 'ok';
}

function view(d: any, today: string) {
  return {
    id: String(d._id),
    kind: d.kind as DocumentKind,
    label: d.label ?? null,
    numberLast4: d.numberLast4 ?? null,
    files: (d.files ?? []).map((f: any) => ({ mime: f.mime, size: f.size ?? null })),
    expiresOn: d.expiresOn ?? null,
    expiry: expiry(d.expiresOn, today),
    addedBy: d.consent?.by === 'owner_on_behalf' ? 'owner' : 'staff',
    hasSlip: !!d.consent?.slipKey,
    createdAt: d.createdAt,
  };
}

async function todayFor(companyId: Types.ObjectId) {
  return todayIn((await Company.findById(companyId).select('timezone').lean())!.timezone);
}

function validate(input: DocumentInput, today: string) {
  if (!input.files.length) throw new AppError('VALIDATION_ERROR', 'Add a photo or PDF of the document');
  if (input.kind === 'other' && !input.label?.trim()) throw new AppError('VALIDATION_ERROR', 'Say what the document is');
  const total = input.files.reduce((n, f) => n + Math.floor((f.data.length * 3) / 4), 0);
  if (total > MAX_TOTAL_BYTES) throw new AppError('VALIDATION_ERROR', 'Files too large together (max 7 MB)');
  if (input.expiresOn && input.expiresOn < addDays(today, -3650)) throw new AppError('VALIDATION_ERROR', 'Check the expiry date');
}

/**
 * Has this person agreed to the business keeping their documents? Staff who used the app themselves have
 * (each upload, or the documents check consent); for others the owner shows a signed slip once.
 */
async function agreementOnFile(companyId: Types.ObjectId, employeeId: Types.ObjectId) {
  const [doc, check] = await Promise.all([
    StaffDocument.exists({ companyId, employeeId, $or: [{ 'consent.by': 'staff' }, { 'consent.slipKey': { $ne: null } }] }),
    VerificationRequest.exists({ companyId, employeeId, 'consent.acceptedAt': { $ne: null } }),
  ]);
  return !!(doc || check);
}

async function create(ctx: Ctx, emp: { _id: Types.ObjectId; name: string }, input: DocumentInput, consent: { by: 'staff' | 'owner_on_behalf'; slip?: FileInput | null }) {
  const today = await todayFor(ctx.companyId);
  validate(input, today);
  const numberLast4 = last4(input.kind, input.number);
  const files = [];
  for (const [i, f] of input.files.entries()) files.push(await store(ctx.companyId, emp._id, f, `${input.kind}-${i + 1}`));
  const slip = consent.slip ? await store(ctx.companyId, emp._id, consent.slip, 'consent-slip') : null;
  const d = await StaffDocument.create({
    companyId: ctx.companyId,
    employeeId: emp._id,
    kind: input.kind,
    label: input.kind === 'other' ? input.label!.trim() : null,
    numberLast4,
    files,
    expiresOn: input.expiresOn ?? null,
    uploadedBy: ctx.userId,
    consent: { by: consent.by, at: new Date(), slipKey: slip?.key ?? null, slipMime: slip?.mime ?? null },
  });
  await audit(ctx, {
    action: 'document.add',
    entity: 'employee',
    entityId: emp._id,
    after: { kind: d.kind, label: d.label, pages: files.length, expiresOn: d.expiresOn, by: consent.by, slip: !!slip },
  });
  return view(d.toObject(), today);
}

// ---------------------------------------------------------------- owner

export async function listForEmployee(ctx: Ctx, employeeId: string) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  const today = await todayFor(ctx.companyId);
  const docs = await StaffDocument.find({ companyId: ctx.companyId, employeeId: emp._id }).sort({ createdAt: -1 }).lean();
  return { documents: docs.map((d) => view(d, today)), agreementOnFile: await agreementOnFile(ctx.companyId, emp._id) };
}

/** The owner adds a document for someone (e.g. staff without a smartphone). They must have agreed. */
export async function addForEmployee(ctx: Ctx, employeeId: string, input: DocumentInput & { staffAgreed: boolean; slip?: FileInput | null }) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  if (!input.staffAgreed) throw new AppError('CONSENT_REQUIRED', 'Tick that they agreed to you keeping this document');
  if (!input.slip && !(await agreementOnFile(ctx.companyId, emp._id))) {
    throw new AppError('CONSENT_REQUIRED', 'Add a photo of the consent slip they signed (needed the first time)');
  }
  return create(ctx, emp, input, { by: 'owner_on_behalf', slip: input.slip });
}

async function loadDoc(ctx: Ctx, id: string) {
  if (!Types.ObjectId.isValid(id)) throw notFound('Document');
  const d = await StaffDocument.findOne({ _id: id, companyId: ctx.companyId });
  if (!d) throw notFound('Document');
  if (ctx.role === 'owner') await assertEmployeeInScope(ctx, String(d.employeeId));
  else if (!ctx.employeeId || String(d.employeeId) !== String(ctx.employeeId)) throw notFound('Document');
  return d;
}

/** Owner fixes the expiry date or the name of an "other" document. */
export async function updateDocument(ctx: Ctx, id: string, patch: { expiresOn?: string | null; label?: string | null }) {
  const d = await loadDoc(ctx, id);
  const before = { expiresOn: d.expiresOn, label: d.label };
  if (patch.expiresOn !== undefined) d.expiresOn = patch.expiresOn;
  if (patch.label !== undefined && d.kind === 'other' && patch.label?.trim()) d.label = patch.label.trim();
  await d.save();
  await audit(ctx, { action: 'document.update', entity: 'employee', entityId: d.employeeId, before: { kind: d.kind, ...before }, after: { kind: d.kind, expiresOn: d.expiresOn, label: d.label } });
  return view(d.toObject(), await todayFor(ctx.companyId));
}

/** Owners can remove any document; staff only the ones they added themselves. */
export async function removeDocument(ctx: Ctx, id: string) {
  const d = await loadDoc(ctx, id);
  if (ctx.role !== 'owner' && d.consent?.by !== 'staff') throw new AppError('FORBIDDEN', 'Ask your employer to remove this document');
  await removeFiles([...d.files.map((f) => f.key), d.consent?.slipKey]);
  await StaffDocument.deleteOne({ _id: d._id, companyId: ctx.companyId });
  await audit(ctx, { action: 'document.delete', entity: 'employee', entityId: d.employeeId, before: { kind: d.kind, label: d.label } });
  return { ok: true };
}

// ---------------------------------------------------------------- opening files

const sign = (payload: string) => hmacSha256Hex(env.FILE_URL_SECRET, `doc:${payload}`);

export function link(key: string, mime: string) {
  const payload = Buffer.from(JSON.stringify({ k: key, m: mime, e: Math.floor(Date.now() / 1000) + LINK_TTL_SEC })).toString('base64url');
  return `${env.PUBLIC_BASE_URL}/doc-files/${payload}.${sign(payload)}`;
}

/** Short-lived links to the files; the opening is written to History ("Rakesh opened Raju's PAN"). */
export async function openDocument(ctx: Ctx, id: string) {
  const d = await loadDoc(ctx, id);
  await audit(ctx, { action: 'document.view', entity: 'employee', entityId: d.employeeId, after: { kind: d.kind, label: d.label } });
  return {
    files: d.files.map((f) => ({ url: link(f.key, f.mime), mime: f.mime })),
    slip: ctx.role === 'owner' && d.consent?.slipKey ? { url: link(d.consent.slipKey, d.consent.slipMime ?? 'image/jpeg'), mime: d.consent.slipMime ?? 'image/jpeg' } : null,
    expiresInSec: LINK_TTL_SEC,
  };
}

/** GET /doc-files/:token: checks the link, decrypts and sends the file. */
export async function readLinked(token: string) {
  const [payload, sig] = token.split('.');
  if (!payload || !sig || !safeEqual(sig, sign(payload))) throw new AppError('FORBIDDEN', 'Link expired or invalid');
  let p: { k: string; m: string; e: number };
  try {
    p = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
  } catch {
    throw new AppError('FORBIDDEN', 'Link expired or invalid');
  }
  if (!p.e || p.e < Date.now() / 1000 || !p.k.startsWith('documents/')) throw new AppError('FORBIDDEN', 'Link expired or invalid');
  const data = decryptBuffer(await (await provider('storage')).get(p.k));
  return { data, mime: MIMES[p.m] ? p.m : 'application/octet-stream' };
}

/** Kinds that carry the person's photo, for the selfie check. */
export const PHOTO_ID_KINDS: DocumentKind[] = ['aadhaar', 'pan', 'dl', 'voter', 'passport'];

/** The newest photo ID image they uploaded (decrypted), or null. PDFs don't count. */
export async function idPhotoFor(companyId: Types.ObjectId, employeeId: Types.ObjectId) {
  const d = await StaffDocument.findOne({ companyId, employeeId, kind: { $in: PHOTO_ID_KINDS }, 'files.mime': { $in: ['image/jpeg', 'image/png'] } })
    .sort({ createdAt: -1 })
    .lean();
  const f = d?.files.find((x) => x.mime !== 'application/pdf');
  if (!d || !f) return null;
  return { kind: d.kind as DocumentKind, data: decryptBuffer(await (await provider('storage')).get(f.key)) };
}

// ---------------------------------------------------------------- staff

export async function listMine(ctx: Ctx) {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Only staff have documents');
  const today = await todayFor(ctx.companyId);
  const docs = await StaffDocument.find({ companyId: ctx.companyId, employeeId: ctx.employeeId }).sort({ createdAt: -1 }).lean();
  return { documents: docs.map((d) => view(d, today)) };
}

export async function addMine(ctx: Ctx, input: DocumentInput) {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Only staff have documents');
  const emp = await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId }).select('name').lean();
  if (!emp) throw notFound('Employee');
  const out = await create(ctx, emp, input, { by: 'staff' });
  await notifyOwners(ctx.companyId, {
    template: 'document_added',
    title: `${emp.name} added their ${nameOf(input)}`,
    titleHi: `${emp.name} ने अपना ${nameOf(input, 'hi')} जोड़ा`,
    body: 'See it in their staff profile → Documents.',
    bodyHi: 'स्टाफ़ प्रोफ़ाइल → दस्तावेज़ में देखें।',
    data: { type: 'document', employeeId: String(emp._id) },
  }, { includeManagers: false });
  return out;
}

// ---------------------------------------------------------------- jobs

/** Daily: documents that run out within 30 days remind the owner and the staff member, once per expiry date. */
export async function remindExpiring(company: { _id: Types.ObjectId; timezone: string }, now = new Date()) {
  const today = todayIn(company.timezone, now);
  const due = await StaffDocument.find({
    companyId: company._id,
    expiresOn: { $ne: null, $lte: addDays(today, REMIND_DAYS) },
    $expr: { $ne: ['$remindedFor', '$expiresOn'] },
  }).limit(200);
  if (!due.length) return 0;
  const people = new Map(
    (await Employee.find({ companyId: company._id, _id: { $in: due.map((d) => d.employeeId) }, status: 'active' }).select('name').lean()).map((e) => [String(e._id), e]),
  );
  let sent = 0;
  for (const d of due) {
    const emp = people.get(String(d.employeeId));
    if (emp) {
      const gone = d.expiresOn! < today;
      const date = DateTime.fromISO(d.expiresOn!).toFormat('d LLL yyyy');
      const dateHi = DateTime.fromISO(d.expiresOn!).setLocale('hi').toFormat('d LLLL yyyy');
      await notifyOwners(company._id, {
        template: 'document_expiring',
        title: gone ? `${emp.name}'s ${nameOf(d)} has expired` : `${emp.name}'s ${nameOf(d)} expires on ${date}`,
        titleHi: gone ? `${emp.name} का ${nameOf(d, 'hi')} ख़त्म हो गया है` : `${emp.name} का ${nameOf(d, 'hi')} ${dateHi} को ख़त्म होगा`,
        body: 'Ask them for the new one.',
        bodyHi: 'उनसे नया माँग लें।',
        data: { type: 'document', employeeId: String(emp._id) },
      }, { includeManagers: false });
      await notifyEmployee(company._id, emp._id, {
        template: 'document_expiring',
        title: gone ? `Your ${nameOf(d)} has expired` : `Your ${nameOf(d)} expires on ${date}`,
        titleHi: gone ? `आपका ${nameOf(d, 'hi')} ख़त्म हो गया है` : `आपका ${nameOf(d, 'hi')} ${dateHi} को ख़त्म होगा`,
        body: 'Add the new one in the app: Profile → My documents.',
        bodyHi: 'नया ऐप में जोड़ें: प्रोफ़ाइल → मेरे दस्तावेज़।',
        data: { type: 'document' },
      });
      sent++;
    }
    d.remindedFor = d.expiresOn;
    await d.save();
  }
  return sent;
}

/** Retention: documents (and their files) of people who left long enough ago. */
export async function purgeDocuments(companyId: Types.ObjectId, employeeIds: Types.ObjectId[]) {
  if (!employeeIds.length) return 0;
  const docs = await StaffDocument.find({ companyId, employeeId: { $in: employeeIds } }).lean();
  await removeFiles(docs.flatMap((d) => [...d.files.map((f) => f.key), d.consent?.slipKey]));
  await StaffDocument.deleteMany({ companyId, employeeId: { $in: employeeIds } });
  return docs.length;
}
