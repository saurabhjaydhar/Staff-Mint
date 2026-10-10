import type { Ctx } from '../lib/context.js';

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string; role: string; companyId: string | null; employeeId: string | null; membershipId?: string | null };
      ctx?: Ctx;
      rawBody?: Buffer;
    }
  }
}
export {};
