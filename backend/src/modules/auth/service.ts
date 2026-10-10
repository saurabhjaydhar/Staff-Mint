import { Types } from 'mongoose';
import { env } from '../../config/env.js';
import { AppError } from '../../lib/errors.js';
import { normalizePhone } from '../../lib/phone.js';
import { randomDigits, randomToken, sha256, safeEqual } from '../../lib/crypto.js';
import jwt from 'jsonwebtoken';
import { signAccessToken } from '../../lib/jwt.js';
import { getConfig } from '../config/service.js';
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
async function sessionResult(user: UserDoc, membership: MembershipDoc | null, list: MembershipDoc[], tokens: { accessToken: string; refreshToken: string }, deviceId?: string | null) {
  const views = await membershipViews(list, deviceId);
  return {
    ...tokens,
    user: userView(user),
    needsCompanySetup: !membership,
    activeMembershipId: membership ? String(membership._id) : null,
    memberships: views,
    needsAccountChoice: list.length > 1,
    /** Staff accounts locked to another phone; with no business open the app offers "Request device change". */
    blockedAccounts: views.filter((v) => v.lockedToOtherPhone),
  };
}

/**
 * Open [m] (or no business) on this device: bind the staff phone, mirror it on
 * the user, retire the device's previous token and issue new ones. Used by
 * switch, leave, close and restore.
 */
export async function openSession(user: UserDoc, m: MembershipDoc | null, deviceId?: string | null, oldRefreshToken?: string) {
  if (m) await bindDevice(m, deviceId);
  await activate(user, m);
  if (oldRefreshToken) await RefreshToken.updateOne({ tokenHash: sha256(oldRefreshToken), userId: user._id }, { revokedAt: new Date() });
  const tokens = await issueTokens(user, deviceId ?? undefined, undefined, m);
  return sessionResult(user, m, await activeMemberships(user._id), tokens, deviceId);
}

/** The device's current account if it is still open, else the best one left. */
export async function currentOrDefault(user: UserDoc, deviceId?: string | null, refreshToken?: string) {
  const doc = refreshToken ? await RefreshToken.findOne({ tokenHash: sha256(refreshToken), userId: user._id }).lean() : null;
  const cur = doc?.membershipId ? await Membership.findOne({ _id: doc.membershipId, userId: user._id, status: 'active' }) : null;
  return cur ?? (await defaultMembership(user, deviceId)).chosen;
}

export async function verifyOtp(input: { phone: string; code: string; deviceId: string; deviceName?: string }) {
  const phone = parsePhone(input.phone);
  await consumeOtp(phone, input.code);
  const existed = await User.findOne({ phone, deletedAt: null }).lean();
  // Recycled numbers: long unused, on a phone never seen before — ask "Is this you?" before opening anything.
  if (existed && (await looksRecycled(existed, input.deviceId))) {
    return {
      identityCheck: {
        token: signIdentityToken(String(existed._id), input.deviceId),
        maskedName: maskName(existed.name || ''),
      },
    };
  }
  const user = await resolveUser(phone);
  return completeLogin(user, input.deviceId);
}

/** Open the right account for a verified person on this device. */
export async function completeLogin(user: UserDoc, deviceId: string) {
  const { list, chosen } = await defaultMembership(user, deviceId);
  if (chosen) await bindDevice(chosen, deviceId);
  user.lastLoginAt = new Date();
  user.loginDevices = [...(user.loginDevices ?? []).filter((d) => d !== deviceId), deviceId].slice(-10) as any;
  await activate(user, chosen);
  const tokens = await issueTokens(user, deviceId, undefined, chosen);
  return sessionResult(user, chosen, list, tokens, deviceId);
}

async function looksRecycled(user: { _id: Types.ObjectId; name?: string | null; lastLoginAt?: Date | null; loginDevices?: string[] | null }, deviceId: string) {
  if (!user.lastLoginAt || (user.loginDevices ?? []).includes(deviceId)) return false;
  const days = await getConfig<number>('accounts.recycleDays');
  if (Date.now() - user.lastLoginAt.getTime() < days * 86400_000) return false;
  return !!(user.name || (await Membership.exists({ userId: user._id, status: 'active' })));
}

