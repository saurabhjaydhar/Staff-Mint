import type { NextFunction, Request, Response } from 'express';
import mongoose from 'mongoose';
import * as Sentry from '@sentry/node';
import { AppError } from '../lib/errors.js';
import { logger } from '../lib/logger.js';
import { env } from '../config/env.js';

export function notFoundHandler(req: Request, res: Response) {
  res.status(404).json({ error: { code: 'NOT_FOUND', message: `Route ${req.method} ${req.path} not found` } });
}

export function errorHandler(err: any, req: Request, res: Response, _next: NextFunction) {
  if (err instanceof AppError) {
    return res.status(err.status).json({ error: { code: err.code, message: err.message, details: err.details } });
  }
  if (err?.type === 'entity.parse.failed') return res.status(400).json({ error: { code: 'VALIDATION_ERROR', message: 'Malformed JSON' } });
  if (err?.type === 'entity.too.large' || err?.code === 'LIMIT_FILE_SIZE') return res.status(413).json({ error: { code: 'VALIDATION_ERROR', message: 'Payload too large' } });
  if (err instanceof mongoose.Error.ValidationError) return res.status(400).json({ error: { code: 'VALIDATION_ERROR', message: err.message } });
  if (err instanceof mongoose.Error.CastError) return res.status(400).json({ error: { code: 'VALIDATION_ERROR', message: `Invalid ${err.path}` } });
  if (err?.code === 11000) return res.status(409).json({ error: { code: 'CONFLICT', message: 'Already exists', details: err.keyValue } });
  logger.error({ err, path: req.path }, 'Unhandled error');
  if (env.SENTRY_DSN) Sentry.captureException(err);
  res.status(500).json({ error: { code: 'INTERNAL', message: 'Something went wrong' } });
}
