import type { MessagingEvent, MessagingProvider, MessageButton } from '../types.js';
import { logger } from '../../lib/logger.js';

export interface MockSentMessage {
  to: string;
  kind: 'template' | 'text' | 'buttons' | 'document';
  template?: string;
  params?: string[];
  text?: string;
  buttons?: MessageButton[];
  url?: string;
  at: Date;
}

/** In-memory outbox; inspectable from tests. Webhook payloads use a simple internal JSON shape. */
export class MockMessagingProvider implements MessagingProvider {
  readonly name = 'mock';
  readonly outbox: MockSentMessage[] = [];
  private seq = 0;
  private record(m: Omit<MockSentMessage, 'at'>) {
    this.outbox.push({ ...m, at: new Date() });
    logger.debug({ to: m.to, kind: m.kind }, '[mock-whatsapp] sent');
    return { providerMsgId: `mockmsg_${++this.seq}` };
  }
  async sendTemplate(to: string, template: string, params: string[], opts?: { buttons?: MessageButton[]; documentUrl?: string }) {
    return this.record({ to, kind: 'template', template, params, buttons: opts?.buttons, url: opts?.documentUrl });
  }
  async sendText(to: string, text: string) {
    return this.record({ to, kind: 'text', text });
  }
  async sendButtons(to: string, body: string, buttons: MessageButton[]) {
    return this.record({ to, kind: 'buttons', text: body, buttons });
  }
  async sendDocument(to: string, url: string, filename: string, caption?: string) {
    return this.record({ to, kind: 'document', url, text: caption ?? filename });
  }
  verifyWebhook(): boolean {
    return true;
  }
  /** body: { from, text?, buttonId?, id? } or { status: {id, status} } */
  parseWebhook(body: any): MessagingEvent[] {
    if (body?.status) return [{ type: 'message.status', providerMsgId: body.status.id, status: body.status.status }];
    if (body?.from) return [{ type: 'message.inbound', from: body.from, text: body.text, buttonId: body.buttonId, providerMsgId: body.id ?? `in_${Date.now()}`, at: new Date() }];
    return [];
  }
}