/** "R*** S***": enough for the real person to recognise themselves, nothing for anyone else. */
export function maskName(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => `${[...w][0]}***`)
    .join(' ');
}

const IDENTITY_AUDIENCE = 'staffmint-identity';
function signIdentityToken(userId: string, deviceId: string) {
  return jwt.sign({ sub: userId, did: deviceId }, env.JWT_ACCESS_SECRET, { expiresIn: '10m', issuer: 'staffmint', audience: IDENTITY_AUDIENCE });
}

export function verifyIdentityToken(token: string): { sub: string; did: string } {
  try {
    return jwt.verify(token, env.JWT_ACCESS_SECRET, { issuer: 'staffmint', audience: IDENTITY_AUDIENCE }) as { sub: string; did: string };
  } catch {
    throw new AppError('UNAUTHORIZED', 'This check has expired. Please log in again.');
  }
}

/** A one-time code for a non-phone key (e.g. `email:a@b.com`); consumed with [consumeOtp]. */
export async function createCode(key: string, channel: string) {
  const hourAgo = new Date(Date.now() - 3600_000);
  if ((await OtpRequest.countDocuments({ phone: key, createdAt: { $gte: hourAgo } })) >= MAX_OTP_PER_HOUR) {
    throw new AppError('RATE_LIMITED', 'Too many codes requested. Try again in an hour.');
  }
  const otp = await provider('otp');
  const code = otp.name === 'mock' ? env.OTP_MOCK_CODE : randomDigits(6);
  await OtpRequest.create({ phone: key, codeHash: otpHash(key, code), channel, provider: otp.name, expiresAt: new Date(Date.now() + env.OTP_TTL_SEC * 1000) });
  return { code, mock: otp.name === 'mock' };
}

/** Open another of the person's businesses on this device. */
export async function switchMembership(userId: Types.ObjectId | string, input: { membershipId: string; deviceId: string; refreshToken?: string }) {
  const user = await User.findOne({ _id: userId, deletedAt: null });
  if (!user) throw new AppError('UNAUTHORIZED', 'User not found');
  const m = await Membership.findOne({ _id: input.membershipId, userId: user._id, status: 'active' });
  if (!m) throw new AppError('NOT_FOUND', 'This account is not available any more');
  if (!deviceAllowed(m, input.deviceId)) {
    throw new AppError('DEVICE_NOT_BOUND', 'This staff account is linked to another phone. Ask your employer to approve this phone.', { membershipId: String(m._id), reason: 'device_locked' });
  }
  return openSession(user, m, input.deviceId, input.refreshToken);
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
    did: deviceId ?? null,
  });
  const refreshToken = randomToken(48);
  await RefreshToken.create({
    userId: user._id,
    tokenHash: sha256(refreshToken),
    family: family ?? randomToken(12),
    membershipId: membership?._id ?? null,
    role: membership?.role ?? null,
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
  const was = doc.membershipId ? await Membership.findOne({ _id: doc.membershipId, userId: user._id }) : null;
  let m = was?.status === 'active' ? was : null;
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
  return { ...tokens, accountChange: await describeChange(was, doc.role ?? null, m) };
}

/**
 * Tells the app why its business or role changed on refresh, so it can reload
 * and say so ("Your access to Gupta Sweets ended"). Null when nothing changed.
 */
async function describeChange(was: MembershipDoc | null, oldRole: string | null, now: MembershipDoc | null) {
  if (!was) return null;
  const sameAccount = now && String(now._id) === String(was._id);
  if (sameAccount && (!oldRole || oldRole === now.role)) return null;
  const [view] = await membershipViews([was]);
  return {
    kind: sameAccount ? ('role_changed' as const) : ('ended' as const),
    reason: sameAccount ? null : (was.endedReason ?? 'removed'),
    companyName: view?.companyName ?? '',
    role: now?.role ?? null,
    activeMembershipId: now ? String(now._id) : null,
  };
}

export async function logout(refreshToken: string) {
  await RefreshToken.updateOne({ tokenHash: sha256(refreshToken) }, { revokedAt: new Date() });
}

export async function revokeAllForUser(userId: Types.ObjectId) {
  await RefreshToken.updateMany({ userId, revokedAt: null }, { revokedAt: new Date() });
}
