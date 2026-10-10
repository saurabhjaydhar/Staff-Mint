import { Router } from 'express';
import { z } from 'zod';
import { body, objectId, param, parse } from '../../lib/http.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import * as svc from './service.js';
import * as owners from './owners.js';
import * as identity from './identity.js';
import { parsePhone } from '../auth/service.js';

/** Account-level actions (F14): leave, close/restore, device change, accountants, invites. */
export const accountsRouter = Router();

const session = { deviceId: z.string().min(4).max(200), refreshToken: z.string().max(200).optional() };

// The person's own accounts (any role, business open or not).
accountsRouter.post('/me/accounts/:id/leave', authenticate, async (req, res) => {
  const b = body(req, z.object(session));
  res.json({ data: await svc.leaveAccount(req.auth!.userId, param(req, 'id'), b) });
});
accountsRouter.post('/me/notices/:id/dismiss', authenticate, async (req, res) => {
  await svc.dismissNotice(req.auth!.userId, param(req, 'id'));
  res.json({ data: { ok: true } });
});
accountsRouter.post('/me/businesses/:companyId/restore', authenticate, async (req, res) => {
  const b = body(req, z.object(session));
  res.json({ data: await svc.restoreBusiness(req.auth!.userId, param(req, 'companyId'), b) });
});
accountsRouter.post('/me/device-requests', authenticate, async (req, res) => {
  const b = body(req, z.object({ membershipId: objectId, deviceId: z.string().min(4).max(200), deviceName: z.string().max(80).optional() }));
  res.status(201).json({ data: await svc.requestDeviceChange(req.auth!.userId, b) });
});

// Owner / manager side.
accountsRouter.post('/company/close', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ confirmName: z.string().min(1).max(120), ...session }));
  res.json({ data: await svc.closeBusiness(ctxOf(req), b.confirmName, b) });
});
accountsRouter.get('/device-requests', authenticate, requireRole('owner', 'manager'), async (req, res) => {
  res.json({ data: await svc.listDeviceRequests(ctxOf(req)) });
});
accountsRouter.post('/device-requests/:id/:decision', authenticate, requireRole('owner', 'manager'), async (req, res) => {
  const decision = parse(z.enum(['approve', 'reject']), req.params.decision);
  res.json({ data: await svc.decideDeviceRequest(ctxOf(req), param(req, 'id'), decision === 'approve') });
});
accountsRouter.get('/company/accountants', authenticate, requireRole('owner'), async (req, res) => {
  res.json({ data: await svc.listAccountants(ctxOf(req)) });
});
accountsRouter.delete('/company/accountants/:id', authenticate, requireRole('owner'), async (req, res) => {
  await svc.removeAccountant(ctxOf(req), param(req, 'id'));
  res.json({ data: { ok: true } });
});
accountsRouter.post('/employees/:id/invite', authenticate, requireRole('owner', 'manager'), async (req, res) => {
  res.json({ data: await svc.inviteStaff(ctxOf(req), param(req, 'id')) });
});

// ------------------------------------------------ Phase 3: owners & identity

const phoneSchema = z.string().min(6).max(20).transform((p) => parsePhone(p));

