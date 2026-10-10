import { Router } from 'express';
import { z } from 'zod';
import { body, param, query } from '../../lib/http.js';
import { zDate, zPaise } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { employeeView } from '../views.js';
import * as svc from './service.js';

export const employeesRouter = Router();
employeesRouter.use(authenticate);

const employeeSchema = z.object({
  name: z.string().trim().min(1).max(80),
  phone: z.string().min(6).max(20),
  wageType: z.enum(['monthly', 'daily']).optional(),
  ratePaise: zPaise.optional(),
  branchId: z.string().optional(),
  shiftId: z.string().optional(),
  designation: z.string().max(60).optional(),
  joiningDate: zDate.optional(),
});

employeesRouter.get('/', requireRole('owner', 'manager', 'ca'), async (req, res) => {
  const q = query(req, z.object({ search: z.string().max(80).optional(), status: z.enum(['active', 'inactive', 'all']).optional(), branchId: z.string().optional() }));
  res.json({ data: await svc.listEmployees(ctxOf(req), q) });
});

employeesRouter.post('/', requireRole('owner', 'manager'), async (req, res) => {
  const { invite, ...input } = body(req, employeeSchema.extend({ invite: z.boolean().default(true) }));
  res.status(201).json({ data: employeeView(await svc.createEmployee(ctxOf(req), input, { invite })) });
});

employeesRouter.post('/bulk', requireRole('owner', 'manager'), async (req, res) => {
  const b = body(req, z.object({ employees: z.array(employeeSchema).min(1).max(200) }));
  res.json({ data: await svc.bulkCreate(ctxOf(req), b.employees) });
});

employeesRouter.get('/:id', requireRole('owner', 'manager', 'ca'), async (req, res) => {
  res.json({ data: await svc.getEmployee(ctxOf(req), param(req, 'id')) });
});

employeesRouter.patch('/:id', requireRole('owner', 'manager'), async (req, res) => {
  const b = body(req, employeeSchema.partial().extend({ effectiveFrom: zDate.optional(), language: z.enum(['en', 'hi']).optional() }));
  res.json({ data: employeeView(await svc.updateEmployee(ctxOf(req), param(req, 'id'), b)) });
});

employeesRouter.post('/:id/deactivate', requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ reason: z.string().max(200).optional() }));
  res.json({ data: employeeView(await svc.deactivateEmployee(ctxOf(req), param(req, 'id'), b.reason)) });
});

employeesRouter.post('/:id/reactivate', requireRole('owner'), async (req, res) => {
  res.json({ data: employeeView(await svc.reactivateEmployee(ctxOf(req), param(req, 'id'))) });
});

employeesRouter.post('/:id/reset-device', requireRole('owner', 'manager'), async (req, res) => {
  res.json({ data: employeeView(await svc.resetDevice(ctxOf(req), param(req, 'id'))) });
});

employeesRouter.post('/:id/role', requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ role: z.enum(['employee', 'manager']) }));
  res.json({ data: employeeView(await svc.setAppRole(ctxOf(req), param(req, 'id'), b.role)) });
});
