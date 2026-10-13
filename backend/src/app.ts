import express, { Router } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { pinoHttp } from 'pino-http';
import mongoose from 'mongoose';
import { env, isTest } from './config/env.js';
import { logger } from './lib/logger.js';
import { errorHandler, notFoundHandler } from './middleware/error.js';
import { authRouter } from './modules/auth/routes.js';
import { meRouter } from './modules/me/routes.js';
import { faceRouter } from './modules/face/routes.js';
import { profileRouter } from './modules/profile/routes.js';
import { companyRouter } from './modules/company/routes.js';
import { employeesRouter } from './modules/employees/routes.js';
import { importsRouter } from './modules/imports/routes.js';
import { rosterRouter } from './modules/roster/routes.js';
import { attendanceRouter } from './modules/attendance/routes.js';
import { leaveRouter } from './modules/leave/routes.js';
import { advancesRouter } from './modules/advances/routes.js';
import { payrollRouter } from './modules/payroll/routes.js';
import { reportsRouter } from './modules/reports/routes.js';
import { assistantRouter } from './modules/assistant/routes.js';
import { auditRouter } from './modules/audit/routes.js';
import { exportRouter } from './modules/export/routes.js';
import { billingRouter, mockCheckoutRouter, paymentsWebhookRouter } from './modules/billing/routes.js';
import { messagingWebhookRouter } from './modules/messaging/routes.js';
import { dashboardRouter } from './modules/dashboard/routes.js';
import { adminAuthRouter, adminRouter } from './modules/admin/routes.js';
import { filesRouter } from './modules/files/routes.js';
import { accountsRouter } from './modules/accounts/routes.js';
import { geoRouter } from './modules/geo/routes.js';
import { enabledFlags } from './modules/config/service.js';
import { providerName } from './providers/registry.js';

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  const origins = env.CORS_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean);
  app.use(cors({ origin: (origin, cb) => cb(null, !origin || origins.includes('*') || origins.includes(origin)), credentials: false, exposedHeaders: ['Content-Disposition'] }));
  app.use(compression());
  // Keep the raw body for webhook signature verification.
  app.use(express.json({ limit: '10mb', verify: (req: any, _res, buf) => (req.rawBody = Buffer.from(buf)) }));
  app.use(express.urlencoded({ extended: false, limit: '1mb' }));
  if (!isTest) app.use(pinoHttp({ logger, autoLogging: { ignore: (req) => req.url === '/health' } }));

  app.get('/health', (_req, res) => {
    const db = mongoose.connection.readyState === 1;
    res.status(db ? 200 : 503).json({ ok: db, db, version: process.env.npm_package_version ?? '0.1.0', time: new Date().toISOString() });
  });
  app.use('/files', filesRouter);
  app.use('/mock-checkout', mockCheckoutRouter);

  const api = Router();
  api.use(rateLimit({ windowMs: 60_000, limit: isTest ? 100000 : 300, standardHeaders: 'draft-8', legacyHeaders: false, message: { error: { code: 'RATE_LIMITED', message: 'Too many requests' } } }));
  // Public / signature-verified routes first: routers below mounted at '/' apply authentication to everything after them.
  api.use('/auth', authRouter);
  api.use('/billing', billingRouter);
  api.use('/webhooks/payments', paymentsWebhookRouter);
  api.use('/webhooks/messaging', messagingWebhookRouter);
  api.use('/admin-auth', adminAuthRouter);
  api.use('/admin', adminRouter);
  api.get('/config/public', async (_req, res) => {
    res.json({ data: { minAppVersion: env.MIN_APP_VERSION, features: await enabledFlags(), supportWhatsApp: env.SUPPORT_WHATSAPP, otpProvider: providerName('otp'), environment: env.NODE_ENV } });
  });
  api.use('/', accountsRouter);
  api.use('/', faceRouter);
  api.use('/', profileRouter);
  api.use('/me', meRouter);
  api.use('/', companyRouter);
  api.use('/', geoRouter);
  api.use('/dashboard', dashboardRouter);
  api.use('/employees', employeesRouter);
  api.use('/imports', importsRouter);
  api.use('/attendance', attendanceRouter);
  api.use('/roster', rosterRouter);
  api.use('/', leaveRouter);
  api.use('/', advancesRouter);
  api.use('/', payrollRouter);
  api.use('/reports', reportsRouter);
  api.use('/assistant', assistantRouter);
  api.use('/audit-logs', auditRouter);
  api.use('/export', exportRouter);
  app.use('/api/v1', api);

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
