import { afterAll, beforeAll, beforeEach, inject } from 'vitest';
import os from 'node:os';
import path from 'node:path';

process.env.NODE_ENV = 'test';
process.env.JOBS_DRIVER = 'inline';
process.env.LOCAL_STORAGE_DIR = path.join(os.tmpdir(), `staffmint-test-${process.pid}`);
process.env.PUBLIC_BASE_URL = 'http://test.local';

const mongoose = (await import('mongoose')).default;

beforeAll(async () => {
  const uri = inject('mongoUri');
  const dbName = `staffmint_test_${process.pid}_${Math.random().toString(36).slice(2, 8)}`;
  await mongoose.connect(uri, { dbName });
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
});

beforeEach(async () => {
  const { resetProviders } = await import('../src/providers/registry.js');
  resetProviders();
  const cols = await mongoose.connection.db!.collections();
  await Promise.all(cols.map((c) => c.deleteMany({})));
  const { seedDefaults } = await import('../src/scripts/seedDefaults.js');
  await seedDefaults();
});

afterAll(async () => {
  await mongoose.connection.db?.dropDatabase();
  await mongoose.disconnect();
});
