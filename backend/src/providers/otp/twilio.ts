import type { OtpProvider } from '../types.js';
import { AppError } from '../../lib/errors.js';

export class TwilioOtpProvider implements OtpProvider {
  readonly name = 'twilio';
  constructor(private cfg: { accountSid: string; authToken: string; from: string }) {}
  async send(phone: string, code: string, channel: 'sms' | 'whatsapp') {
    const to = channel === 'whatsapp' ? `whatsapp:${phone}` : phone;
    const from = channel === 'whatsapp' ? `whatsapp:${this.cfg.from}` : this.cfg.from;
    const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${this.cfg.accountSid}/Messages.json`, {
      method: 'POST',
      headers: {
        authorization: 'Basic ' + Buffer.from(`${this.cfg.accountSid}:${this.cfg.authToken}`).toString('base64'),
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ To: to, From: from, Body: `${code} is your StaffMint code. Do not share it.` }),
    });
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok) throw new AppError('PROVIDER_ERROR', `Twilio: ${json.message ?? res.status}`);
    return { providerRef: json.sid };
  }
}
