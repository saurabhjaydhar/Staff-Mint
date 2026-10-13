import type { PastEmployer, VerificationProvider, VerifyRecord } from '../types.js';

/**
 * Deterministic stand-in for development and tests (no money spent):
 * - PAN starting with "ZZ" isn't found; ending with "Z" belongs to someone with a different name.
 * - Bank account ending "0000" isn't found; ending "9" is held under a shorter name.
 * - Aadhaar OTP is always 123456; an Aadhaar starting with "9999" isn't found.
 * - Driving licence, voter ID and UAN ending "0000" aren't found; ending "9" belong to someone with a different name.
 * - A licence for date of birth 2000-01-01 isn't found (the date has to match the licence).
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

  private other(id: string, name: string) {
    return id.endsWith('9') ? 'Rajesh Kumar Sharma' : name.toUpperCase();
  }

  async verifyDl({ number, dob, name }: { number: string; dob: string; name: string }): Promise<VerifyRecord> {
    if (number.endsWith('0000') || dob === '2000-01-01') return { found: false, nameOnRecord: null, providerRef: this.ref(), costPaise: 300 };
    return { found: true, nameOnRecord: this.other(number, name), providerRef: this.ref(), costPaise: 300, details: { validTill: '2034-05-20', state: 'Delhi' } };
  }

  async verifyVoter({ epic, name }: { epic: string; name: string }): Promise<VerifyRecord> {
    if (epic.endsWith('0000')) return { found: false, nameOnRecord: null, providerRef: this.ref(), costPaise: 300 };
    return { found: true, nameOnRecord: this.other(epic, name), providerRef: this.ref(), costPaise: 300, details: { state: 'Delhi' } };
  }

  async verifyUan({ uan, name }: { uan: string; name: string }): Promise<VerifyRecord> {
    if (uan.endsWith('0000')) return { found: false, nameOnRecord: null, providerRef: this.ref(), costPaise: 800 };
    const employers: PastEmployer[] = [
      { name: 'City Mart Pvt Ltd', joined: '2022-04-15', left: '2025-12-31' },
      { name: 'Sharma Traders', joined: '2019-06-01', left: '2022-03-31' },
    ];
    return { found: true, nameOnRecord: this.other(uan, name), providerRef: this.ref(), costPaise: 800, employers };
  }
}
