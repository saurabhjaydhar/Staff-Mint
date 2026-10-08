import type { OtpProvider } from '../types.js';
import { logger } from '../../lib/logger.js';

export class MockOtpProvider implements OtpProvider {
  readonly name = 'mock';
  async send(phone: string, code: string, channel: 'sms' | 'whatsapp') {
    logger.info({ phone, channel }, `[mock-otp] code for ${phone}: ${code}`);
    return { providerRef: `mock_${Date.now()}`, devCode: code };
  }
}
