import * as Sentry from '@sentry/node';
import { env, assertProductionConfig } from './config/env.js';
import { connectDb, disconnectDb } from './db.js';
import { logger } from './lib/logger.js';
import { createApp } from './app.js';
import { startScheduler, stopScheduler } from './jobs/queue.js';
import { seedDefaults } from './scripts/seedDefaults.js';

async function main() {
  assertProductionConfig();
  if (env.SENTRY_DSN) Sentry.init({ dsn: env.SENTRY_DSN, environment: env.NODE_ENV, tracesSampleRate: 0.1 });
  await connectDb();
  await seedDefaults();
  const app = createApp();
  const server = app.listen(env.PORT, () => logger.info(`StaffMint API listening on :${env.PORT}`));
  await startScheduler();
  const shutdown = async (sig: string) => {
    logger.info(`${sig} received, shutting down`);
    server.close();
    await stopScheduler();
    await disconnectDb();
    process.exit(0);
  };
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
}

main().catch((err) => {
  logger.error({ err }, 'Failed to start');
  process.exit(1);
});
