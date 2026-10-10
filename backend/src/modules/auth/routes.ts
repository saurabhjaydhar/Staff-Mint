import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { body } from '../../lib/http.js';
import { isTest } from '../../config/env.js';
import { authenticate } from '../../middleware/auth.js';
import * as auth from './service.js';

export const authRouter = Router();

const otpLimiter = rateLimit({ windowMs: 15 * 60_000, limit: isTest ? 1000 : 20, standardHeaders: 'draft-8', legacyHeaders: false, message: { error: { code: 'RATE_LIMITED', message: 'Too many requests' } } });

authRouter.post('/otp/request', otpLimiter, async (req, res) => {
  const b = body(req, z.object({ phone: z.string().min(6).max(20), channel: z.enum(['sms', 'whatsapp']).default('sms') }));
  res.json({ data: await auth.requestOtp(b.phone, b.channel, req.ip) });
});

authRouter.post('/otp/verify', otpLimiter, async (req, res) => {
  const b = body(req, z.object({ phone: z.string().min(6).max(20), code: z.string().regex(/^\d{4,8}$/), deviceId: z.string().min(4).max(200), deviceName: z.string().max(200).optional() }));
  res.json({ data: await auth.verifyOtp(b) });
});

authRouter.post('/refresh', async (req, res) => {
  const b = body(req, z.object({ refreshToken: z.string().min(10) }));
  res.json({ data: await auth.refresh(b.refreshToken) });
});

authRouter.post('/logout', async (req, res) => {
  const b = body(req, z.object({ refreshToken: z.string().min(10) }));
  await auth.logout(b.refreshToken);
  res.json({ data: { ok: true } });
});

// Open another of this person's businesses on the current device.
authRouter.post('/switch', authenticate, async (req, res) => {
  const b = body(req, z.object({ membershipId: z.string().regex(/^[a-f0-9]{24}$/), deviceId: z.string().min(4).max(200), refreshToken: z.string().max(200).optional() }));
  res.json({ data: await auth.switchMembership(req.auth!.userId, b) });
});
