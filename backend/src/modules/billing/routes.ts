import { Router } from 'express';
import { z } from 'zod';
import { body, objectId, param } from '../../lib/http.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { AppError } from '../../lib/errors.js';
import { isProd } from '../../config/env.js';
import { provider } from '../../providers/registry.js';
import { listPlans } from './plans.js';
import { requireBillingAccess } from '../accounts/owners.js';
import * as svc from './service.js';
import * as group from './group.js';

export const billingRouter = Router();

billingRouter.get('/plans', async (req, res) => {
  res.json({ data: await listPlans(String(req.query.country ?? 'IN')) });
});
billingRouter.get('/subscription', authenticate, requireRole('owner'), requireBillingAccess, async (req, res) => {
  res.json({ data: await svc.subscriptionSummary(ctxOf(req)) });
});
billingRouter.post('/subscribe', authenticate, requireRole('owner'), requireBillingAccess, async (req, res) => {
  const b = body(req, z.object({ planCode: z.string(), interval: z.enum(['monthly', 'yearly']).default('monthly') }));
  res.json({ data: await svc.subscribe(ctxOf(req), b.planCode, b.interval) });
});
billingRouter.post('/cancel', authenticate, requireRole('owner'), requireBillingAccess, async (req, res) => {
  const sub = await svc.cancel(ctxOf(req));
  res.json({ data: { subscription: { status: sub.status, planCode: sub.planCode, currentPeriodEnd: sub.currentPeriodEnd ?? null } } });
});

// One bill for several businesses (main owner / billing-allowed co-owner of the paying business).
billingRouter.get('/group', authenticate, requireRole('owner'), requireBillingAccess, async (req, res) => {
  res.json({ data: await group.billingGroup(ctxOf(req)) });
});
billingRouter.post('/group/members', authenticate, requireRole('owner'), requireBillingAccess, async (req, res) => {
  const b = body(req, z.object({ companyId: objectId }));
  res.json({ data: await group.addToBill(ctxOf(req), b.companyId) });
});
billingRouter.delete('/group/members/:companyId', authenticate, requireRole('owner'), requireBillingAccess, async (req, res) => {
  res.json({ data: await group.removeFromBill(ctxOf(req), param(req, 'companyId')) });
});

export const paymentsWebhookRouter = Router();
paymentsWebhookRouter.post('/:provider', async (req, res) => {
  const name = String(req.params.provider);
  const p = await provider('payments', name).catch(() => null);
  if (!p) throw new AppError('NOT_FOUND', 'Unknown provider');
  if (!p.verifyWebhook(req.headers, req.rawBody ?? Buffer.from(JSON.stringify(req.body ?? {})))) throw new AppError('UNAUTHORIZED', 'Bad signature');
  await svc.handlePaymentEvents(p.name, p.parseWebhook(req.body));
  res.json({ ok: true });
});

/** Dev-only fake checkout for PAYMENT_PROVIDER=mock. */
export const mockCheckoutRouter = Router();
mockCheckoutRouter.get('/', async (req, res) => {
  if (isProd) throw new AppError('NOT_FOUND', 'Not found');
  const sub = String(req.query.sub ?? '');
  await svc.handlePaymentEvents('mock', [{ type: 'subscription.activated', eventId: `checkout-${sub}`, providerSubId: sub, raw: { sub } }]);
  res.type('html').send(`<html><body style="font-family:sans-serif;text-align:center;padding:40px"><h2 style="color:#2BB673">Payment successful (mock)</h2><p>Subscription ${sub} is now active. You can close this window.</p></body></html>`);
});
