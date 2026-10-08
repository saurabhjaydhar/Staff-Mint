import type { EmailProvider } from '../types.js';
import { logger } from '../../lib/logger.js';

export class MockEmailProvider implements EmailProvider {
  readonly name = 'mock';
  readonly sent: { to: string; subject: string }[] = [];
  async send(to: string, subject: string) {
    this.sent.push({ to, subject });
    logger.debug({ to, subject }, '[mock-email] sent');
    return { id: `mockmail_${Date.now()}` };
  }
}
