import { z } from 'zod';
import { DATE_RE, MONTH_RE, TIME_RE } from './dates.js';

export const zDate = z.string().regex(DATE_RE, 'Use YYYY-MM-DD');
export const zMonth = z.string().regex(MONTH_RE, 'Use YYYY-MM');
export const zTime = z.string().regex(TIME_RE, 'Use HH:mm');
export const zLatLng = z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180), address: z.string().max(300).optional() });
export const zPaise = z.number().int().min(0).max(10_000_000_000);
export const zWeekdays = z.array(z.number().int().min(0).max(6)).max(7);
