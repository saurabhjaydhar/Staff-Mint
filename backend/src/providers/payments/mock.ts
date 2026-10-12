import type { CreateSubscriptionInput, PaymentEvent, PaymentProvider } from '../types.js';
import { env } from '../../config/env.js';

/** Mock gateway: checkout URL points to a local page that immediately "activates" the subscription. */
export class MockPaymentProvider implements PaymentProvider {
  readonly name = 'mock';
  private seq = 0;
  async createSubscription(input: CreateSubscriptionInput) {
    const providerSubId = `mocksub_${Date.now()}_${++this.seq}`;
    return { providerSubId, checkoutUrl: `${env.PUBLIC_BASE_URL}/mock-checkout?sub=${providerSubId}&plan=${input.planCode}` };
  }
  async cancelSubscription() {}
  verifyWebhook(): boolean {
    return true;
  }
  /** body: { id, event: 'subscription.activated'|..., subscriptionId, currentPeriodEnd?, paymentId?, amountPaise? } */
  parseWebhook(body: any): PaymentEvent[] {
    if (!body?.event) return [];
    if (body.event.startsWith('payment.')) {
      return [{ type: body.event, eventId: body.id, providerSubId: body.subscriptionId, providerPaymentId: body.paymentId ?? 'mockpay', amountPaise: body.amountPaise ?? 0, raw: body }];
    }
    const payment = body.paymentId ? { id: String(body.paymentId), amountPaise: Number(body.amountPaise ?? 0) } : undefined;
    return [{ type: body.event, eventId: body.id, providerSubId: body.subscriptionId, currentPeriodEnd: body.currentPeriodEnd ? new Date(body.currentPeriodEnd) : undefined, payment, raw: body }];
  }
}
