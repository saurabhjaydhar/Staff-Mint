import type { VerificationProvider, VerifyRecord } from '../types.js';

/**
 * Deterministic stand-in for development and tests (no money spent):
 * - PAN starting with "ZZ" isn't found; ending with "Z" belongs to someone with a different name.
 * - Bank account ending "0000" isn't found; ending "9" is held under a shorter name.
 * - Aadhaar OTP is always 123456; an Aadhaar starting with "9999" isn't found.
 */
export class MockVerificationProvider implements VerificationProvider {
  readonly name = 'mock';
  private seq = 0;
  private readonly otp = new Map<string, string>();

  private ref() {
    return `mockver_${++this.seq}`;
  }

  async verifyPan({ pan, name }: { pan: string; name: string }): Promise<VerifyRecord> {
    if (pan.startsWith('ZZ')) return { found: false, nameOnRecord: null, providerRef: this.ref(), costPaise: 200 };
    const nameOnRecord = pan.endsWith('Z') ? 'Rajesh Kumar Sharma' : name.toUpperCase();
    return { found: true, nameOnRecord, providerRef: this.ref(), costPaise: 200 };
  }

  async verifyBank({ accountNumber, name }: { accountNumber: string; ifsc: string; name: string }): Promise<VerifyRecord> {
    if (accountNumber.endsWith('0000')) return { found: false, nameOnRecord: null, providerRef: this.ref(), costPaise: 300 };
    const nameOnRecord = accountNumber.endsWith('9') ? name.split(' ')[0].toUpperCase() : name.toUpperCase();
    return { found: true, nameOnRecord, providerRef: this.ref(), costPaise: 300, details: { bankName: 'State Bank of India' } };
  }

  async aadhaarSendOtp({ aadhaar }: { aadhaar: string }) {
    const ref = this.ref();
    this.otp.set(ref, aadhaar);
    return { ref };
  }

  async aadhaarVerifyOtp({ ref, otp }: { ref: string; otp: string }): Promise<VerifyRecord> {
    const aadhaar = this.otp.get(ref);
    if (!aadhaar || otp !== '123456') throw new Error('OTP_INVALID');
    this.otp.delete(ref);
    if (aadhaar.startsWith('9999')) return { found: false, nameOnRecord: null, providerRef: ref, costPaise: 1500 };
    return { found: true, nameOnRecord: null, providerRef: ref, costPaise: 1500, details: { dob: '1995-04-12', gender: 'M', state: 'Delhi' } };
  }
}
