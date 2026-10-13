import { Router } from 'express';
import { z } from 'zod';
import { body, param } from '../../lib/http.js';
import { authenticate, ctxOf, requireFeature, requireRole } from '../../middleware/auth.js';
import { DOCUMENT_KINDS, VERIFICATION_KINDS } from '../../models/index.js';
import * as svc from './service.js';
import * as docs from './documents.js';

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
verificationRouter.post('/mine/face', ...staff, async (req, res) => {
  const b = body(req, z.object({ selfie: z.string().min(8) }));
  res.json({ data: await svc.verifyFace(ctxOf(req), b.selfie) });
});

// Owner does the same steps with someone who has no smartphone. Responses are the staff view of the steps.
const forStaff = async (req: any) => svc.onBehalf(ctxOf(req), param(req, 'id'));
verificationRouter.get('/employees/:id/on-behalf', ...owner, async (req, res) => res.json({ data: await svc.myVerification(await forStaff(req)) }));
verificationRouter.post('/employees/:id/on-behalf/consent', ...owner, async (req, res) => {
  const b = body(req, z.object({ staffAgreed: z.literal(true), slip: z.object({ data: z.string().min(8), mime: z.string().max(40) }) }));
  res.json({ data: await svc.consentOnBehalf(ctxOf(req), param(req, 'id'), b.slip) });
});
verificationRouter.post('/employees/:id/on-behalf/aadhaar/otp', ...owner, async (req, res) => {
  const b = body(req, z.object({ aadhaar: z.string().min(12).max(20) }));
  res.json({ data: await svc.aadhaarSendOtp(await forStaff(req), b.aadhaar) });
});
verificationRouter.post('/employees/:id/on-behalf/aadhaar/verify', ...owner, async (req, res) => {
  const b = body(req, z.object({ otp: z.string().regex(/^\d{4,8}$/) }));
  res.json({ data: await svc.aadhaarVerifyOtp(await forStaff(req), b.otp) });
});
verificationRouter.post('/employees/:id/on-behalf/pan', ...owner, async (req, res) => {
  const b = body(req, z.object({ pan: z.string().min(10).max(14) }));
  res.json({ data: await svc.verifyPan(await forStaff(req), b.pan) });
});
verificationRouter.post('/employees/:id/on-behalf/bank', ...owner, async (req, res) => {
  const b = body(req, z.object({ accountNumber: z.string().max(24).optional(), ifsc: z.string().max(14).optional() }));
  res.json({ data: await svc.verifyBank(await forStaff(req), b) });
});
verificationRouter.post('/employees/:id/on-behalf/face', ...owner, async (req, res) => {
  const b = body(req, z.object({ selfie: z.string().min(8) }));
  res.json({ data: await svc.verifyFace(await forStaff(req), b.selfie) });
});
verificationRouter.post('/employees/:id/slip/open', ...owner, async (req, res) => res.json({ data: await svc.openSlip(ctxOf(req), param(req, 'id')) }));

// Documents (photos and PDFs, encrypted). Owners see everyone's; staff see and add their own.
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const file = z.object({ data: z.string().min(8), mime: z.string().max(40) });
const doc = {
  kind: z.enum(DOCUMENT_KINDS),
  label: z.string().trim().max(60).nullish(),
  number: z.string().trim().max(24).nullish(),
  expiresOn: date.nullish(),
  files: z.array(file).min(1).max(3),
};
verificationRouter.get('/employees/:id/documents', ...owner, async (req, res) => res.json({ data: await docs.listForEmployee(ctxOf(req), param(req, 'id')) }));
verificationRouter.post('/employees/:id/documents', ...owner, requireFeature('documents'), async (req, res) => {
  const b = body(req, z.object({ ...doc, staffAgreed: z.boolean(), slip: file.nullish() }));
  res.status(201).json({ data: await docs.addForEmployee(ctxOf(req), param(req, 'id'), b) });
});
verificationRouter.patch('/documents/:id', ...owner, async (req, res) => {
  const b = body(req, z.object({ expiresOn: date.nullish(), label: z.string().trim().max(60).nullish() }));
  res.json({ data: await docs.updateDocument(ctxOf(req), param(req, 'id'), b) });
});
verificationRouter.delete('/documents/:id', authenticate, requireRole('owner', 'employee', 'manager'), async (req, res) => res.json({ data: await docs.removeDocument(ctxOf(req), param(req, 'id')) }));
verificationRouter.post('/documents/:id/open', authenticate, requireRole('owner', 'employee', 'manager'), async (req, res) => res.json({ data: await docs.openDocument(ctxOf(req), param(req, 'id')) }));
verificationRouter.get('/mine/documents', ...staff, async (req, res) => res.json({ data: await docs.listMine(ctxOf(req)) }));
verificationRouter.post('/mine/documents', ...staff, requireFeature('documents'), async (req, res) => {
  const b = body(req, z.object(doc));
  res.status(201).json({ data: await docs.addMine(ctxOf(req), b) });
});
