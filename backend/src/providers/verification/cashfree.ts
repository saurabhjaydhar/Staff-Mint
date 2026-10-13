import { randomUUID } from 'node:crypto';
import type { PastEmployer, VerificationProvider, VerifyRecord } from '../types.js';

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

  /** Cashfree wants our own unique id on the newer endpoints. */
  private vid() {
    return `sm_${randomUUID().replace(/-/g, '').slice(0, 24)}`;
  }

  async verifyDl({ number, dob }: { number: string; dob: string; name: string }): Promise<VerifyRecord> {
    const d = await this.post('/driving-license', { verification_id: this.vid(), dl_number: number, dob });
    const till = d.dl_validity?.non_transport?.to ?? d.dl_validity?.transport?.to ?? null;
    const details: Record<string, string> = {};
    if (till) details.validTill = String(till);
    if (d.details_of_driving_licence?.address_list?.[0]?.split_address?.state?.[0]) details.state = String(d.details_of_driving_licence.address_list[0].split_address.state[0]);
    return { found: d.status === 'VALID', nameOnRecord: d.details_of_driving_licence?.name ?? d.name ?? null, providerRef: d.reference_id != null ? String(d.reference_id) : null, costPaise: 300, details };
  }

  async verifyVoter({ epic, name }: { epic: string; name: string }): Promise<VerifyRecord> {
    const d = await this.post('/voter-id', { verification_id: this.vid(), epic_number: epic, name });
    return {
      found: d.status === 'VALID',
      nameOnRecord: d.name ?? null,
      providerRef: d.reference_id != null ? String(d.reference_id) : null,
      costPaise: 300,
      details: d.state ? { state: String(d.state) } : undefined,
    };
  }

  async verifyUan({ uan, phone }: { uan: string; name: string; phone?: string }): Promise<VerifyRecord> {
    // Employment history from the UAN. Field names are from Cashfree's reference; confirm with sandbox keys.
    const d = await this.post('/advance-employment', { verification_id: this.vid(), uan, ...(phone ? { phone: phone.replace(/^\+91/, '') } : {}) });
    const list: any[] = d.employment_history ?? d.data?.employment_history ?? [];
    const employers: PastEmployer[] = list.map((e) => ({
      name: String(e.establishment_name ?? e.employer_name ?? ''),
      joined: e.date_of_joining ?? null,
      left: e.date_of_exit ?? null,
    }));
    return {
      found: d.status === 'VALID' || d.status === 'SUCCESS',
      nameOnRecord: d.name ?? list[0]?.name ?? null,
      providerRef: d.reference_id != null ? String(d.reference_id) : null,
      costPaise: 800,
      employers: employers.filter((e) => e.name),
    };
  }
}
