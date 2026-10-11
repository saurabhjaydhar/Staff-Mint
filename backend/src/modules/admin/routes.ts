import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { body, param, query } from '../../lib/http.js';
import { isTest } from '../../config/env.js';
import { FeatureFlag, Plan } from '../../models/index.js';
import { getConfig, setConfig } from '../config/service.js';
import { authenticateAdmin, finishLogin, logAction, logoutEverywhere, requireAdminRole, startLogin, adminView } from './auth.js';
import * as svc from './service.js';
import { AdminUser } from '../../models/index.js';

const page = { page: z.coerce.number().int().min(1).default(1), limit: z.coerce.number().int().min(1).max(100).default(20) };

/** Sign-in for the admin app: email + password, then a code sent by email. */
export const adminAuthRouter = Router();
adminAuthRouter.use(
  rateLimit({ windowMs: 15 * 60_000, limit: isTest ? 100000 : 20, standardHeaders: 'draft-8', legacyHeaders: false, message: { error: { code: 'RATE_LIMITED', message: 'Too many sign-in attempts. Try again later.' } } }),
);
adminAuthRouter.post('/login', async (req, res) => {
  const b = body(req, z.object({ email: z.string().email().max(200), password: z.string().min(1).max(200) }));
  res.json({ data: await startLogin(b.email, b.password) });
});
adminAuthRouter.post('/verify', async (req, res) => {
  const b = body(req, z.object({ ticket: z.string().min(10), code: z.string().regex(/^\s*\d{6}\s*$/, 'Enter the 6-digit code') }));
  res.json({ data: await finishLogin(b.ticket, b.code) });
});

/** Internal admin API: the admin app (Bearer session) or scripts (x-admin-key). Viewers can read; changes need the admin role. */
export const adminRouter = Router();
adminRouter.use(authenticateAdmin);
const write = requireAdminRole;

// ---- Session ----
adminRouter.get('/me', async (req, res) => {
  const a = req.admin!.id ? await AdminUser.findById(req.admin!.id).lean() : null;
  res.json({ data: a ? adminView(a) : { id: null, email: 'api-key', name: 'API key', role: 'admin', active: true } });
});
adminRouter.post('/logout', async (req, res) => {
  if (req.admin!.id) await logoutEverywhere(req.admin!.id);
  res.json({ data: { ok: true } });
});
adminRouter.post('/me/password', async (req, res) => {
  const b = body(req, z.object({ current: z.string().min(1), next: z.string().min(1).max(200) }));
  if (!req.admin!.id) return res.status(400).json({ error: { code: 'VALIDATION_ERROR', message: 'The API key has no password' } });
  await svc.changeOwnPassword(req.admin!.id, b.current, b.next);
  await logAction(req, 'admin.password_change');
  res.json({ data: { ok: true } });
});

// ---- Overview ----
adminRouter.get('/stats', async (_req, res) => res.json({ data: await svc.stats() }));

// ---- Businesses ----
adminRouter.get('/companies', async (req, res) => {
  const q = query(req, z.object({ search: z.string().max(100).optional(), status: z.enum(svc.BUSINESS_STATUSES as [svc.BusinessStatus, ...svc.BusinessStatus[]]).optional(), ...page }));
  res.json({ data: await svc.listCompanies(q) });
});
adminRouter.get('/companies/:id', async (req, res) => res.json({ data: await svc.companyDetail(param(req, 'id')) }));
adminRouter.post('/companies/:id/plan', write, async (req, res) => {
  const id = param(req, 'id');
  const b = body(req, z.object({ planCode: z.string().min(1), months: z.number().int().min(1).max(36).default(1), note: z.string().max(300).optional() }));
  const r = await svc.setCompanyPlan(id, b);
  await logAction(req, 'company.plan', { companyId: id, details: { planCode: b.planCode, months: b.months, note: b.note } });
  res.json({ data: r });
});

// ---- Free trials (one business, or every business a phone owns). days=0 ends it now. ----
adminRouter.post('/trials', write, async (req, res) => {
  const b = body(
    req,
    z
      .object({ companyId: z.string().optional(), phone: z.string().optional(), days: z.number().int().min(0).max(90).default(14), planCode: z.string().default('pro') })
      .refine((x) => x.companyId || x.phone, 'companyId or phone is required'),
  );
  const { grantTrial } = await import('../billing/trial.js');
  const out = await grantTrial(b);
  for (const r of out) await logAction(req, 'company.trial', { companyId: r.companyId, details: { days: b.days, planCode: b.planCode, ...('skipped' in r ? { skipped: r.skipped } : {}) } });
  res.json({ data: out });
});

// ---- Plans and prices ----
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

