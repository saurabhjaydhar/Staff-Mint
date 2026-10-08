import { Router } from 'express';
import { env } from '../../config/env.js';
import { AppError } from '../../lib/errors.js';
import { provider } from '../../providers/registry.js';
import { processMessagingEvents } from './service.js';
import { logger } from '../../lib/logger.js';

export const messagingWebhookRouter = Router();

/** Meta webhook verification handshake. */
messagingWebhookRouter.get('/:provider', (req, res) => {
  if (req.query['hub.mode'] === 'subscribe' && req.query['hub.verify_token'] === env.WHATSAPP_VERIFY_TOKEN) return res.status(200).send(String(req.query['hub.challenge'] ?? ''));
  res.status(403).send('forbidden');
});

messagingWebhookRouter.post('/:provider', async (req, res) => {
  const name = String(req.params.provider);
  const m = await provider('messaging', name).catch(() => null);
  if (!m) throw new AppError('NOT_FOUND', 'Unknown provider');
  if (!m.verifyWebhook(req.headers, req.rawBody ?? Buffer.from(JSON.stringify(req.body ?? {})))) throw new AppError('UNAUTHORIZED', 'Bad signature');
  const events = m.parseWebhook(req.body);
  // Acknowledge fast (Meta retries slow webhooks); process after responding.
  res.json({ ok: true });
  processMessagingEvents(m.name, events).catch((err) => logger.error({ err }, 'messaging webhook processing failed'));
});
