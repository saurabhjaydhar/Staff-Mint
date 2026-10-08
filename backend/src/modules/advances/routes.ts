import { Router } from 'express';
import { z } from 'zod';
import { body, param, query } from '../../lib/http.js';
import { zDate, zMonth, zPaise } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireFeature, requireRole } from '../../middleware/auth.js';
import * as svc from './service.js';

export const advancesRouter = Router();
advancesRouter.use(authenticate);

advancesRouter.get('/advances', requireRole('owner', 'manager', 'ca'), async (req, res) => {
  const q = query(req, z.object({ employeeId: z.string().optional(), status: z.enum(['active', 'closed']).optional() }));
  res.json({ data: await svc.listAdvances(ctxOf(req), q) });
});

advancesRouter.post('/advances', requireRole('owner'), requireFeature('advances'), async (req, res) => {
  const b = body(
    req,
    z.object({ employeeId: z.string(), amountPaise: zPaise.min(1), date: zDate, mode: z.enum(['installments', 'full_next']).default('full_next'), installments: z.number().int().min(1).max(36).optional(), note: z.string().max(200).optional() }),
  );
  res.status(201).json({ data: await svc.createAdvance(ctxOf(req), b) });
});

advancesRouter.post('/advances/:id/skip', requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ month: zMonth }));
  res.json({ data: await svc.skipAdvanceMonth(ctxOf(req), param(req, 'id'), b.month) });
});

advancesRouter.get('/adjustments', requireRole('owner', 'manager', 'ca'), async (req, res) => {
  const q = query(req, z.object({ month: zMonth.optional(), employeeId: z.string().optional() }));
  res.json({ data: await svc.listAdjustments(ctxOf(req), q) });
});

advancesRouter.post('/adjustments', requireRole('owner'), requireFeature('payroll'), async (req, res) => {
  const b = body(req, z.object({ employeeId: z.string(), month: zMonth, type: z.enum(['bonus', 'deduction']), amountPaise: zPaise.min(1), note: z.string().max(200).optional() }));
  res.status(201).json({ data: await svc.createAdjustment(ctxOf(req), b) });
});

advancesRouter.delete('/adjustments/:id', requireRole('owner'), async (req, res) => {
  await svc.deleteAdjustment(ctxOf(req), param(req, 'id'));
  res.json({ data: { ok: true } });
});
