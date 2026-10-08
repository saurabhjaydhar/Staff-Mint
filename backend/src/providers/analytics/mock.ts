import type { AnalyticsProvider } from '../types.js';

export class MockAnalyticsProvider implements AnalyticsProvider {
  readonly name = 'mock';
  readonly events: { distinctId: string; event: string; properties?: Record<string, unknown> }[] = [];
  capture(distinctId: string, event: string, properties?: Record<string, unknown>) {
    if (this.events.length > 1000) this.events.shift();
    this.events.push({ distinctId, event, properties });
  }
}
