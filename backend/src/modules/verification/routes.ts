import { Router } from 'express';
import { z } from 'zod';
import { body, param } from '../../lib/http.js';
import { authenticate, ctxOf, requireFeature, requireRole } from '../../middleware/auth.js';
import { VERIFICATION_KINDS } from '../../models/index.js';
import * as svc from './service.js';

export const verificationRouter = Router();

// Owner only: results include date of birth and names on government records.
const owner = [authenticate, requireRole('owner')];
const staff = [authenticate, requireRole('employee', 'manager')];

verificationRouter.get('/employees/:id', ...owner, async (req, res) => res.json({ data: await svc.ownerView(ctxOf(req), param(req, 'id')) }));
verificationRouter.post('/employees/:id', ...owner, requireFeature('verification'), async (req, res) => {
  const b = body(req, z.object({ kinds: z.array(z.enum(VERIFICATION_KINDS)).min(1) }));
  res.status(201).json({ data: await svc.requestVerification(ctxOf(req), param(req, 'id'), b.kinds) });
});
verificationRouter.delete('/employees/:id', ...owner, async (req, res) => res.json({ data: await svc.cancelRequest(ctxOf(req), param(req, 'id')) }));
verificationRouter.post('/checks/:id/accept', ...owner, async (req, res) => {
  const b = body(req, z.object({ reason: z.string().trim().min(1).max(200) }));
  res.json({ data: await svc.acceptMismatch(ctxOf(req), param(req, 'id'), b.reason) });
});
verificationRouter.post('/checks/:id/ask-again', ...owner, async (req, res) => res.json({ data: await svc.askAgain(ctxOf(req), param(req, 'id')) }));

// Staff: agree, then Aadhaar (OTP), PAN and bank account.
verificationRouter.get('/mine', ...staff, async (req, res) => res.json({ data: await svc.myVerification(ctxOf(req)) }));
verificationRouter.post('/mine/consent', ...staff, async (req, res) => res.json({ data: await svc.giveConsent(ctxOf(req)) }));
verificationRouter.post('/mine/aadhaar/otp', ...staff, async (req, res) => {
  const b = body(req, z.object({ aadhaar: z.string().min(12).max(20) }));
  res.json({ data: await svc.aadhaarSendOtp(ctxOf(req), b.aadhaar) });
});
verificationRouter.post('/mine/aadhaar/verify', ...staff, async (req, res) => {
  const b = body(req, z.object({ otp: z.string().regex(/^\d{4,8}$/) }));
  res.json({ data: await svc.aadhaarVerifyOtp(ctxOf(req), b.otp) });
});
verificationRouter.post('/mine/pan', ...staff, async (req, res) => {
  const b = body(req, z.object({ pan: z.string().min(10).max(14) }));
  res.json({ data: await svc.verifyPan(ctxOf(req), b.pan) });
});
verificationRouter.post('/mine/bank', ...staff, async (req, res) => {
  const b = body(req, z.object({ accountNumber: z.string().max(24).optional(), ifsc: z.string().max(14).optional() }));
  res.json({ data: await svc.verifyBank(ctxOf(req), b) });
});