accountsRouter.get('/company/owners', authenticate, requireRole('owner'), async (req, res) => {
  res.json({ data: await owners.listOwners(ctxOf(req)) });
});
accountsRouter.post('/company/owners', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ phone: phoneSchema, name: z.string().trim().min(1).max(80), canManageBilling: z.boolean().optional() }));
  res.status(201).json({ data: await owners.addCoOwner(ctxOf(req), b) });
});
accountsRouter.patch('/company/owners/:id', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ canManageBilling: z.boolean() }));
  res.json({ data: await owners.setCoOwnerBilling(ctxOf(req), param(req, 'id'), b.canManageBilling) });
});
accountsRouter.delete('/company/owners/:id', authenticate, requireRole('owner'), async (req, res) => {
  res.json({ data: await owners.removeCoOwner(ctxOf(req), param(req, 'id')) });
});
accountsRouter.post('/company/transfer', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ phone: phoneSchema, keepAs: z.enum(['co_owner', 'leave']).default('co_owner'), code: z.string().min(4).max(8) }));
  res.status(201).json({ data: await owners.startTransfer(ctxOf(req), b) });
});
accountsRouter.get('/company/transfer', authenticate, requireRole('owner'), async (req, res) => {
  res.json({ data: await owners.currentTransfer(ctxOf(req)) });
});
accountsRouter.delete('/company/transfer', authenticate, requireRole('owner'), async (req, res) => {
  await owners.cancelTransfer(ctxOf(req));
  res.json({ data: { ok: true } });
});
accountsRouter.post('/company/owner-recovery', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ newPhone: phoneSchema }));
  res.status(201).json({ data: await owners.startOwnerRecovery(ctxOf(req), b.newPhone) });
});
accountsRouter.post('/me/transfers/:id/:decision', authenticate, async (req, res) => {
  const decision = parse(z.enum(['accept', 'decline']), req.params.decision);
  const b = body(req, z.object(session));
  res.json({ data: await owners.decideTransfer(req.auth!.userId, param(req, 'id'), decision === 'accept', b) });
});

// Recycled numbers: answer "Is this you?" with the short-lived token from login.
accountsRouter.post('/auth/identity/:answer', async (req, res) => {
  const answer = parse(z.enum(['confirm', 'reject']), req.params.answer);
  const b = body(req, z.object({ token: z.string().min(20) }));
  res.json({ data: answer === 'confirm' ? await identity.confirmIdentity(b.token) : await identity.rejectIdentity(b.token) });
});

// Lost number: email code, or support recovery with a 7-day hold.
accountsRouter.post('/me/recovery/email', authenticate, async (req, res) => {
  const b = body(req, z.object({ email: z.string().email() }));
  res.json({ data: await identity.requestEmailRecovery(req.auth!.userId, b.email) });
});
accountsRouter.post('/me/recovery/email/verify', authenticate, async (req, res) => {
  const b = body(req, z.object({ email: z.string().email(), code: z.string().min(4).max(8), ...session }));
  res.json({ data: await identity.verifyEmailRecovery(req.auth!.userId, b) });
});
accountsRouter.post('/me/recovery-requests', authenticate, async (req, res) => {
  const b = body(
    req,
    z.object({
      oldPhone: phoneSchema,
      businessName: z.string().trim().min(2).max(120),
      gstin: z.string().trim().max(40).optional(),
      paymentTxnId: z.string().trim().max(80).optional(),
      selfieVideoBase64: z.string().max(12_000_000).optional(),
    }),
  );
  res.status(201).json({ data: await identity.submitRecovery(req.auth!.userId, b) });
});
accountsRouter.get('/me/recovery-requests', authenticate, async (req, res) => {
  res.json({ data: await identity.myRecoveries(req.auth!.userId) });
});
accountsRouter.post('/me/recovery-holds/:id/stop', authenticate, async (req, res) => {
  await identity.stopRecovery(req.auth!.userId, param(req, 'id'));
  res.json({ data: { ok: true } });
});

// Personal data: export, delete, and past payslips after leaving a job.
accountsRouter.get('/me/export', authenticate, async (req, res) => {
  res.json({ data: await identity.exportMyData(req.auth!.userId) });
});
accountsRouter.post('/me/delete', authenticate, async (req, res) => {
  const b = body(req, z.object({ code: z.string().min(4).max(8) }));
  await identity.deleteMyAccount(req.auth!.userId, b.code);
  res.json({ data: { ok: true } });
});
accountsRouter.get('/me/past-payslips', authenticate, async (req, res) => {
  res.json({ data: await identity.pastPayslips(req.auth!.userId) });
});
