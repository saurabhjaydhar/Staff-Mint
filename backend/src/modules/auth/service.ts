import { Types } from 'mongoose';
import { env } from '../../config/env.js';
import { AppError } from '../../lib/errors.js';
import { normalizePhone } from '../../lib/phone.js';
import { randomDigits, randomToken, sha256, safeEqual } from '../../lib/crypto.js';
import { signAccessToken } from '../../lib/jwt.js';
import { OtpRequest, RefreshToken, User, Employee, Membership, type MembershipDoc, type UserDoc } from '../../models/index.js';
import { activate, activeMemberships, attachStaffMemberships, bindDevice, defaultMembership, deviceAllowed, ensureLegacyMembership, membershipViews } from './memberships.js';
import { provider } from '../../providers/registry.js';
import { logger } from '../../lib/logger.js';

const MAX_OTP_PER_HOUR = 5;
const MIN_OTP_GAP_SEC = 30;
const MAX_VERIFY_ATTEMPTS = 5;

const otpHash = (phone: string, code: string) => sha256(`${phone}:${code}:${env.JWT_REFRESH_SECRET}`);

export function parsePhone(raw: string, country = env.DEFAULT_COUNTRY): string {
  const phone = normalizePhone(raw, country);
  if (!phone) throw new AppError('VALIDATION_ERROR', 'Enter a valid mobile number');
  return phone;
}

export async function requestOtp(rawPhone: string, channel: 'sms' | 'whatsapp', ip?: string) {
  const phone = parsePhone(rawPhone);
  const hourAgo = new Date(Date.now() - 3600_000);
  const recent = await OtpRequest.find({ phone, createdAt: { $gte: hourAgo } }).sort({ createdAt: -1 }).lean();
  if (recent.length >= MAX_OTP_PER_HOUR) throw new AppError('RATE_LIMITED', 'Too many OTP requests. Try again in an hour.');
  if (recent[0] && Date.now() - recent[0].createdAt.getTime() < MIN_OTP_GAP_SEC * 1000) {
    throw new AppError('RATE_LIMITED', `Please wait ${MIN_OTP_GAP_SEC} seconds before requesting another OTP`);
  }
  const otp = await provider('otp');
  const code = otp.name === 'mock' ? env.OTP_MOCK_CODE : randomDigits(6);
  let sent: { providerRef?: string; devCode?: string };
  if (channel === 'whatsapp') {
    const wa = await provider('messaging');
    const r = await wa.sendTemplate(phone, 'otp_code', [code], { language: 'en' });
    sent = { providerRef: r.providerMsgId, devCode: wa.name === 'mock' ? code : undefined };
  } else {
    sent = await otp.send(phone, code, channel);
  }
  const doc = await OtpRequest.create({
    phone,
    codeHash: otpHash(phone, code),
    channel,
    provider: otp.name,
    providerRef: sent.providerRef,
    expiresAt: new Date(Date.now() + env.OTP_TTL_SEC * 1000),
    ip,
  });
  return { requestId: String(doc._id), expiresInSec: env.OTP_TTL_SEC, ...(sent.devCode ? { devCode: sent.devCode } : {}) };
}

export async function consumeOtp(phone: string, code: string) {
  const req = await OtpRequest.findOne({ phone, consumedAt: null, expiresAt: { $gt: new Date() } }).sort({ createdAt: -1 });
  if (!req) throw new AppError('OTP_INVALID', 'OTP expired. Request a new one.');
  if (req.attempts >= MAX_VERIFY_ATTEMPTS) throw new AppError('RATE_LIMITED', 'Too many wrong attempts. Request a new OTP.');
  if (!safeEqual(req.codeHash, otpHash(phone, code))) {
    req.attempts += 1;
    await req.save();
    throw new AppError('OTP_INVALID', 'Wrong OTP');
  }
  req.consumedAt = new Date();
  await req.save();
}

/** Find or create the person for a phone, with their business memberships up to date. */
async function resolveUser(phone: string): Promise<UserDoc> {
  let user = await User.findOne({ phone, deletedAt: null });
  if (!user) {
    const emp = await Employee.findOne({ phone, status: 'active', deletedAt: null }).setOptions({ skipTenant: true }).sort({ createdAt: -1 }).lean();
    user = await User.create({ phone, name: emp?.name ?? '', role: 'owner', companyId: null, language: emp?.language ?? 'hi' });
  }
  await ensureLegacyMembership(user);
  await attachStaffMemberships(user);
  return user;
}

/** Login result: the session opens in the most recent business; the app asks when there is more than one. */
async function sessionResult(user: UserDoc, membership: MembershipDoc | null, list: MembershipDoc[], tokens: { accessToken: string; refreshToken: string }) {
  return {
    ...tokens,
    user: userView(user),
    needsCompanySetup: !membership,
    activeMembershipId: membership ? String(membership._id) : null,
    memberships: await membershipViews(list),
    needsAccountChoice: list.length > 1,
  };
}

