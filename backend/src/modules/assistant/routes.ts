import { Router } from 'express';
import { z } from 'zod';
import { body } from '../../lib/http.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { AppError } from '../../lib/errors.js';
import * as svc from './service.js';

export const assistantRouter = Router();
assistantRouter.use(authenticate);

assistantRouter.post('/message', requireRole('owner', 'manager', 'employee'), async (req, res) => {
  const b = body(req, z.object({ text: z.string().max(1000).optional(), audioBase64: z.string().max(8_000_000).optional(), audioMime: z.string().max(60).optional(), sessionId: z.string().optional() }));
  if (!b.text && !b.audioBase64) throw new AppError('VALIDATION_ERROR', 'Send text or audio');
  const audio = b.audioBase64 ? { data: Buffer.from(b.audioBase64, 'base64'), mime: b.audioMime ?? 'audio/m4a' } : undefined;
  res.json({ data: await svc.handleMessage({ ...ctxOf(req), channel: 'assistant' }, { text: b.text, audio, sessionId: b.sessionId }) });
});

assistantRouter.post('/confirm', requireRole('owner', 'manager', 'employee'), async (req, res) => {
  const b = body(req, z.object({ pendingActionId: z.string().min(8), action: z.enum(['confirm', 'cancel', 'choose']), optionId: z.string().optional() }));
  res.json({ data: await svc.confirm({ ...ctxOf(req), channel: 'assistant' }, b) });
});
