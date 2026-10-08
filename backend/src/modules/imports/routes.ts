import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { body, param } from '../../lib/http.js';
import { zMonth } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import * as svc from './service.js';

export const importsRouter = Router();
export const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });
importsRouter.use(authenticate);

importsRouter.post('/', requireRole('owner', 'manager'), upload.single('file'), async (req, res) => {
  const b = body(
    req,
    z.object({
      text: z.string().max(200_000).optional(),
      kind: z.enum(['staff', 'attendance']).default('staff'),
      month: zMonth.optional(),
      source: z.enum(['auto', 'salarybox', 'pagarbook', 'generic']).default('auto'),
    }),
  );
  const ctx = ctxOf(req);
  const s = await svc.createImport(ctx, { ...b, file: req.file ? { buffer: req.file.buffer, originalname: req.file.originalname, mimetype: req.file.mimetype } : undefined });
  res.status(201).json({ data: await svc.sessionView(ctx, s) });
});

importsRouter.get('/:id', requireRole('owner', 'manager'), async (req, res) => {
  const ctx = ctxOf(req);
  res.json({ data: await svc.sessionView(ctx, await svc.getImport(ctx, param(req, 'id'))) });
});

importsRouter.patch('/:id', requireRole('owner', 'manager'), async (req, res) => {
  const b = body(
    req,
    z.object({
      mapping: z.record(z.string(), z.string().nullable()).optional(),
      fixes: z.array(z.object({ row: z.number().int().min(0), field: z.string(), value: z.unknown() })).max(5000).optional(),
      skipRows: z.array(z.number().int().min(0)).optional(),
    }),
  );
  const ctx = ctxOf(req);
  res.json({ data: await svc.sessionView(ctx, await svc.patchImport(ctx, param(req, 'id'), b)) });
});

importsRouter.post('/:id/commit', requireRole('owner', 'manager'), async (req, res) => {
  const b = body(req, z.object({ overwriteExisting: z.boolean().optional() }));
  res.json({ data: await svc.commitImport(ctxOf(req), param(req, 'id'), b) });
});

importsRouter.post('/:id/rollback', requireRole('owner'), async (req, res) => {
  res.json({ data: await svc.rollbackImport(ctxOf(req), param(req, 'id')) });
});
