import { describe, expect, it } from 'vitest';
import crypto from 'node:crypto';
import { MockMessagingProvider } from '../src/providers/messaging/mock.js';
import { MetaCloudMessagingProvider } from '../src/providers/messaging/meta.js';
import { AiSensyMessagingProvider } from '../src/providers/messaging/aisensy.js';
import { MockPaymentProvider } from '../src/providers/payments/mock.js';
import { RazorpayPaymentProvider } from '../src/providers/payments/razorpay.js';
import { LocalStorageProvider } from '../src/providers/storage/local.js';
import { SimplePdfRenderer } from '../src/providers/pdf/simple.js';
import { MockOtpProvider } from '../src/providers/otp/mock.js';
import { RulesLlmProvider } from '../src/providers/llm/rules.js';
import type { MessagingProvider, PaymentProvider } from '../src/providers/types.js';
import os from 'node:os';
import path from 'node:path';

const hmac = (secret: string, body: string) => crypto.createHmac('sha256', secret).update(body).digest('hex');

/** Shared contract every MessagingProvider must satisfy (PRD §16 rule 5). */
function messagingContract(name: string, make: () => MessagingProvider, inbound: { body: any; headers: (raw: string) => Record<string, string> }) {
  describe(`MessagingProvider contract: ${name}`, () => {
    it('verifies signatures and parses inbound messages into internal events', () => {
      const m = make();
      const raw = JSON.stringify(inbound.body);
      expect(m.verifyWebhook(inbound.headers(raw), Buffer.from(raw))).toBe(true);
      const ev = m.parseWebhook(inbound.body);
      expect(ev[0]).toMatchObject({ type: 'message.inbound', from: '+919876543210', text: 'Kaun late aaya?' });
    });
    it('rejects bad signatures (except mock)', () => {
      const m = make();
      if (m.name === 'mock') return;
      expect(m.verifyWebhook({}, Buffer.from('{}'))).toBe(false);
    });
  });
}

messagingContract('mock', () => new MockMessagingProvider(), { body: { from: '+919876543210', text: 'Kaun late aaya?' }, headers: () => ({}) });
messagingContract('meta', () => new MetaCloudMessagingProvider({ token: 't', phoneNumberId: '1', appSecret: 'app-secret', graphVersion: 'v21.0' }), {
  body: { entry: [{ changes: [{ value: { messages: [{ from: '919876543210', id: 'wamid.X', timestamp: '1760000000', text: { body: 'Kaun late aaya?' } }] } }] }] },
  headers: (raw) => ({ 'x-hub-signature-256': `sha256=${hmac('app-secret', raw)}` }),
});
messagingContract('aisensy', () => new AiSensyMessagingProvider({ apiKey: 'k', webhookSecret: 'ws' }), {
  body: { data: { message: { from: '919876543210', id: 'm1', text: { body: 'Kaun late aaya?' } } } },
  headers: (raw) => ({ 'x-aisensy-signature': hmac('ws', raw) }),
});

function paymentContract(name: string, make: () => PaymentProvider, activated: { body: any; headers: (raw: string) => Record<string, string> }) {
  describe(`PaymentProvider contract: ${name}`, () => {
    it('translates vendor webhooks into internal events', () => {
      const p = make();
      const raw = JSON.stringify(activated.body);
      expect(p.verifyWebhook(activated.headers(raw), Buffer.from(raw))).toBe(true);
      const [ev] = p.parseWebhook(activated.body);
      expect(ev).toMatchObject({ type: 'subscription.activated', providerSubId: 'sub_123' });
      expect(ev.eventId).toBeTruthy();
    });
  });
}
paymentContract('mock', () => new MockPaymentProvider(), { body: { id: 'e1', event: 'subscription.activated', subscriptionId: 'sub_123' }, headers: () => ({}) });
paymentContract('razorpay', () => new RazorpayPaymentProvider({ keyId: 'k', keySecret: 's', webhookSecret: 'whs' }), {
  body: { id: 'evt', event: 'subscription.activated', payload: { subscription: { entity: { id: 'sub_123', current_end: 1790000000 } } } },
  headers: (raw) => ({ 'x-razorpay-signature': hmac('whs', raw) }),
});

describe('StorageProvider contract: local', () => {
  it('put/get/delete and signed URLs', async () => {
    const s = new LocalStorageProvider({ dir: path.join(os.tmpdir(), 'sm-contract'), publicBaseUrl: 'http://x', secret: 'sec' });
    await s.put('a/b.txt', Buffer.from('hi'), 'text/plain');
    expect((await s.get('a/b.txt')).toString()).toBe('hi');
    expect(await s.signedUrl('a/b.txt', 60)).toMatch(/^http:\/\/x\/files\/a\/b\.txt\?exp=\d+&sig=[a-f0-9]{64}$/);
    await s.delete('a/b.txt');
    await expect(s.get('a/b.txt')).rejects.toThrow();
    await expect(s.put('../../etc/x', Buffer.from(''), 'text/plain')).rejects.toThrow(/Invalid key/);
  });
});

describe('other adapters', () => {
  it('simple PDF renderer produces a valid PDF', async () => {
    const pdf = await new SimplePdfRenderer().render('<h1>Payslip</h1><p>Net ₹12,000</p>');
    expect(pdf.subarray(0, 8).toString()).toBe('%PDF-1.4');
    expect(pdf.toString('latin1')).toContain('Rs.12,000');
  });
  it('mock OTP returns the dev code', async () => expect((await new MockOtpProvider().send('+919876543210', '123456', 'sms')).devCode).toBe('123456'));
  it('rules LLM adapter extracts intents', async () => {
    const r = await new RulesLlmProvider().extract({ text: 'Kaun late aaya?', tools: [], context: { today: '2026-10-08', language: 'hi', employeeNames: [], role: 'owner' } });
    expect(r).toMatchObject({ intent: 'who_is', provider: 'rules' });
  });
});
