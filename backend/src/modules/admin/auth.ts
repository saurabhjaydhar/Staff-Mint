import crypto from 'node:crypto';
import { promisify } from 'node:util';
import type { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import type { Types } from 'mongoose';
import { env, isProd } from '../../config/env.js';
import { AppError } from '../../lib/errors.js';
import { randomDigits, safeEqual, sha256 } from '../../lib/crypto.js';
import { AdminAction, AdminUser } from '../../models/index.js';
import { provider } from '../../providers/registry.js';

const scrypt = promisify(crypto.scrypt) as (pw: string, salt: Buffer, len: number) => Promise<Buffer>;
const AUDIENCE = 'staffmint-admin';
const TICKET_AUDIENCE = 'staffmint-admin-ticket';
const SESSION_TTL = '12h';
const CODE_TTL_MS = 10 * 60_000;
const MAX_FAILED = 5;
const LOCK_MS = 15 * 60_000;
const MAX_CODE_ATTEMPTS = 5;

export type AdminRole = 'admin' | 'viewer';

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.randomBytes(16);
  const hash = await scrypt(password, salt, 64);
  return `s1:${salt.toString('base64')}:${hash.toString('base64')}`;
}

export async function checkPassword(password: string, stored: string): Promise<boolean> {
  const [v, salt, hash] = stored.split(':');
  if (v !== 's1' || !salt || !hash) return false;
  const got = await scrypt(password, Buffer.from(salt, 'base64'), 64);
  const want = Buffer.from(hash, 'base64');
  return got.length === want.length && crypto.timingSafeEqual(got, want);
}

/** At least 10 characters with a letter and a number: admins can change prices and plans. */
export function assertStrongPassword(password: string) {
  if (password.length < 10 || !/[a-zA-Z]/.test(password) || !/\d/.test(password)) {
    throw new AppError('VALIDATION_ERROR', 'Password needs at least 10 characters, with letters and numbers');
  }
}

export const adminView = (a: any) => ({
  id: String(a._id),
  email: a.email,
  name: a.name,
  role: a.role as AdminRole,
  active: a.active,
  lastLoginAt: a.lastLoginAt ?? null,
  createdAt: a.createdAt,
});

const invalid = () => new AppError('UNAUTHORIZED', 'Wrong email or password');

/** Step 1: email + password. Sends a 6-digit code to the admin's email and returns a 10-minute ticket. */
export async function startLogin(emailIn: string, password: string) {
  const email = emailIn.trim().toLowerCase();
  const admin = await AdminUser.findOne({ email });
  if (!admin || !admin.active) {
    // Same work and answer as a wrong password, so emails can't be discovered.
    await checkPassword(password, 's1:AAAAAAAAAAAAAAAAAAAAAA==:AAAA');
    throw invalid();
  }
  if (admin.lockedUntil && admin.lockedUntil > new Date()) {
    throw new AppError('RATE_LIMITED', 'Too many wrong attempts. Try again in 15 minutes.');
  }
  if (!(await checkPassword(password, admin.passwordHash))) {
    admin.failedLogins += 1;
    if (admin.failedLogins >= MAX_FAILED) {
      admin.failedLogins = 0;
      admin.lockedUntil = new Date(Date.now() + LOCK_MS);
    }
    await admin.save();
    throw invalid();
  }
  const code = randomDigits(6);
  admin.failedLogins = 0;
  admin.lockedUntil = null;
  admin.loginCodeHash = sha256(`${admin._id}:${code}`);
  admin.loginCodeExpiresAt = new Date(Date.now() + CODE_TTL_MS);
  admin.loginCodeAttempts = 0;
  await admin.save();
  const mail = await provider('email');
  await mail.send(
    admin.email,
    `StaffMint admin sign-in code: ${code}`,
    `<p>Your StaffMint admin sign-in code is <b style="font-size:20px">${code}</b>.</p><p>It works for 10 minutes. If this wasn't you, change your password.</p>`,
  );
  const ticket = jwt.sign({ sub: String(admin._id), tv: admin.tokenVersion }, env.JWT_ACCESS_SECRET, { expiresIn: '10m', issuer: 'staffmint', audience: TICKET_AUDIENCE });
  const masked = admin.email.replace(/^(.)(.*)(@.*)$/, (_m, a: string, b: string, c: string) => `${a}${'•'.repeat(Math.min(b.length, 6))}${c}`);
  return { ticket, sentTo: masked, ...(!isProd && mail.name === 'mock' ? { devCode: code } : {}) };
}

