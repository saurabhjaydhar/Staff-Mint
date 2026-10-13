import { Router } from 'express';
import { AppError } from '../../lib/errors.js';
import { readLinked } from './documents.js';

/** Opens a document file from a short-lived signed link (made by POST /verification/documents/:id/open). */
export const docFilesRouter = Router();

docFilesRouter.get('/:token', async (req, res) => {
  try {
    const { data, mime } = await readLinked(String(req.params.token));
    res.setHeader('Content-Type', mime);
    res.setHeader('Cache-Control', 'private, no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.send(data);
  } catch (err) {
    const forbidden = err instanceof AppError;
    res.status(forbidden ? 403 : 404).json({ error: { code: forbidden ? 'FORBIDDEN' : 'NOT_FOUND', message: forbidden ? 'Link expired or invalid' : 'File not found' } });
  }
});
