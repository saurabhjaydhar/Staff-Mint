import { Router } from 'express';
import { z } from 'zod';
import { body, param } from '../../lib/http.js';
import { DATE_RE } from '../../lib/dates.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { TRACKING_EVENTS } from '../../models/index.js';
import * as svc from './service.js';

export const trackingRouter = Router();

const boss = [authenticate, requireRole('owner', 'manager')];
const staff = [authenticate, requireRole('employee', 'manager')];

// Owner/manager: field staff on or off, everyone's latest point, one person's day.
trackingRouter.put('/employees/:id', ...boss, async (req, res) => {
  const b = body(req, z.object({ enabled: z.boolean() }));
  res.json({ data: await svc.setTracking(ctxOf(req), param(req, 'id'), b.enabled) });
});
trackingRouter.get('/live', ...boss, async (req, res) => res.json({ data: await svc.live(ctxOf(req)) }));
trackingRouter.get('/day', authenticate, requireRole('owner', 'manager', 'employee'), async (req, res) => {
  const q = z.object({ employeeId: z.string().optional(), date: z.string().regex(DATE_RE) }).parse(req.query);
  res.json({ data: await svc.day(ctxOf(req), q.employeeId ?? null, q.date) });
});

// Staff phone: should it share, consent, points (batches, also from offline), events.
trackingRouter.get('/me', ...staff, async (req, res) => res.json({ data: await svc.mine(ctxOf(req)) }));
trackingRouter.post('/me/consent', ...staff, async (req, res) => res.json({ data: await svc.giveConsent(ctxOf(req)) }));
trackingRouter.delete('/me/consent', ...staff, async (req, res) => res.json({ data: await svc.withdrawConsent(ctxOf(req)) }));
const point = z.object({
  at: z.string().min(10).max(40),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  accuracyM: z.number().min(0).max(100000).nullish(),
  speed: z.number().min(0).max(1000).nullish(),
  battery: z.number().min(0).max(100).nullish(),
  mock: z.boolean().optional(),
});
trackingRouter.post('/pings', ...staff, async (req, res) => {
  const b = body(req, z.object({ points: z.array(point).max(500) }));
  res.json({ data: await svc.addPings(ctxOf(req), b.points) });
});
trackingRouter.post('/events', ...staff, async (req, res) => {
  const b = body(req, z.object({ events: z.array(z.object({ at: z.string().min(10).max(40), type: z.enum(TRACKING_EVENTS) })).max(50) }));
  res.json({ data: await svc.addEvents(ctxOf(req), b.events) });
});
