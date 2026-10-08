import type { PushMessage, PushProvider } from '../types.js';
import { initializeApp, cert, getApps, type App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

export class FcmPushProvider implements PushProvider {
  readonly name = 'fcm';
  private app: App;
  constructor(serviceAccountBase64: string) {
    const sa = JSON.parse(Buffer.from(serviceAccountBase64, 'base64').toString('utf8'));
    this.app = getApps().find((a) => a.name === 'staffmint') ?? initializeApp({ credential: cert(sa) }, 'staffmint');
  }
  async send(tokens: string[], msg: PushMessage) {
    if (!tokens.length) return { successCount: 0, invalidTokens: [] };
    const res = await getMessaging(this.app).sendEachForMulticast({
      tokens,
      notification: { title: msg.title, body: msg.body },
      data: msg.data,
      android: { priority: 'high', notification: { channelId: 'staffmint_default' } },
    });
    const invalidTokens = res.responses
      .map((r, i) => (!r.success && /registration-token-not-registered|invalid-argument/.test(r.error?.code ?? '') ? tokens[i] : null))
      .filter((t): t is string => !!t);
    return { successCount: res.successCount, invalidTokens };
  }
}
