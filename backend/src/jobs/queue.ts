import { env } from '../config/env.js';
import { logger } from '../lib/logger.js';
import type { JobName } from './handlers.js';

/**
 * Job queue facade.
 *  - bullmq: Redis-backed queue; run `npm run worker` (dist/worker.js) to process.
 *  - inline: run handlers in-process (dev, tests, single small VPS).
 *  - off:    drop jobs (one-off scripts).
 */
let bull: { queue: any } | null = null;

async function bullQueue() {
  if (!bull) {
    const { Queue } = await import('bullmq');
    const { Redis } = await import('ioredis');
    const connection = new Redis(env.REDIS_URL, { maxRetriesPerRequest: null });
    bull = { queue: new Queue('staffmint', { connection, defaultJobOptions: { attempts: 3, backoff: { type: 'exponential', delay: 5000 }, removeOnComplete: 1000, removeOnFail: 5000 } }) };
  }
  return bull.queue;
}

export async function enqueue(name: JobName, data: Record<string, unknown>) {
  if (env.JOBS_DRIVER === 'off') return;
  if (env.JOBS_DRIVER === 'bullmq') {
    await (await bullQueue()).add(name, data);
    return;
  }
  const { handlers } = await import('./handlers.js');
  try {
    await handlers[name](data);
  } catch (err) {
    logger.error({ err, job: name }, 'inline job failed');
  }
}

let timer: NodeJS.Timeout | null = null;

/** Start the periodic scheduler (inline driver) or register the repeatable job (bullmq). */
export async function startScheduler(intervalMs = 5 * 60_000) {
  if (env.JOBS_DRIVER === 'off') return;
  if (env.JOBS_DRIVER === 'bullmq') {
    await (await bullQueue()).upsertJobScheduler('scheduler', { every: intervalMs }, { name: 'scheduler.tick', data: {} });
    return;
  }
  const { handlers } = await import('./handlers.js');
  const tick = () => handlers['scheduler.tick']({}).catch((err) => logger.error({ err }, 'scheduler tick failed'));
  timer = setInterval(tick, intervalMs);
  setTimeout(tick, 10_000);
}

export async function stopScheduler() {
  if (timer) clearInterval(timer);
  timer = null;
  if (bull) await bull.queue.close();
  bull = null;
}
