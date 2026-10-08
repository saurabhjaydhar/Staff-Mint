import type { MessagingEvent, MessagingProvider, MessageButton } from '../types.js';
import { AppError } from '../../lib/errors.js';
import { hmacSha256Hex, safeEqual } from '../../lib/crypto.js';

/** Meta WhatsApp Cloud API adapter. */
export class MetaCloudMessagingProvider implements MessagingProvider {
  readonly name = 'meta';
  constructor(private cfg: { token: string; phoneNumberId: string; appSecret: string; graphVersion: string }) {}

  private async post(payload: Record<string, unknown>) {
    const res = await fetch(`https://graph.facebook.com/${this.cfg.graphVersion}/${this.cfg.phoneNumberId}/messages`, {
      method: 'POST',
      headers: { authorization: `Bearer ${this.cfg.token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', ...payload }),
    });
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok) throw new AppError('PROVIDER_ERROR', `WhatsApp: ${json?.error?.message ?? res.status}`);
    return { providerMsgId: json.messages?.[0]?.id as string };
  }
  private to(phone: string) {
    return phone.replace('+', '');
  }

  sendTemplate(to: string, template: string, params: string[], opts?: { language?: 'en' | 'hi'; buttons?: MessageButton[]; documentUrl?: string; filename?: string }) {
    const components: any[] = [];
    if (opts?.documentUrl) components.push({ type: 'header', parameters: [{ type: 'document', document: { link: opts.documentUrl, filename: opts.filename ?? 'document.pdf' } }] });
    if (params.length) components.push({ type: 'body', parameters: params.map((text) => ({ type: 'text', text })) });
    opts?.buttons?.forEach((b, index) => components.push({ type: 'button', sub_type: 'quick_reply', index: String(index), parameters: [{ type: 'payload', payload: b.id }] }));
    return this.post({ to: this.to(to), type: 'template', template: { name: template, language: { code: opts?.language === 'en' ? 'en' : 'hi' }, components } });
  }
  sendText(to: string, text: string) {
    return this.post({ to: this.to(to), type: 'text', text: { body: text.slice(0, 4096) } });
  }
  sendButtons(to: string, body: string, buttons: MessageButton[]) {
    return this.post({
      to: this.to(to),
      type: 'interactive',
      interactive: { type: 'button', body: { text: body.slice(0, 1024) }, action: { buttons: buttons.slice(0, 3).map((b) => ({ type: 'reply', reply: { id: b.id, title: b.title.slice(0, 20) } })) } },
    });
  }
  sendDocument(to: string, url: string, filename: string, caption?: string) {
    return this.post({ to: this.to(to), type: 'document', document: { link: url, filename, caption } });
  }
  verifyWebhook(headers: Record<string, string | string[] | undefined>, rawBody: Buffer): boolean {
    const sig = String(headers['x-hub-signature-256'] ?? '');
    if (!sig.startsWith('sha256=')) return false;
    return safeEqual(sig.slice(7), hmacSha256Hex(this.cfg.appSecret, rawBody));
  }
  parseWebhook(body: any): MessagingEvent[] {
    const events: MessagingEvent[] = [];
    for (const entry of body?.entry ?? []) {
      for (const change of entry.changes ?? []) {
        const v = change.value ?? {};
        for (const m of v.messages ?? []) {
          events.push({
            type: 'message.inbound',
            from: `+${m.from}`,
            text: m.text?.body ?? m.button?.text,
            buttonId: m.interactive?.button_reply?.id ?? m.button?.payload,
            audio: m.audio ? { mediaId: m.audio.id, mime: m.audio.mime_type } : undefined,
            providerMsgId: m.id,
            at: new Date(Number(m.timestamp) * 1000),
          });
        }
        for (const s of v.statuses ?? []) {
          events.push({ type: 'message.status', providerMsgId: s.id, status: s.status, error: s.errors?.[0]?.title });
        }
      }
    }
    return events;
  }
  async fetchMedia(mediaId: string) {
    const meta: any = await (await fetch(`https://graph.facebook.com/${this.cfg.graphVersion}/${mediaId}`, { headers: { authorization: `Bearer ${this.cfg.token}` } })).json();
    const res = await fetch(meta.url, { headers: { authorization: `Bearer ${this.cfg.token}` } });
    return { data: Buffer.from(await res.arrayBuffer()), mime: meta.mime_type ?? 'audio/ogg' };
  }
}
