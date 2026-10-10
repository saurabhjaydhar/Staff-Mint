import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { AppError } from './errors.js';

export interface AccessClaims {
  sub: string;
  role: string;
  cid: string | null;
  eid: string | null;
  /** Membership the session is open in (absent on tokens issued before memberships). */
  mid?: string | null;
  /** Device the session belongs to (lets /me say which staff accounts are locked to another phone). */
  did?: string | null;
}

export function signAccessToken(claims: AccessClaims): string {
  return jwt.sign(claims, env.JWT_ACCESS_SECRET, { expiresIn: env.JWT_ACCESS_TTL as jwt.SignOptions['expiresIn'], issuer: 'staffmint', audience: 'staffmint-api' });
}

export function verifyAccessToken(token: string): AccessClaims {
  try {
    return jwt.verify(token, env.JWT_ACCESS_SECRET, { issuer: 'staffmint', audience: 'staffmint-api' }) as AccessClaims;
  } catch (e: any) {
    if (e?.name === 'TokenExpiredError') throw new AppError('TOKEN_EXPIRED', 'Access token expired');
    throw new AppError('UNAUTHORIZED', 'Invalid access token');
  }
}
