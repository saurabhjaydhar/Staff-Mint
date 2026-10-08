import type { AnalyticsProvider } from '../types.js';
import { logger } from '../../lib/logger.js';

export class PostHogAnalyticsProvider implements AnalyticsProvider {
  readonly name = 'posthog';
  constructor(private cfg: { apiKey: string; host: string }) {}
  capture(distinctId: string, event: string, properties?: Record<string, unknown>) {
    fetch(`${this.cfg.host}/capture/`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ api_key: this.cfg.apiKey, event, distinct_id: distinctId, properties }),
    }).catch((e) => logger.warn({ err: e }, 'posthog capture failed'));
  }
}
