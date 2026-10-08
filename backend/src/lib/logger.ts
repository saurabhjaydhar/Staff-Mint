import pino from 'pino';
import { env, isTest } from '../config/env.js';

export const logger = pino({
  level: isTest ? 'silent' : env.LOG_LEVEL,
  redact: { paths: ['req.headers.authorization', '*.code', '*.otp', '*.refreshToken', '*.accessToken', '*.selfieBase64', '*.audioBase64'], censor: '[redacted]' },
  transport: env.NODE_ENV === 'development' ? { target: 'pino-pretty', options: { colorize: true, singleLine: true } } : undefined,
});
