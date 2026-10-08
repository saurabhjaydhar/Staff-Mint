import type { PushMessage, PushProvider } from '../types.js';
import { logger } from '../../lib/logger.js';

export class MockPushProvider implements PushProvider {
  readonly name = 'mock';
  readonly sent: { tokens: string[]; msg: PushMessage }[] = [];
  async send(tokens: string[], msg: PushMessage) {
    this.sent.push({ tokens, msg });
    logger.debug({ count: tokens.length, title: msg.title }, '[mock-push] sent');
    return { successCount: tokens.length, invalidTokens: [] };
  }
}
