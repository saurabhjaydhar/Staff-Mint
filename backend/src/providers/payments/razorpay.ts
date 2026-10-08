import type { CreateSubscriptionInput, PaymentEvent, PaymentProvider } from '../types.js';
import { AppError } from '../../lib/errors.js';
import { hmacSha256Hex, safeEqual } from '../../lib/crypto.js';

/** Razorpay Subscriptions via REST. Plans must exist in Razorpay (ids stored in plans.providerPlanIds.razorpay). */
export class RazorpayPaymentProvider implements PaymentProvider {
  readonly name = 'razorpay';
  constructor(private cfg: { keyId: string; keySecret: string; webhookSecret: string }) {}
  private async call(method: string, path: string, body?: unknown) {
    const res = await fetch(`https://api.razorpay.com/v1${path}`, {
      method,
      headers: { authorization: 'Basic ' + Buffer.from(`${this.cfg.keyId}:${this.cfg.keySecret}`).toString('base64'), 'content-type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok) throw new AppError('PROVIDER_ERROR', `Razorpay: ${json?.error?.description ?? res.status}`);
    return json;
  }
  async createSubscription(input: CreateSubscriptionInput) {
    if (!input.providerPlanId) throw new AppError('PROVIDER_ERROR', `Razorpay plan id missing for ${input.planCode}/${input.interval}`);
    const startAt = input.trialDays ? Math.floor(Date.now() / 1000) + input.trialDays * 86400 : undefined;
    const sub = await this.call('POST', '/subscriptions', {
      plan_id: input.providerPlanId,
      total_count: input.interval === 'yearly' ? 10 : 120,
      customer_notify: 1,
      start_at: startAt,
      notes: { companyId: input.customer.companyId, planCode: input.planCode },
    });
    return { providerSubId: sub.id as string, checkoutUrl: sub.short_url as string, keyId: this.cfg.keyId };
  }
  async cancelSubscription(providerSubId: string) {
    await this.call('POST', `/subscriptions/${providerSubId}/cancel`, { cancel_at_cycle_end: 1 });
  }
  verifyWebhook(headers: Record<string, string | string[] | undefined>, rawBody: Buffer): boolean {
    const sig = String(headers['x-razorpay-signature'] ?? '');
    return !!sig && safeEqual(sig, hmacSha256Hex(this.cfg.webhookSecret, rawBody));
  }
  parseWebhook(body: any): PaymentEvent[] {
    const eventId = String(body?.id ?? body?.created_at ?? Date.now()) + ':' + body?.event;
    const sub = body?.payload?.subscription?.entity;
    const pay = body?.payload?.payment?.entity;
    const map: Record<string, PaymentEvent['type']> = {
      'subscription.activated': 'subscription.activated',
      'subscription.charged': 'subscription.charged',
      'subscription.pending': 'subscription.pending',
      'subscription.halted': 'subscription.halted',
      'subscription.cancelled': 'subscription.cancelled',
      'subscription.completed': 'subscription.completed',
      'payment.captured': 'payment.succeeded',
      'payment.failed': 'payment.failed',
    };
    const type = map[body?.event];
    if (!type) return [];
    if (type.startsWith('payment.')) {
      return [{ type: type as 'payment.succeeded' | 'payment.failed', eventId, providerSubId: pay?.subscription_id, providerPaymentId: pay?.id, amountPaise: pay?.amount ?? 0, raw: body }];
    }
    return [{ type: type as any, eventId, providerSubId: sub?.id, currentPeriodEnd: sub?.current_end ? new Date(sub.current_end * 1000) : undefined, raw: body }];
  }
}
