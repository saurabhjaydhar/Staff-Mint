import { Router } from 'express';
import { z } from 'zod';
import { body, objectId, param, parse } from '../../lib/http.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import * as svc from './service.js';

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
