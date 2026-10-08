import type { EmailProvider } from '../types.js';
import { AppError } from '../../lib/errors.js';

export class ResendEmailProvider implements EmailProvider {
  readonly name = 'resend';
  constructor(private cfg: { apiKey: string; from: string }) {}
  async send(to: string, subject: string, html: string, attachments?: { filename: string; content: Buffer }[]) {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { authorization: `Bearer ${this.cfg.apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ from: this.cfg.from, to, subject, html, attachments: attachments?.map((a) => ({ filename: a.filename, content: a.content.toString('base64') })) }),
    });
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok) throw new AppError('PROVIDER_ERROR', `Resend: ${json?.message ?? res.status}`);
    return { id: json.id };
  }
}
