import { Router } from 'express';
import { z } from 'zod';
import { body, param } from '../../lib/http.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { Employee } from '../../models/index.js';
import { notFound } from '../../lib/errors.js';
import { assertEmployeeInScope } from '../employees/service.js';
import * as svc from './service.js';

/** Mounted at `/`; every route authenticates itself so public routes are never shadowed. */
export const faceRouter = Router();

// Staff: own face photo. `consent: true` is required on every enrolment.
faceRouter.get('/me/face', authenticate, requireRole('employee', 'manager'), async (req, res) => {
  const ctx = ctxOf(req);
  const emp = await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId }).lean();
  if (!emp) throw notFound('Employee');
  res.json({ data: await svc.faceView(emp) });
});

faceRouter.post('/me/face', authenticate, requireRole('employee', 'manager'), async (req, res) => {
  const b = body(req, z.object({ consent: z.literal(true), photoBase64: z.string().min(100).max(3_000_000) }));
  res.status(201).json({ data: await svc.faceView(await svc.enroll(ctxOf(req), b.photoBase64)) });
});

faceRouter.delete('/me/face', authenticate, requireRole('employee', 'manager'), async (req, res) => {
  res.json({ data: await svc.faceView(await svc.withdraw(ctxOf(req))) });
});

// Owner / manager: review a staff member's face photo.
faceRouter.get('/employees/:id/face', authenticate, requireRole('owner', 'manager'), async (req, res) => {
  res.json({ data: await svc.faceView(await assertEmployeeInScope(ctxOf(req), param(req, 'id'))) });
});

faceRouter.post('/employees/:id/face/approve', authenticate, requireRole('owner', 'manager'), async (req, res) => {
  res.json({ data: await svc.faceView(await svc.approve(ctxOf(req), param(req, 'id'))) });
});

faceRouter.delete('/employees/:id/face', authenticate, requireRole('owner', 'manager'), async (req, res) => {
  res.json({ data: await svc.faceView(await svc.reset(ctxOf(req), param(req, 'id'))) });
});
