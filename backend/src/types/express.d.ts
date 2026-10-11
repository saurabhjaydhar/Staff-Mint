import type { Ctx } from '../lib/context.js';

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string; role: string; companyId: string | null; employeeId: string | null; membershipId?: string | null; deviceId?: string | null };
      ctx?: Ctx;
      rawBody?: Buffer;
      /** Signed-in admin (admin app) or the API key (scripts). */
      admin?: { id: string | null; email: string; role: 'admin' | 'viewer' };
    }
  }
}
export {};
