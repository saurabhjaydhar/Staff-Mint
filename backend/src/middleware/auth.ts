import type { NextFunction, Request, Response } from 'express';
import { Types } from 'mongoose';
import { verifyAccessToken } from '../lib/jwt.js';
import { AppError } from '../lib/errors.js';
import { User, Company } from '../models/index.js';
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
  req.auth = { userId: String(user._id), role: user.role, companyId: user.companyId ? String(user.companyId) : null, employeeId: user.employeeId ? String(user.employeeId) : null };
  const lang = (req.headers['accept-language'] as string | undefined)?.slice(0, 2);
  if (user.companyId) {
    req.ctx = {
      userId: user._id,
      companyId: user.companyId,
      role: user.role as Role,
      employeeId: user.employeeId ?? null,
      branchIds: (user.branchIds ?? []) as Types.ObjectId[],
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
