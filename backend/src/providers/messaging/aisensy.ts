import type { MessagingEvent, MessagingProvider, MessageButton } from '../types.js';
import { AppError } from '../../lib/errors.js';
import { hmacSha256Hex, safeEqual } from '../../lib/crypto.js';

/**
 * AiSensy BSP adapter (campaign API). AiSensy sends templates by "campaign name";
 * configure one API campaign per template with the same name as our template key.
 * Free-form session messages are not supported by the campaign API → we fall back to a
 * generic "mint_reply" template carrying the text.
 */
export class AiSensyMessagingProvider implements MessagingProvider {
  readonly name = 'aisensy';
  constructor(private cfg: { apiKey: string; webhookSecret: string }) {}

  private async campaign(to: string, campaignName: string, params: string[], media?: { url: string; filename: string }) {
    const res = await fetch('https://backend.aisensy.com/campaign/t1/api/v2', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ apiKey: this.cfg.apiKey, campaignName, destination: to.replace('+', ''), userName: 'StaffMint', templateParams: params, media }),
    });
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok || json.success === false) throw new AppError('PROVIDER_ERROR', `AiSensy: ${json.message ?? res.status}`);
    return { providerMsgId: String(json.submitted_message_id ?? json.messageId ?? `aisensy_${Date.now()}`) };
  }
  sendTemplate(to: string, template: string, params: string[], opts?: { documentUrl?: string; filename?: string }) {
    return this.campaign(to, template, params, opts?.documentUrl ? { url: opts.documentUrl, filename: opts.filename ?? 'document.pdf' } : undefined);
  }
  sendText(to: string, text: string) {
    return this.campaign(to, 'mint_reply', [text.slice(0, 1000)]);
  }
  sendButtons(to: string, body: string, buttons: MessageButton[]) {
    return this.campaign(to, 'mint_reply', [`${body}\n\n${buttons.map((b, i) => `${i + 1}. ${b.title}`).join('\n')}`]);
  }
  sendDocument(to: string, url: string, filename: string, caption?: string) {
    return this.campaign(to, 'document_share', [caption ?? filename], { url, filename });
  }
  verifyWebhook(headers: Record<string, string | string[] | undefined>, rawBody: Buffer): boolean {
    const sig = String(headers['x-aisensy-signature'] ?? '');
    return !!sig && safeEqual(sig, hmacSha256Hex(this.cfg.webhookSecret, rawBody));
  }
  parseWebhook(body: any): MessagingEvent[] {
    // AiSensy forwards Meta-shaped payloads under `data` for inbound messages.
    const m = body?.data?.message ?? body?.message;
    if (m?.from) return [{ type: 'message.inbound', from: `+${String(m.from).replace('+', '')}`, text: m.text?.body ?? m.text, buttonId: m.button?.payload, providerMsgId: m.id, at: new Date() }];
    if (body?.data?.status) return [{ type: 'message.status', providerMsgId: body.data.messageId, status: body.data.status }];
    return [];
  }
}
