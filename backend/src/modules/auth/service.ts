import { Types } from 'mongoose';
import { env } from '../../config/env.js';
import { AppError } from '../../lib/errors.js';
import { normalizePhone } from '../../lib/phone.js';
import { randomDigits, randomToken, sha256, safeEqual } from '../../lib/crypto.js';
import { signAccessToken } from '../../lib/jwt.js';
import { OtpRequest, RefreshToken, User, Employee, type UserDoc } from '../../models/index.js';
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

/** A login that never set up a business. It is not anyone's data yet, so it may become a staff login. */
export const isUnclaimedLogin = (u: { role: string; companyId?: unknown }) => u.role === 'owner' && !u.companyId;

/**
 * Turn an unclaimed login into the staff login for the newest active staff
 * record with this phone. Fixes numbers that opened the app before the
 * owner added them (they would otherwise land in "create your business").
 * Returns true when it linked.
 */
export async function linkStaffLogin(user: UserDoc, deviceId?: string | null): Promise<boolean> {
  if (!isUnclaimedLogin(user)) return false;
  const emp = await Employee.findOne({ phone: user.phone, status: 'active', deletedAt: null }).setOptions({ skipTenant: true }).sort({ createdAt: -1 });
  if (!emp) return false;
  user.role = emp.appRole ?? 'employee';
  user.companyId = emp.companyId;
  user.employeeId = emp._id;
  if (!user.name) user.name = emp.name;
  user.language = emp.language ?? user.language;
  // Device binding starts fresh: only the phone logging in now is bound.
  user.deviceIds = deviceId && !deviceId.startsWith('web-') ? [deviceId] : [];
  await user.save();
  emp.userId = user._id;
  await emp.save();
  logger.info({ userId: user._id, employeeId: emp._id }, 'Unclaimed login linked to staff record');
  return true;
}

/** Find or create the user for a phone. Employees are matched by their phone on an active employee record. */
async function resolveUser(phone: string): Promise<UserDoc> {
  let user = await User.findOne({ phone, deletedAt: null });
  if (user && (await linkStaffLogin(user))) return user;
  if (user) {
    // Employee user whose record was re-activated or moved: keep link fresh.
    if (user.role === 'employee' || user.role === 'manager') {
      const emp = user.employeeId ? await Employee.findOne({ _id: user.employeeId, companyId: user.companyId }).lean() : null;
      if (!emp || emp.status !== 'active' || emp.deletedAt) {
        throw new AppError('FORBIDDEN', 'Your staff account is inactive. Please contact your employer.');
      }
      if (user.role !== emp.appRole) {
        user.role = emp.appRole;
        await user.save();
      }
    }
    return user;
  }
  const emp = await Employee.findOne({ phone, status: 'active', deletedAt: null }).setOptions({ skipTenant: true }).sort({ createdAt: -1 });
  if (emp) {
    user = await User.create({ phone, name: emp.name, role: emp.appRole ?? 'employee', companyId: emp.companyId, employeeId: emp._id, language: emp.language ?? 'hi' });
    emp.userId = user._id;
    await emp.save();
    return user;
  }
  return User.create({ phone, role: 'owner', companyId: null });
}

export async function verifyOtp(input: { phone: string; code: string; deviceId: string; deviceName?: string }) {
  const phone = parsePhone(input.phone);
  await consumeOtp(phone, input.code);
  const user = await resolveUser(phone);

  const isWebLogin = input.deviceId.startsWith('web-');
  if ((user.role === 'employee' || user.role === 'manager') && !isWebLogin) {
    // Device binding applies to the phone app only; web logins never bind a staff account.
    if (user.deviceIds.length === 0) user.deviceIds = [input.deviceId];
    else if (!user.deviceIds.includes(input.deviceId)) {
      throw new AppError('DEVICE_NOT_BOUND', 'This account is linked to another phone. Ask your employer to reset your device.');
    }
  } else if (!isWebLogin && !user.deviceIds.includes(input.deviceId)) {
    user.deviceIds = [...user.deviceIds, input.deviceId].slice(-5);
  }
  user.lastLoginAt = new Date();
  await user.save();
  const tokens = await issueTokens(user, input.deviceId);
  return { ...tokens, user: userView(user), needsCompanySetup: !user.companyId };
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

export async function issueTokens(user: { _id: Types.ObjectId; role: string; companyId?: Types.ObjectId | null; employeeId?: Types.ObjectId | null }, deviceId?: string, family?: string) {
  const accessToken = signAccessToken({
    sub: String(user._id),
    role: user.role,
    cid: user.companyId ? String(user.companyId) : null,
    eid: user.employeeId ? String(user.employeeId) : null,
  });
  const refreshToken = randomToken(48);
  await RefreshToken.create({
    userId: user._id,
    tokenHash: sha256(refreshToken),
    family: family ?? randomToken(12),
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
  // "Check again" on the waiting screen: the owner may have added this number since.
  await linkStaffLogin(user, doc.deviceId);
  const tokens = await issueTokens(user, doc.deviceId ?? undefined, doc.family);
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
