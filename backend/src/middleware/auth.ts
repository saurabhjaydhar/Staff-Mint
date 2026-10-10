import type { NextFunction, Request, Response } from 'express';
import { Types } from 'mongoose';
import { verifyAccessToken } from '../lib/jwt.js';
import { AppError } from '../lib/errors.js';
import { User, Company, Membership } from '../models/index.js';
import type { Ctx, Role } from '../lib/context.js';
import { companyPlan } from '../modules/billing/plans.js';

/** Verifies the bearer token and builds the service context. companyId always comes from the server-side user record. */
export async function authenticate(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : (req.query.access_token as string | undefined);
  if (!token) throw new AppError('UNAUTHORIZED', 'Missing access token');
  const claims = verifyAccessToken(token);
  const user = await User.findById(claims.sub).lean();
  if (!user || user.deletedAt) throw new AppError('UNAUTHORIZED', 'User not found');
  // The business comes from the session's membership (each device can be in a different one).
  // Tokens from before memberships fall back to the business mirrored on the user.
  let access: { role: string; companyId: Types.ObjectId | null; employeeId: Types.ObjectId | null; branchIds: Types.ObjectId[]; membershipId: string | null } = {
    role: user.role,
    companyId: user.companyId ?? null,
    employeeId: user.employeeId ?? null,
    branchIds: (user.branchIds ?? []) as Types.ObjectId[],
    membershipId: null,
  };
  if (claims.mid) {
    const m = await Membership.findOne({ _id: claims.mid, userId: user._id }).lean();
    // Access ended or the role changed: the app refreshes (as for an expired token) and the
    // refresh moves this device to what the person can open now. Nobody is logged out.
    if (!m || m.status !== 'active' || m.role !== claims.role) {
      throw new AppError('TOKEN_EXPIRED', 'Your access to this business changed', { reason: 'account_changed' });
    }
    access = { role: m.role, companyId: m.companyId, employeeId: m.employeeId ?? null, branchIds: (m.branchIds ?? []) as Types.ObjectId[], membershipId: String(m._id) };
  }
  req.auth = {
    userId: String(user._id),
    role: access.role,
    companyId: access.companyId ? String(access.companyId) : null,
    employeeId: access.employeeId ? String(access.employeeId) : null,
    membershipId: access.membershipId,
    deviceId: claims.did ?? null,
  };
  const lang = (req.headers['accept-language'] as string | undefined)?.slice(0, 2);
  if (access.companyId) {
    req.ctx = {
      userId: user._id,
      companyId: access.companyId,
      role: access.role as Role,
      employeeId: access.employeeId,
      branchIds: access.branchIds,
      actorName: user.name || user.phone,
      channel: req.headers['x-client'] === 'web' ? 'web' : 'app',
      language: lang === 'en' || lang === 'hi' ? lang : (user.language as 'en' | 'hi'),
    };
  }
  next();
}

export function requireCompany(req: Request, _res: Response, next: NextFunction) {
  if (!req.ctx) throw new AppError('COMPANY_SETUP_REQUIRED', 'Complete company setup first');
  next();
}

export const requireRole =
  (...roles: Role[]) =>
  (req: Request, _res: Response, next: NextFunction) => {
    if (!req.ctx) throw new AppError('COMPANY_SETUP_REQUIRED', 'Complete company setup first');
    if (!roles.includes(req.ctx.role as Role)) throw new AppError('FORBIDDEN', 'Your role cannot do this');
    next();
  };

export const requireFeature =
  (feature: string) =>
  async (req: Request, _res: Response, next: NextFunction) => {
    const company = await Company.findById(req.ctx!.companyId).lean();
    const { plan } = await companyPlan(company!);
    if (!plan.features.includes(feature)) {
      throw new AppError('FEATURE_NOT_IN_PLAN', `This needs a higher plan (${feature})`, { feature, planCode: plan.code });
    }
    next();
  };

export const ctxOf = (req: Request): Ctx => {
  if (!req.ctx) throw new AppError('COMPANY_SETUP_REQUIRED', 'Complete company setup first');
  return req.ctx;
};