/** Saved plans, or the built-in ones until the first edit. */
adminRouter.get('/plans', async (_req, res) => {
  const saved = await Plan.find().sort({ sort: 1 }).lean();
  res.json({ data: saved.length ? saved : await svc.listPlansForAdmin() });
});
adminRouter.get('/plans/:code', async (req, res) => res.json({ data: await Plan.findOne({ code: req.params.code }).lean() }));
adminRouter.put('/plans/:code', write, async (req, res) => {
  const b = body(req, planSchema);
  const before = await Plan.findOne({ code: req.params.code }).lean();
  const after = await Plan.findOneAndUpdate({ code: req.params.code }, { ...b, code: req.params.code }, { upsert: true, returnDocument: 'after' }).lean();
  await logAction(req, 'plan.update', { target: String(req.params.code), details: { before: before ? svc.planSummary(before) : null, after: svc.planSummary(after) } });
  res.json({ data: after });
});

// ---- Feature flags ----
adminRouter.get('/flags', async (_req, res) => res.json({ data: await FeatureFlag.find().sort({ key: 1 }).lean() }));
adminRouter.put('/flags', write, async (req, res) => {
  const b = body(req, z.object({ key: z.string().min(1).max(80), enabled: z.boolean(), plans: z.array(z.string()).default([]), companyIds: z.array(z.string()).default([]), description: z.string().optional() }));
  const flag = await FeatureFlag.findOneAndUpdate({ key: b.key }, b, { upsert: true, returnDocument: 'after' }).lean();
  await logAction(req, 'flag.update', { target: b.key, details: { enabled: b.enabled, plans: b.plans, companies: b.companyIds.length } });
  res.json({ data: flag });
});

// ---- Settings ----
adminRouter.get('/configs', async (_req, res) => res.json({ data: await svc.listConfigs() }));
adminRouter.get('/configs/:key', async (req, res) => res.json({ data: { key: req.params.key, value: await getConfig(String(req.params.key), (req.query.companyId as string) ?? null) } }));
adminRouter.put('/configs/:key', write, async (req, res) => {
  const key = String(req.params.key);
  const b = body(req, z.object({ value: z.unknown(), companyId: z.string().nullable().optional() }));
  svc.checkConfigValue(key, b.value);
  const before = await getConfig(key, b.companyId ?? null);
  const saved = await setConfig(key, b.value, b.companyId ?? null);
  await logAction(req, 'config.update', { target: key, companyId: b.companyId ?? null, details: { before, after: b.value } });
  res.json({ data: saved });
});

// ---- Messages (WhatsApp, push, SMS, email) ----
adminRouter.get('/messages', async (req, res) => {
  const q = query(req, z.object({ status: z.enum(['queued', 'sent', 'delivered', 'read', 'failed']).optional(), channel: z.enum(['push', 'whatsapp', 'sms', 'email']).optional(), companyId: z.string().optional(), ...page }));
  res.json({ data: await svc.listMessages(q) });
});

// ---- What admins changed ----
adminRouter.get('/actions', async (req, res) => {
  const q = query(req, z.object({ companyId: z.string().optional(), ...page }));
  res.json({ data: await svc.listActions(q) });
});

// ---- Admin accounts ----
adminRouter.get('/admins', async (_req, res) => res.json({ data: await svc.listAdmins() }));
adminRouter.post('/admins', write, async (req, res) => {
  const b = body(req, z.object({ email: z.string().email().max(200), name: z.string().max(80).optional(), role: z.enum(['admin', 'viewer']).default('viewer'), password: z.string().min(1).max(200) }));
  const a = await svc.createAdmin(b);
  await logAction(req, 'admin.create', { target: a.email, details: { role: a.role } });
  res.status(201).json({ data: a });
});
adminRouter.patch('/admins/:id', write, async (req, res) => {
  const id = param(req, 'id');
  const b = body(req, z.object({ role: z.enum(['admin', 'viewer']).optional(), active: z.boolean().optional(), name: z.string().max(80).optional() }));
  const a = await svc.updateAdmin(id, b, req.admin!.id);
  await logAction(req, 'admin.update', { target: a.email, details: b });
  res.json({ data: a });
});

// ---- Support recovery for a lost number (PRD F14 row 11): review proofs, then approve (7-day hold) or reject. ----
adminRouter.get('/recovery-requests', async (req, res) => {
  const { adminListRecoveries } = await import('../accounts/identity.js');
  res.json({ data: await adminListRecoveries(typeof req.query.status === 'string' ? req.query.status : undefined) });
});
adminRouter.post('/recovery-requests/:id/approve', write, async (req, res) => {
  const { adminApproveRecovery } = await import('../accounts/identity.js');
  const r = await adminApproveRecovery(String(req.params.id));
  await logAction(req, 'recovery.approve', { target: String(req.params.id) });
  res.json({ data: r });
});
adminRouter.post('/recovery-requests/:id/reject', write, async (req, res) => {
  const b = body(req, z.object({ note: z.string().max(500).optional() }));
  const { adminRejectRecovery } = await import('../accounts/identity.js');
  const r = await adminRejectRecovery(String(req.params.id), b.note);
  await logAction(req, 'recovery.reject', { target: String(req.params.id), details: { note: b.note } });
  res.json({ data: r });
});
