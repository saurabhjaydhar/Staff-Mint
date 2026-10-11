import { Schema, model } from 'mongoose';

/** People who run StaffMint (not tenants). Sign in to the admin app with email + password + a code sent by email. */
const adminUserSchema = new Schema(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    name: { type: String, default: '' },
    /** scrypt: "s1:<salt>:<hash>" (base64). */
    passwordHash: { type: String, required: true },
    /** admin: everything. viewer: read only (support staff). */
    role: { type: String, enum: ['admin', 'viewer'], default: 'viewer' },
    active: { type: Boolean, default: true },
    /** Bumped on logout / password change / disable: every older session stops working. */
    tokenVersion: { type: Number, default: 0 },
    failedLogins: { type: Number, default: 0 },
    lockedUntil: { type: Date, default: null },
    loginCodeHash: { type: String, default: null },
    loginCodeExpiresAt: { type: Date, default: null },
    loginCodeAttempts: { type: Number, default: 0 },
    lastLoginAt: { type: Date, default: null },
  },
  { timestamps: true },
);
export const AdminUser = model('AdminUser', adminUserSchema);

/** Every change made from the admin app or admin API: who, what, on which business. */
const adminActionSchema = new Schema(
  {
    adminId: { type: Schema.Types.ObjectId, ref: 'AdminUser', default: null },
    /** Email of the admin, or "api-key" for scripts. */
    actor: { type: String, required: true },
    action: { type: String, required: true },
    companyId: { type: Schema.Types.ObjectId, ref: 'Company', default: null, index: true },
    target: { type: String, default: null },
    details: { type: Schema.Types.Mixed, default: {} },
  },
  { timestamps: { createdAt: true, updatedAt: false } },
);
adminActionSchema.index({ createdAt: -1 });
export const AdminAction = model('AdminAction', adminActionSchema);
