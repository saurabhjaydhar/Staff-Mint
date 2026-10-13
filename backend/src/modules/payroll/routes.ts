import { Router } from 'express';
import { z } from 'zod';
import { body, param, query } from '../../lib/http.js';
import { zDate, zMonth } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireFeature, requireRole } from '../../middleware/auth.js';
import { AppError } from '../../lib/errors.js';
import { upload } from '../imports/routes.js';
import { Company, Payslip } from '../../models/index.js';
import * as svc from './service.js';
import { compareWithReport } from './compare.js';
import * as payslips from '../payslips/service.js';
import { payslipView } from '../payslips/views.js';

export const payrollRouter = Router();
payrollRouter.use(authenticate);

payrollRouter.get('/payroll/runs', requireRole('owner', 'ca'), async (req, res) => {
  const q = query(req, z.object({ month: zMonth.optional() }));
  res.json({ data: await svc.listRuns(ctxOf(req), q.month) });
});

payrollRouter.post('/payroll/runs', requireRole('owner'), requireFeature('payroll'), async (req, res) => {
  const b = body(req, z.object({ month: zMonth }));
  const ctx = ctxOf(req);
  res.json({ data: await svc.runView(await svc.createOrRecomputeDraft(ctx, b.month), true, ctx.language) });
});

payrollRouter.get('/payroll/runs/:id', requireRole('owner', 'ca'), async (req, res) => {
  const ctx = ctxOf(req);
  res.json({ data: await svc.runView(await svc.getFreshRun(ctx, param(req, 'id')), true, ctx.language) });
});

for (const [path, fn] of [
  ['recompute', svc.recompute],
  ['approve', svc.approve],
  ['revise', svc.revise],
] as const) {
  payrollRouter.post(`/payroll/runs/:id/${path}`, requireRole('owner'), requireFeature('payroll'), async (req, res) => {
    const ctx = ctxOf(req);
    res.json({ data: await svc.runView(await fn(ctx, param(req, 'id')), true, ctx.language) });
  });
}

payrollRouter.post('/payroll/runs/:id/mark-paid', requireRole('owner'), requireFeature('payroll'), async (req, res) => {
  const ctx = ctxOf(req);
  const b = body(req, z.object({ paidOn: zDate.optional(), method: z.enum(['cash', 'upi', 'bank', 'mixed']).optional() }));
  res.json({ data: await svc.runView(await svc.markPaid(ctx, param(req, 'id'), b), true, ctx.language) });
});

payrollRouter.post('/payroll/runs/:id/compare', requireRole('owner'), upload.single('file'), async (req, res) => {
  if (!req.file) throw new AppError('VALIDATION_ERROR', 'Upload the old app salary report as file');
  const ctx = ctxOf(req);
  const run = await svc.getRun(ctx, param(req, 'id'));
  const slips = await Payslip.find({ companyId: ctx.companyId, runId: run._id }).lean();
  const company = await Company.findById(ctx.companyId).lean();
  try {
    res.json({ data: await compareWithReport(req.file, slips, company!.settings.monthDivisor) });
  } catch (e: any) {
    if (e?.code === 'VALIDATION_ERROR') throw new AppError('VALIDATION_ERROR', e.message);
    throw e;
  }
});

// ---- Payslips ----
payrollRouter.get('/payslips', requireRole('owner', 'manager', 'employee', 'ca'), async (req, res) => {
  const q = query(req, z.object({ month: zMonth.optional(), employeeId: z.string().optional() }));
  const ctx = ctxOf(req);
  const list = await payslips.listPayslips(ctx, q);
  res.json({ data: await Promise.all(list.map((s) => payslipView(s, ctx.language))) });
});

payrollRouter.post('/payslips/send', requireRole('owner'), requireFeature('payslips'), async (req, res) => {
  const b = body(req, z.object({ runId: z.string(), payslipIds: z.array(z.string()).optional() }));
  res.json({ data: await payslips.sendPayslips(ctxOf(req), b.runId, b.payslipIds) });
});

payrollRouter.get('/payslips/:id', requireRole('owner', 'manager', 'employee', 'ca'), async (req, res) => {
  const ctx = ctxOf(req);
  const s = await payslips.getPayslip(ctx, param(req, 'id'));
  if (!s.pdfKey && s.status !== 'draft') await payslips.renderPayslipPdf(ctx.companyId, s._id);
  res.json({ data: await payslipView(await payslips.getPayslip(ctx, param(req, 'id')), ctx.language) });
});

payrollRouter.get('/payslips/:id/explain', requireRole('owner', 'manager', 'employee', 'ca'), async (req, res) => {
  const ctx = ctxOf(req);
  res.json({ data: payslips.explain(await payslips.getPayslip(ctx, param(req, 'id')), ctx.language) });
});
