import type { OtpProvider } from '../types.js';
import { AppError } from '../../lib/errors.js';

/** MSG91 OTP API — we generate the code; MSG91 delivers it via the DLT-approved template. */
export class Msg91OtpProvider implements OtpProvider {
  readonly name = 'msg91';
  constructor(private cfg: { authKey: string; templateId: string }) {}
  async send(phone: string, code: string, _channel: 'sms' | 'whatsapp') {
    const mobile = phone.replace('+', '');
    const url = `https://control.msg91.com/api/v5/otp?template_id=${encodeURIComponent(this.cfg.templateId)}&mobile=${mobile}&otp=${code}`;
    const res = await fetch(url, { method: 'POST', headers: { authkey: this.cfg.authKey, 'content-type': 'application/json' }, body: '{}' });
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok || json.type === 'error') throw new AppError('PROVIDER_ERROR', `MSG91: ${json.message ?? res.status}`);
    return { providerRef: json.request_id };
  }
}