/** Step 2: the emailed code. Returns a 12-hour admin session token. */
export async function finishLogin(ticket: string, code: string) {
  let claims: { sub: string; tv: number };
  try {
    claims = jwt.verify(ticket, env.JWT_ACCESS_SECRET, { issuer: 'staffmint', audience: TICKET_AUDIENCE }) as any;
  } catch {
    throw new AppError('UNAUTHORIZED', 'Sign-in expired. Start again.');
  }
  const admin = await AdminUser.findById(claims.sub);
  if (!admin || !admin.active || admin.tokenVersion !== claims.tv || !admin.loginCodeHash || !admin.loginCodeExpiresAt) {
    throw new AppError('UNAUTHORIZED', 'Sign-in expired. Start again.');
  }
  if (admin.loginCodeExpiresAt < new Date() || admin.loginCodeAttempts >= MAX_CODE_ATTEMPTS) {
    throw new AppError('OTP_INVALID', 'Code expired. Start again.');
  }
  if (!safeEqual(sha256(`${admin._id}:${code.trim()}`), admin.loginCodeHash)) {
    admin.loginCodeAttempts += 1;
    await admin.save();
    throw new AppError('OTP_INVALID', 'Wrong code');
  }
  admin.loginCodeHash = null;
  admin.loginCodeExpiresAt = null;
  admin.loginCodeAttempts = 0;
  admin.lastLoginAt = new Date();
  await admin.save();
  await AdminAction.create({ adminId: admin._id, actor: admin.email, action: 'admin.login' });
  const accessToken = jwt.sign({ sub: String(admin._id), role: admin.role, tv: admin.tokenVersion }, env.JWT_ACCESS_SECRET, {
    expiresIn: SESSION_TTL,
    issuer: 'staffmint',
    audience: AUDIENCE,
  });
  return { accessToken, expiresInSec: 12 * 3600, admin: adminView(admin) };
}

/** Ends every session of this admin (all devices). */
export async function logoutEverywhere(adminId: string) {
  await AdminUser.updateOne({ _id: adminId }, { $inc: { tokenVersion: 1 } });
}

/** Admin app session (Bearer) or the x-admin-key for scripts and support tooling. */
export async function authenticateAdmin(req: Request, _res: Response, next: NextFunction) {
  const key = String(req.headers['x-admin-key'] ?? '');
  if (key) {
    if (!safeEqual(key, env.ADMIN_API_KEY)) throw new AppError('UNAUTHORIZED', 'Admin key required');
    req.admin = { id: null, email: 'api-key', role: 'admin' };
    return next();
  }
  const header = req.headers.authorization ?? '';
  if (!header.startsWith('Bearer ')) throw new AppError('UNAUTHORIZED', 'Admin key required');
  let claims: { sub: string; tv: number };
  try {
    claims = jwt.verify(header.slice(7), env.JWT_ACCESS_SECRET, { issuer: 'staffmint', audience: AUDIENCE }) as any;
  } catch (e: any) {
    if (e?.name === 'TokenExpiredError') throw new AppError('TOKEN_EXPIRED', 'Admin session expired');
    throw new AppError('UNAUTHORIZED', 'Invalid admin session');
  }
  const admin = await AdminUser.findById(claims.sub).lean();
  if (!admin || !admin.active || admin.tokenVersion !== claims.tv) throw new AppError('UNAUTHORIZED', 'Admin session ended');
  req.admin = { id: String(admin._id), email: admin.email, role: admin.role as AdminRole };
  next();
}

/** Changes need the admin role; viewers can only look. */
export function requireAdminRole(req: Request, _res: Response, next: NextFunction) {
  if (req.admin?.role !== 'admin') throw new AppError('FORBIDDEN', 'View-only admins cannot make changes');
  next();
}

export async function logAction(req: Request, action: string, extra: { companyId?: unknown; target?: string; details?: Record<string, unknown> } = {}) {
  await AdminAction.create({
    adminId: req.admin?.id ?? null,
    actor: req.admin?.email ?? 'unknown',
    action,
    companyId: (extra.companyId as Types.ObjectId | string | null | undefined) ?? null,
    target: extra.target ?? null,
    details: extra.details ?? {},
  });
}
