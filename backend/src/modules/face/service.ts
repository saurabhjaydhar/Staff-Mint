import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import type { Ctx } from '../../lib/context.js';
import { env } from '../../config/env.js';
import { Employee } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import { audit } from '../audit/service.js';
import { assertEmployeeInScope } from '../employees/service.js';
import { notifyEmployee, notifyOwners } from '../notifications/service.js';

export type FaceResult = 'match' | 'unsure' | 'mismatch' | 'no_face' | 'many_faces' | 'error';

const decode = (b64: string) => {
  const buf = Buffer.from(b64.replace(/^data:image\/\w+;base64,/, ''), 'base64');
  if (!buf.length) throw new AppError('VALIDATION_ERROR', 'Photo is empty');
  if (buf.length > 2_000_000) throw new AppError('VALIDATION_ERROR', 'Photo too large (max 2 MB)');
  return buf;
};

/** Similarity → decision, using the configured thresholds. */
export function classify(similarity: number | null, faces: number): FaceResult {
  if (faces === 0 || similarity === null) return 'no_face';
  if (faces > 1) return 'many_faces';
  if (similarity >= env.FACE_MATCH_THRESHOLD) return 'match';
  if (similarity >= env.FACE_UNSURE_THRESHOLD) return 'unsure';
  return 'mismatch';
}

async function removeRef(key: string | null | undefined) {
  if (!key) return;
  await (await provider('storage')).delete(key).catch(() => undefined);
}

/** Staff member enrols (or re-enrols) their reference photo. Needs explicit consent each time. */
export async function enroll(ctx: Ctx, photoBase64: string) {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Only staff can set up face check');
  const emp = await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId });
  if (!emp) throw notFound('Employee');
  const buf = decode(photoBase64);
  // One clear face, checked with the same engine used at check-in.
  const probe = await (await provider('face')).compare(buf, buf);
  const r = classify(probe.similarity, probe.faces);
  if (r === 'no_face' || r === 'many_faces') {
    throw new AppError('FACE_NOT_CLEAR', r === 'no_face' ? 'No face found. Face the camera in good light.' : 'More than one face. Only you should be in the photo.', { reason: r });
  }
  const old = emp.face?.refKey;
  const key = `faces/${ctx.companyId}/${emp._id}-${Date.now()}.jpg`;
  await (await provider('storage')).put(key, buf, 'image/jpeg');
  const now = new Date();
  emp.face = { status: 'pending', refKey: key, consentAt: now, enrolledAt: now, approvedAt: null, approvedBy: null } as any;
  await emp.save();
  await removeRef(old);
  await audit(ctx, { action: 'employee.face.enroll', entity: 'employee', entityId: emp._id, after: { face: { status: 'pending', consentAt: now } } });
  await notifyOwners(ctx.companyId, {
    template: 'face_enrollment',
    title: 'Face photo to approve',
    titleHi: 'चेहरे की फ़ोटो मंज़ूर करें',
    body: `${emp.name} set up face check. Approve their photo in the app.`,
    bodyHi: `${emp.name} ने चेहरा पहचान सेट किया। ऐप में उनकी फ़ोटो मंज़ूर करें।`,
    data: { type: 'face_enrollment', employeeId: String(emp._id) },
  });
  return emp;
}

/** Staff member withdraws consent: the reference photo is deleted at once. */
export async function withdraw(ctx: Ctx) {
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Only staff can do this');
  const emp = await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId });
  if (!emp) throw notFound('Employee');
  await clearFace(emp);
  await audit(ctx, { action: 'employee.face.withdraw', entity: 'employee', entityId: emp._id });
  return emp;
}

export async function approve(ctx: Ctx, employeeId: string) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  if (emp.face?.status !== 'pending' || !emp.face.refKey) throw new AppError('CONFLICT', 'No face photo waiting for approval');
  emp.face.status = 'approved';
  emp.face.approvedAt = new Date();
  emp.face.approvedBy = ctx.userId ? new Types.ObjectId(String(ctx.userId)) : null;
  await emp.save();
  await audit(ctx, { action: 'employee.face.approve', entity: 'employee', entityId: emp._id });
  await notifyEmployee(ctx.companyId, emp._id, {
    template: 'face_approved',
    title: 'Face check is on',
    titleHi: 'चेहरा पहचान चालू',
    body: 'Your owner approved your face photo.',
    bodyHi: 'मालिक ने आपकी चेहरे की फ़ोटो मंज़ूर कर दी।',
    data: { type: 'face_approved' },
  });
  return emp;
}

/** Owner rejects or resets: the photo is deleted and the staff member is asked to enrol again. */
export async function reset(ctx: Ctx, employeeId: string) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  await clearFace(emp);
  await audit(ctx, { action: 'employee.face.reset', entity: 'employee', entityId: emp._id });
  return emp;
}

export async function clearFace(emp: any) {
  const key = emp.face?.refKey;
  emp.face = { status: 'none', refKey: null, consentAt: null, enrolledAt: null, approvedAt: null, approvedBy: null };
  await emp.save();
  await removeRef(key);
}

export async function faceView(emp: any) {
  const storage = await provider('storage');
  return {
    status: emp.face?.status ?? 'none',
    enrolledAt: emp.face?.enrolledAt ?? null,
    approvedAt: emp.face?.approvedAt ?? null,
    photoUrl: emp.face?.refKey ? await storage.signedUrl(emp.face.refKey, env.SIGNED_URL_TTL_SEC) : null,
  };
}

/** Compare a check-in selfie with the approved reference. Never throws: failures return `error`. */
export async function matchSelfie(emp: any, selfie: Buffer): Promise<{ result: FaceResult; similarity: number | null }> {
  try {
    const storage = await provider('storage');
    const ref = await storage.get(emp.face.refKey);
    if (!ref) return { result: 'error', similarity: null };
    const r = await (await provider('face')).compare(ref, selfie);
    return { result: classify(r.similarity, r.faces), similarity: r.similarity === null ? null : Math.round(r.similarity * 10) / 10 };
  } catch {
    return { result: 'error', similarity: null };
  }
}
