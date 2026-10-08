import mongoose from 'mongoose';
import { env } from './config/env.js';
import { logger } from './lib/logger.js';

mongoose.set('strictQuery', true);

export async function connectDb(uri = env.MONGODB_URI): Promise<void> {
  await mongoose.connect(uri, { autoIndex: true, serverSelectionTimeoutMS: 10000 });
  logger.info('MongoDB connected');
}

export async function disconnectDb(): Promise<void> {
  await mongoose.disconnect();
}

export async function syncIndexes(): Promise<void> {
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
}
