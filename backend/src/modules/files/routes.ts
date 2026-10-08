import { Router } from 'express';
import path from 'node:path';
import { env } from '../../config/env.js';
import { LocalStorageProvider } from '../../providers/storage/local.js';
import { safeEqual } from '../../lib/crypto.js';
import { provider } from '../../providers/registry.js';

/** Serves local-storage files behind short-lived HMAC signatures (dev / single-VPS mode). */
export const filesRouter = Router();

filesRouter.get('/*key', async (req, res) => {
  const key = ([] as string[]).concat((req.params as any).key).join('/');
  const exp = Number(req.query.exp);
  const sig = String(req.query.sig ?? '');
  if (!exp || exp < Date.now() / 1000 || !safeEqual(sig, LocalStorageProvider.sign(env.FILE_URL_SECRET, key, exp))) {
    return res.status(403).json({ error: { code: 'FORBIDDEN', message: 'Link expired or invalid' } });
  }
  try {
    const data = await (await provider('storage')).get(key);
    const ext = path.extname(key).toLowerCase();
    res.setHeader('Content-Type', { '.pdf': 'application/pdf', '.jpg': 'image/jpeg', '.png': 'image/png', '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.csv': 'text/csv' }[ext] ?? 'application/octet-stream');
    res.setHeader('Cache-Control', 'private, max-age=300');
    if (req.query.fn) res.setHeader('Content-Disposition', `attachment; filename="${String(req.query.fn).replace(/"/g, '')}"`);
    res.send(data);
  } catch {
    res.status(404).json({ error: { code: 'NOT_FOUND', message: 'File not found' } });
  }
});
