import crypto from 'node:crypto';
import { env } from '../config/env.js';

const key = (): Buffer => {
  const k = Buffer.from(env.FIELD_ENCRYPTION_KEY, 'base64');
  if (k.length !== 32) return crypto.createHash('sha256').update(env.FIELD_ENCRYPTION_KEY).digest();
  return k;
};

/** AES-256-GCM field-level encryption. Output: v1:<iv>:<tag>:<ciphertext> (base64). */
export function encryptField(plain: string): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv);
  const ct = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64'), cipher.getAuthTag().toString('base64'), ct.toString('base64')].join(':');
}

export function decryptField(enc: string): string {
  const [v, iv, tag, ct] = enc.split(':');
  if (v !== 'v1') throw new Error('Unknown encryption version');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key(), Buffer.from(iv, 'base64'));
  decipher.setAuthTag(Buffer.from(tag, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(ct, 'base64')), decipher.final()]).toString('utf8');
}

export const sha256 = (s: string): string => crypto.createHash('sha256').update(s).digest('hex');

export const hmacSha256Hex = (secret: string, payload: string | Buffer): string =>
  crypto.createHmac('sha256', secret).update(payload).digest('hex');

export function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}

export const randomToken = (bytes = 32): string => crypto.randomBytes(bytes).toString('base64url');

export const randomDigits = (n: number): string => Array.from({ length: n }, () => crypto.randomInt(0, 10)).join('');
