import { Types } from 'mongoose';

export type Role = 'owner' | 'manager' | 'employee' | 'ca';
export type Channel = 'app' | 'web' | 'assistant' | 'whatsapp' | 'system' | 'import';

/** Request-independent execution context passed into services (REST, assistant and WhatsApp share services). */
export interface Ctx {
  userId: Types.ObjectId | null;
  companyId: Types.ObjectId;
  role: Role | 'system';
  employeeId: Types.ObjectId | null;
  branchIds: Types.ObjectId[];
  actorName: string;
  channel: Channel;
  language: 'en' | 'hi';
}

export const systemCtx = (companyId: Types.ObjectId | string, language: 'en' | 'hi' = 'hi'): Ctx => ({
  userId: null,
  companyId: new Types.ObjectId(String(companyId)),
  role: 'system',
  employeeId: null,
  branchIds: [],
  actorName: 'StaffMint',
  channel: 'system',
  language,
});

export const isAdminRole = (ctx: Ctx) => ctx.role === 'owner' || ctx.role === 'system';
export const isManagerial = (ctx: Ctx) => ctx.role === 'owner' || ctx.role === 'manager' || ctx.role === 'system';
export const oid = (id: string | Types.ObjectId) => new Types.ObjectId(String(id));
