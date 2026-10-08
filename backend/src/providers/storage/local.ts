import fs from 'node:fs/promises';
import path from 'node:path';
import type { StorageProvider } from '../types.js';
import { hmacSha256Hex } from '../../lib/crypto.js';

/** Local disk storage with HMAC-signed, expiring URLs served by GET /files/*. */
export class LocalStorageProvider implements StorageProvider {
  readonly name = 'local';
  constructor(private cfg: { dir: string; publicBaseUrl: string; secret: string }) {}
  private resolve(key: string) {
    const p = path.resolve(this.cfg.dir, key);
    if (!p.startsWith(path.resolve(this.cfg.dir))) throw new Error('Invalid key');
    return p;
  }
  async put(key: string, data: Buffer, _contentType?: string) {
    const p = this.resolve(key);
    await fs.mkdir(path.dirname(p), { recursive: true });
    await fs.writeFile(p, data);
  }
  async get(key: string) {
    return fs.readFile(this.resolve(key));
  }
  async delete(key: string) {
    await fs.rm(this.resolve(key), { force: true });
  }
  async signedUrl(key: string, ttlSec: number, opts?: { filename?: string }) {
    const exp = Math.floor(Date.now() / 1000) + ttlSec;
    const sig = LocalStorageProvider.sign(this.cfg.secret, key, exp);
    const fn = opts?.filename ? `&fn=${encodeURIComponent(opts.filename)}` : '';
    return `${this.cfg.publicBaseUrl}/files/${key.split('/').map(encodeURIComponent).join('/')}?exp=${exp}&sig=${sig}${fn}`;
  }
  static sign(secret: string, key: string, exp: number) {
    return hmacSha256Hex(secret, `${key}:${exp}`);
  }
}
