import { MongoMemoryServer } from 'mongodb-memory-server';
import fs from 'node:fs';
import type { TestProject } from 'vitest/node';

let mongod: MongoMemoryServer | undefined;

export async function setup(project: TestProject) {
  if (process.env.TEST_MONGODB_URI) {
    project.provide('mongoUri', process.env.TEST_MONGODB_URI);
    return;
  }
  // Use a system mongod if present (CI images / offline sandboxes), else let mongodb-memory-server download one.
  const systemBinary = process.env.MONGOMS_SYSTEM_BINARY ?? ['/opt/mongo-bin/mongod', '/usr/bin/mongod'].find((p) => fs.existsSync(p));
  mongod = await MongoMemoryServer.create({ binary: systemBinary ? { systemBinary } : undefined });
  project.provide('mongoUri', mongod.getUri());
}

export async function teardown() {
  await mongod?.stop();
}

declare module 'vitest' {
  export interface ProvidedContext {
    mongoUri: string;
  }
}
