import type { VerificationProvider, VerifyRecord } from '../types.js';

/**
 * Cashfree Verification Suite ("Secure ID"). Built from Cashfree's API reference
 * (https://docs.cashfree.com/v3/reference/verification-api-overview); check each call with sandbox keys
 * before going live. Approximate prices are what Cashfree lists; the real bill is on their dashboard.
 */
export class CashfreeVerificationProvider implements VerificationProvider {
  readonly name = 'cashfree';
  private readonly base: string;

  constructor(private readonly opts: { clientId: string; clientSecret: string; env: 'sandbox' | 'production' }) {
    this.base = opts.env === 'production' ? 'https://api.cashfree.com/verification' : 'https://sandbox.cashfree.com/verification';
  }

  private async post(path: string, body: Record<string, unknown>) {
    const r = await fetch(`${this.base}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-client-id': this.opts.clientId, 'x-client-secret': this.opts.clientSecret },
      body: JSON.stringify(body),
    });
    const data: any = await r.json().catch(() => ({}));
    if (!r.ok) {
      const err = new Error(data?.message ?? `Cashfree ${path} failed (${r.status})`) as Error & { code?: string; status?: number };
      err.code = data?.code ?? data?.type;
      err.status = r.status;
      throw err;
    }
    return data;
  }

  async verifyPan({ pan, name }: { pan: string; name: string }): Promise<VerifyRecord> {
    const d = await this.post('/pan', { pan, name });
    return { found: d.valid === true, nameOnRecord: d.registered_name ?? null, providerRef: d.reference_id != null ? String(d.reference_id) : null, costPaise: 150 };
  }

  async verifyBank({ accountNumber, ifsc, name, phone }: { accountNumber: string; ifsc: string; name: string; phone?: string }): Promise<VerifyRecord> {
    const d = await this.post('/bank-account/sync', { bank_account: accountNumber, ifsc, name, ...(phone ? { phone } : {}) });
    return {
      found: d.account_status === 'VALID',
      nameOnRecord: d.name_at_bank ?? null,
      providerRef: d.reference_id != null ? String(d.reference_id) : null,
      costPaise: 300,
      details: d.bank_name ? { bankName: String(d.bank_name) } : undefined,
    };
  }

  async aadhaarSendOtp({ aadhaar }: { aadhaar: string }) {
    const d = await this.post('/offline-aadhaar/otp', { aadhaar_number: aadhaar });
    return { ref: String(d.ref_id) };
  }

  async aadhaarVerifyOtp({ ref, otp }: { ref: string; otp: string }): Promise<VerifyRecord> {
    const d = await this.post('/offline-aadhaar/verify', { ref_id: ref, otp });
    const ok = d.status === 'VALID';
    // Keep only what helps the owner; never the Aadhaar number or the photo.
    const details: Record<string, string> = {};
    if (d.dob) details.dob = String(d.dob);
    if (d.gender) details.gender = String(d.gender);
    if (d.split_address?.state) details.state = String(d.split_address.state);
    return { found: ok, nameOnRecord: d.name ?? null, providerRef: ref, costPaise: 1500, details };
  }
}
