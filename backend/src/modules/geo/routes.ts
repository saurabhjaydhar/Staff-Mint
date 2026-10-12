import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { isTest } from '../../config/env.js';
import { query } from '../../lib/http.js';
import { authenticate } from '../../middleware/auth.js';
import { provider } from '../../providers/registry.js';

/** Place search and pin → address for the shop location picker. The Maps key stays on the server. */
export const geoRouter = Router();

const geoLimiter = rateLimit({
  windowMs: 60_000,
  limit: isTest ? 100000 : 30,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: { error: { code: 'RATE_LIMITED', message: 'Too many requests' } },
});

const lang = z.enum(['en', 'hi']).optional();

geoRouter.get('/geo/search', authenticate, geoLimiter, async (req, res) => {
  const q = query(
    req,
    z.object({
      q: z.string().trim().min(2).max(100),
      lat: z.coerce.number().min(-90).max(90).optional(),
      lng: z.coerce.number().min(-180).max(180).optional(),
      lang,
    }),
  );
  const near = q.lat != null && q.lng != null ? { lat: q.lat, lng: q.lng } : undefined;
  res.json({ data: await (await provider('geo')).search(q.q, { near, language: q.lang }) });
});

geoRouter.get('/geo/reverse', authenticate, geoLimiter, async (req, res) => {
  const q = query(req, z.object({ lat: z.coerce.number().min(-90).max(90), lng: z.coerce.number().min(-180).max(180), lang }));
  res.json({ data: await (await provider('geo')).reverseGeocode(q.lat, q.lng, q.lang) });
});
