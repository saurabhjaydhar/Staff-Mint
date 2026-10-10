import { Router } from 'express';
import { z } from 'zod';
import { body, param } from '../../lib/http.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { AppError } from '../../lib/errors.js';
import * as svc from './service.js';

/** Mounted at `/`; every route authenticates itself so public routes are never shadowed. */
export const profileRouter = Router();

const bankSchema = z.object({
  holderName: z.string().trim().min(2).max(80),
  accountNumber: z.string().max(30).nullable().optional(),
  ifsc: z.string().max(15).nullable().optional(),
  upiId: z.string().max(100).nullable().optional(),
});

profileRouter.get('/me/profile', authenticate, async (req, res) => {
  res.json({ data: await svc.profileView(ctxOf(req)) });
});

profileRouter.patch('/me/profile', authenticate, async (req, res) => {
  const b = body(
    req,
    z
      .object({
        name: z.string().trim().min(1).max(80),
        email: z.string().trim().email().max(120).nullable(),
        language: z.enum(['en', 'hi']),
        emergencyContact: z
          .object({ name: z.string().trim().min(2).max(80), phone: z.string().max(20).nullable().optional(), relation: z.string().trim().max(40).nullable().optional() })
          .nullable(),
      })
      .partial()
      .strict(),
  );
  res.json({ data: await svc.updateProfile(ctxOf(req), b) });
});

profileRouter.put('/me/photo', authenticate, async (req, res) => {
  const b = body(req, z.object({ photoBase64: z.string().min(100).max(3_000_000) }));
  res.json({ data: await svc.setPhoto(ctxOf(req), b.photoBase64) });
});

profileRouter.delete('/me/photo', authenticate, async (req, res) => {
  res.json({ data: await svc.removePhoto(ctxOf(req)) });
});

profileRouter.put('/me/bank', authenticate, requireRole('employee', 'manager'), async (req, res) => {
  const ctx = ctxOf(req);
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Only staff have a salary account here');
  res.json({ data: await svc.setBank(ctx, ctx.employeeId, body(req, bankSchema)) });
});

profileRouter.delete('/me/bank', authenticate, requireRole('employee', 'manager'), async (req, res) => {
  const ctx = ctxOf(req);
  if (!ctx.employeeId) throw new AppError('FORBIDDEN', 'Only staff have a salary account here');
  res.json({ data: await svc.setBank(ctx, ctx.employeeId, null) });
});

profileRouter.post('/me/phone/request', authenticate, async (req, res) => {
  const b = body(req, z.object({ phone: z.string().min(6).max(20) }));
  res.json({ data: await svc.requestPhoneChange(ctxOf(req), b.phone, req.ip) });
});

profileRouter.post('/me/phone/verify', authenticate, async (req, res) => {
  const b = body(req, z.object({ phone: z.string().min(6).max(20), code: z.string().regex(/^\d{4,8}$/) }));
  res.json({ data: await svc.verifyPhoneChange(ctxOf(req), b.phone, b.code) });
});

profileRouter.post('/me/logout-all', authenticate, async (req, res) => {
  await svc.logoutEverywhere(ctxOf(req));
  res.json({ data: { ok: true } });
});

// Owner fills in or clears a staff member's salary account.
profileRouter.put('/employees/:id/bank', authenticate, requireRole('owner'), async (req, res) => {
  res.json({ data: await svc.setBank(ctxOf(req), param(req, 'id'), body(req, bankSchema)) });
});

profileRouter.delete('/employees/:id/bank', authenticate, requireRole('owner'), async (req, res) => {
  res.json({ data: await svc.setBank(ctxOf(req), param(req, 'id'), null) });
});