export async function verifyOtp(input: { phone: string; code: string; deviceId: string; deviceName?: string }) {
  const phone = parsePhone(input.phone);
  await consumeOtp(phone, input.code);
  const user = await resolveUser(phone);
  const { list, chosen } = await defaultMembership(user, input.deviceId);
  if (chosen) await bindDevice(chosen, input.deviceId);
  user.lastLoginAt = new Date();
  await activate(user, chosen);
  const tokens = await issueTokens(user, input.deviceId, undefined, chosen);
  return sessionResult(user, chosen, list, tokens);
}

/** Open another of the person's businesses on this device. */
export async function switchMembership(userId: Types.ObjectId | string, input: { membershipId: string; deviceId: string; refreshToken?: string }) {
  const user = await User.findOne({ _id: userId, deletedAt: null });
  if (!user) throw new AppError('UNAUTHORIZED', 'User not found');
  const m = await Membership.findOne({ _id: input.membershipId, userId: user._id, status: 'active' });
  if (!m) throw new AppError('NOT_FOUND', 'This account is not available any more');
  if (!deviceAllowed(m, input.deviceId)) {
    throw new AppError('DEVICE_NOT_BOUND', 'This staff account is linked to another phone. Ask your employer to reset your device.');
  }
  await bindDevice(m, input.deviceId);
  await activate(user, m);
  if (input.refreshToken) await RefreshToken.updateOne({ tokenHash: sha256(input.refreshToken), userId: user._id }, { revokedAt: new Date() });
  const tokens = await issueTokens(user, input.deviceId, undefined, m);
  return sessionResult(user, m, await activeMemberships(user._id), tokens);
}

export function userView(u: any) {
  return {
    id: String(u._id),
    phone: u.phone,
    name: u.name ?? '',
    email: u.email ?? null,
    role: u.role,
    companyId: u.companyId ? String(u.companyId) : null,
    employeeId: u.employeeId ? String(u.employeeId) : null,
    language: u.language ?? 'hi',
  };
}

export async function issueTokens(
  user: { _id: Types.ObjectId; role: string; companyId?: Types.ObjectId | null; employeeId?: Types.ObjectId | null },
  deviceId?: string,
  family?: string,
  membership?: { _id: Types.ObjectId; role: string; companyId: Types.ObjectId; employeeId?: Types.ObjectId | null } | null,
) {
  const accessToken = signAccessToken({
    sub: String(user._id),
    role: membership?.role ?? user.role,
    cid: membership ? String(membership.companyId) : user.companyId ? String(user.companyId) : null,
    eid: membership?.employeeId ? String(membership.employeeId) : membership ? null : user.employeeId ? String(user.employeeId) : null,
    mid: membership ? String(membership._id) : null,
  });
  const refreshToken = randomToken(48);
  await RefreshToken.create({
    userId: user._id,
    tokenHash: sha256(refreshToken),
    family: family ?? randomToken(12),
    membershipId: membership?._id ?? null,
    deviceId,
    expiresAt: new Date(Date.now() + env.JWT_REFRESH_TTL_DAYS * 86400_000),
  });
  return { accessToken, refreshToken };
}

export async function refresh(refreshToken: string) {
  const doc = await RefreshToken.findOne({ tokenHash: sha256(refreshToken) });
  if (!doc || doc.expiresAt < new Date()) throw new AppError('UNAUTHORIZED', 'Session expired. Please log in again.');
  if (doc.revokedAt) {
    // Reuse of a rotated token → likely theft. Kill the whole family.
    await RefreshToken.updateMany({ family: doc.family }, { revokedAt: new Date() });
    logger.warn({ userId: doc.userId }, 'Refresh token reuse detected; family revoked');
    throw new AppError('UNAUTHORIZED', 'Session expired. Please log in again.');
  }
  const user = await User.findById(doc.userId);
  if (!user || user.deletedAt) throw new AppError('UNAUTHORIZED', 'User not found');
  await ensureLegacyMembership(user);
  // Stay in the same business on this device while that access lasts.
  let m = doc.membershipId ? await Membership.findOne({ _id: doc.membershipId, userId: user._id, status: 'active' }) : null;
  if (!m && !doc.membershipId && user.companyId) m = await Membership.findOne({ userId: user._id, companyId: user.companyId, status: 'active' });
  if (!m) {
    // No business yet ("Check again" on the waiting screen) or access was removed: pick what is available now.
    await attachStaffMemberships(user);
    m = (await defaultMembership(user, doc.deviceId).catch(() => ({ chosen: null }))).chosen;
    if (m) await bindDevice(m, doc.deviceId);
    await activate(user, m);
  }
  const tokens = await issueTokens(user, doc.deviceId ?? undefined, doc.family, m);
  doc.revokedAt = new Date();
  doc.replacedBy = sha256(tokens.refreshToken);
  await doc.save();
  return tokens;
}

export async function logout(refreshToken: string) {
  await RefreshToken.updateOne({ tokenHash: sha256(refreshToken) }, { revokedAt: new Date() });
}

export async function revokeAllForUser(userId: Types.ObjectId) {
  await RefreshToken.updateMany({ userId, revokedAt: null }, { revokedAt: new Date() });
}
