import type { Request } from 'express';
import { z, type ZodType } from 'zod';
import { AppError } from './errors.js';

export function parse<T extends ZodType>(schema: T, input: unknown): z.infer<T> {
  const r = schema.safeParse(input);
  if (!r.success) {
    const details = r.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message }));
    const first = details[0];
    throw new AppError('VALIDATION_ERROR', first ? `${first.path || 'input'}: ${first.message}` : 'Invalid input', details);
  }
  return r.data;
}

export const body = <T extends ZodType>(req: Request, schema: T) => parse(schema, req.body ?? {});
export const query = <T extends ZodType>(req: Request, schema: T) => parse(schema, req.query ?? {});

export const objectId = z.string().regex(/^[a-f\d]{24}$/i, 'Invalid id');

export const param = (req: Request, name: string): string => {
  const v = req.params[name];
  return parse(objectId, Array.isArray(v) ? v[0] : v);
};
