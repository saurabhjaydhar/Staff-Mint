import { Router } from 'express';
import { z } from 'zod';
import { param as _p, query } from '../../lib/http.js';
import { zMonth } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireFeature, requireRole } from '../../middleware/auth.js';
import { provider } from '../../providers/registry.js';
import { env } from '../../config/env.js';
import { renderReport, type ReportKind } from './service.js';

export const reportsRouter = Router();
reportsRouter.use(authenticate);

reportsRouter.get('/:kind', requireRole('owner', 'manager', 'ca'), requireFeature('reports'), async (req, res) => {
  const kind = z.enum(['attendance', 'salary', 'advances', 'late']).parse(req.params.kind) as ReportKind;
  const q = query(req, z.object({ month: zMonth, format: z.enum(['pdf', 'xlsx']).default('pdf'), delivery: z.enum(['file', 'url']).default('file') }));
  const ctx = ctxOf(req);
  const file = await renderReport(ctx, kind, q.month, q.format);
  if (q.delivery === 'url') {
    const key = `reports/${ctx.companyId}/${Date.now()}-${file.filename}`;
    const storage = await provider('storage');
    await storage.put(key, file.data, file.contentType);
    return res.json({ data: { url: await storage.signedUrl(key, env.SIGNED_URL_TTL_SEC, { filename: file.filename }), filename: file.filename } });
  }
  res.setHeader('Content-Type', file.contentType);
  res.setHeader('Content-Disposition', `attachment; filename="${file.filename}"`);
  res.send(file.data);
});
void _p;
