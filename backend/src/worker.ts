import { Worker } from 'bullmq';
import { Redis } from 'ioredis';
import { env, assertProductionConfig } from './config/env.js';
import { connectDb } from './db.js';
import { logger } from './lib/logger.js';
import { handlers, type JobName } from './jobs/handlers.js';
import { startScheduler } from './jobs/queue.js';

/** BullMQ worker process (JOBS_DRIVER=bullmq). */
async function main() {
  assertProductionConfig();
  await connectDb();
  const connection = new Redis(env.REDIS_URL, { maxRetriesPerRequest: null });
  const worker = new Worker('staffmint', async (job) => handlers[job.name as JobName](job.data), { connection, concurrency: 4 });
  worker.on('failed', (job, err) => logger.error({ err, job: job?.name }, 'job failed'));
  worker.on('completed', (job) => logger.debug({ job: job.name }, 'job done'));
  await startScheduler();
  logger.info('Worker started');
  const shutdown = async () => {
    await worker.close();
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((err) => {
  logger.error({ err }, 'worker crashed');
  process.exit(1);
});
