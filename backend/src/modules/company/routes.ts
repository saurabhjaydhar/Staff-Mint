import { Router } from 'express';
import { z } from 'zod';
import { body, param, query } from '../../lib/http.js';
import { zDate, zLatLng, zTime, zWeekdays } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { AppError } from '../../lib/errors.js';
import { describeRules } from '../attendance/rules.js';
import { Shift } from '../../models/index.js';
import * as svc from './service.js';

export const companyRouter = Router();

companyRouter.post('/company', authenticate, async (req, res) => {
  if (req.ctx) throw new AppError('CONFLICT', 'Company already set up');
  const b = body(
    req,
    z.object({
      name: z.string().trim().min(2).max(120),
      businessType: z.string().trim().min(2).max(40),
      location: zLatLng,
      openingTime: zTime,
      closingTime: zTime.optional(),
      weeklyOff: zWeekdays.default([0]),
      country: z.string().length(2).optional(),
      timezone: z.string().max(60).optional(),
      currency: z.string().length(3).optional(),
      ownerName: z.string().max(80).optional(),
    }),
  );
  const { Types } = await import('mongoose');
  res.status(201).json({ data: await svc.setupCompany(new Types.ObjectId(req.auth!.userId), b) });
});

companyRouter.get('/company', authenticate, requireRole('owner', 'manager', 'ca', 'employee'), async (req, res) => {
  res.json({ data: await svc.companyView(await svc.getCompany(ctxOf(req))) });
});

companyRouter.patch('/company', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ name: z.string().trim().min(2).max(120).optional(), businessType: z.string().max(40).optional(), location: zLatLng.optional() }));
  res.json({ data: await svc.companyView(await svc.updateCompany(ctxOf(req), b)) });
});

const settingsSchema = z
  .object({
    graceMinutes: z.number().int().min(0).max(240),
    halfDayHours: z.number().min(0).max(12),
    monthDivisor: z.enum(['days_in_month', '30', '26']),
    missingCheckoutPolicy: z.enum(['half_day', 'present', 'flag']),
    weekOffsPaid: z.boolean(),
    holidaysPaid: z.boolean(),
    sickLeavePaid: z.boolean(),
    dailyPaysOffDays: z.boolean(),
    outsideGeofencePolicy: z.enum(['block', 'request_approval']),
    phoneLockPolicy: z.enum(['off', 'recommended', 'required']),
    language: z.enum(['en', 'hi']),
    digestTime: zTime,
    roundToRupee: z.boolean(),
    selfieRequired: z.boolean(),
    maxDeviceTimeDriftMin: z.number().int().min(1).max(720),
    selfieRetentionDays: z.number().int().min(7).max(365),
    locationRetentionMonths: z.number().int().min(1).max(36),
    whatsappAlerts: z.boolean(),
    minGpsAccuracyM: z.number().int().min(10).max(2000),
  })
  .partial()
  .strict();

companyRouter.patch('/company/settings', authenticate, requireRole('owner'), async (req, res) => {
  res.json({ data: await svc.companyView(await svc.updateSettings(ctxOf(req), body(req, settingsSchema))) });
});

companyRouter.get('/company/rules', authenticate, requireRole('owner', 'manager', 'employee', 'ca'), async (req, res) => {
  const ctx = ctxOf(req);
  const c = await svc.getCompany(ctx);
  const shift = await Shift.findOne({ companyId: ctx.companyId, isDefault: true }).lean();
  res.json({ data: { rules: describeRules(c.settings as any, ctx.language, shift ?? undefined) } });
});

companyRouter.post('/company/accountants', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ phone: z.string(), name: z.string().min(1).max(80) }));
  const { parsePhone } = await import('../auth/service.js');
  res.status(201).json({ data: await svc.addAccountant(ctxOf(req), parsePhone(b.phone), b.name) });
});

// Branches
companyRouter.get('/branches', authenticate, requireRole('owner', 'manager', 'employee'), async (req, res) => res.json({ data: await svc.listBranches(ctxOf(req)) }));
companyRouter.post('/branches', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ name: z.string().min(1).max(80), location: zLatLng, radiusM: z.number().int().min(20).max(5000).optional(), shiftId: z.string().optional() }));
  res.status(201).json({ data: await svc.createBranch(ctxOf(req), b) });
});
companyRouter.patch('/branches/:id', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ name: z.string().min(1).max(80).optional(), location: zLatLng.optional(), radiusM: z.number().int().min(20).max(5000).optional(), shiftId: z.string().optional() }));
  res.json({ data: await svc.updateBranch(ctxOf(req), param(req, 'id'), b) });
});

// Shifts
const shiftSchema = z.object({ name: z.string().min(1).max(60), start: zTime, end: zTime, graceMinutes: z.number().int().min(0).max(240).nullable().optional(), weeklyOff: zWeekdays });
companyRouter.get('/shifts', authenticate, requireRole('owner', 'manager', 'employee'), async (req, res) => res.json({ data: await svc.listShifts(ctxOf(req)) }));
companyRouter.post('/shifts', authenticate, requireRole('owner'), async (req, res) => res.status(201).json({ data: await svc.createShift(ctxOf(req), body(req, shiftSchema)) }));
companyRouter.patch('/shifts/:id', authenticate, requireRole('owner'), async (req, res) => res.json({ data: await svc.updateShift(ctxOf(req), param(req, 'id'), body(req, shiftSchema.partial())) }));

// Holidays
companyRouter.get('/holidays', authenticate, requireRole('owner', 'manager', 'employee', 'ca'), async (req, res) => {
  const q = query(req, z.object({ year: z.coerce.number().int().min(2000).max(2100).optional() }));
  res.json({ data: await svc.listHolidays(ctxOf(req), q.year) });
});
companyRouter.post('/holidays', authenticate, requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ date: zDate, name: z.string().min(1).max(80) }));
  res.status(201).json({ data: await svc.addHoliday(ctxOf(req), b.date, b.name) });
});
companyRouter.delete('/holidays/:id', authenticate, requireRole('owner'), async (req, res) => {
  await svc.deleteHoliday(ctxOf(req), param(req, 'id'));
  res.json({ data: { ok: true } });
});
