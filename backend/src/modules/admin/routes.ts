import { Router, type NextFunction, type Request, type Response } from 'express';
import { z } from 'zod';
import { body } from '../../lib/http.js';
import { env } from '../../config/env.js';
import { AppError } from '../../lib/errors.js';
import { safeEqual } from '../../lib/crypto.js';
import { FeatureFlag, Plan } from '../../models/index.js';
import { getConfig, setConfig } from '../config/service.js';

/** Internal admin API for dynamic pricing / flags / config (no app release needed). */
export const adminRouter = Router();
adminRouter.use((req: Request, _res: Response, next: NextFunction) => {
  const key = String(req.headers['x-admin-key'] ?? '');
  if (!key || !safeEqual(key, env.ADMIN_API_KEY)) throw new AppError('UNAUTHORIZED', 'Admin key required');
  next();
});

const planSchema = z.object({
  name: z.string(),
  country: z.string().default('IN'),
  currency: z.string().default('INR'),
  priceMonthlyPaise: z.number().int().min(0),
  priceYearlyPaise: z.number().int().min(0),
  taxPercent: z.number().min(0).max(50).optional(),
  staffLimit: z.number().int().min(1),
  extraStaffPricePaise: z.number().int().min(0).default(0),
  maxStaffHardCap: z.number().int().min(1).optional(),
  trialDays: z.number().int().min(0).default(0),
  features: z.array(z.string()),
  providerPlanIds: z.record(z.string(), z.any()).optional(),
  sort: z.number().int().optional(),
  active: z.boolean().default(true),
});

adminRouter.get('/plans', async (_req, res) => res.json({ data: await Plan.find().sort({ sort: 1 }).lean() }));
adminRouter.get('/plans/:code', async (req, res) => res.json({ data: await Plan.findOne({ code: req.params.code }).lean() }));
adminRouter.put('/plans/:code', async (req, res) => {
  const b = body(req, planSchema);
  res.json({ data: await Plan.findOneAndUpdate({ code: req.params.code }, { ...b, code: req.params.code }, { upsert: true, new: true }).lean() });
});

adminRouter.get('/flags', async (_req, res) => res.json({ data: await FeatureFlag.find().lean() }));
adminRouter.put('/flags', async (req, res) => {
  const b = body(req, z.object({ key: z.string(), enabled: z.boolean(), plans: z.array(z.string()).default([]), companyIds: z.array(z.string()).default([]), description: z.string().optional() }));
  res.json({ data: await FeatureFlag.findOneAndUpdate({ key: b.key }, b, { upsert: true, new: true }).lean() });
});

adminRouter.get('/configs/:key', async (req, res) => res.json({ data: { key: req.params.key, value: await getConfig(String(req.params.key), (req.query.companyId as string) ?? null) } }));
adminRouter.put('/configs/:key', async (req, res) => {
  const b = body(req, z.object({ value: z.unknown(), companyId: z.string().nullable().optional() }));
  res.json({ data: await setConfig(String(req.params.key), b.value, b.companyId ?? null) });
});

// Fresh free trial for testing or support: one business, or every business a phone owns. days=0 ends it now.
adminRouter.post('/trials', async (req, res) => {
  const b = body(
    req,
    z
      .object({ companyId: z.string().optional(), phone: z.string().optional(), days: z.number().int().min(0).max(90).default(14), planCode: z.string().default('pro') })
      .refine((x) => x.companyId || x.phone, 'companyId or phone is required'),
  );
  const { grantTrial } = await import('../billing/trial.js');
  res.json({ data: await grantTrial(b) });
});

// Support recovery for a lost number (PRD F14 row 11): review proofs, then approve (7-day hold) or reject.
adminRouter.get('/recovery-requests', async (req, res) => {
  const { adminListRecoveries } = await import('../accounts/identity.js');
  res.json({ data: await adminListRecoveries(typeof req.query.status === 'string' ? req.query.status : undefined) });
});
adminRouter.post('/recovery-requests/:id/approve', async (req, res) => {
  const { adminApproveRecovery } = await import('../accounts/identity.js');
  res.json({ data: await adminApproveRecovery(String(req.params.id)) });
});
adminRouter.post('/recovery-requests/:id/reject', async (req, res) => {
  const b = body(req, z.object({ note: z.string().max(500).optional() }));
  const { adminRejectRecovery } = await import('../accounts/identity.js');
  res.json({ data: await adminRejectRecovery(String(req.params.id), b.note) });
});
