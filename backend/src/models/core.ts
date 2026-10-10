import { Schema, model, type InferSchemaType, type HydratedDocument } from 'mongoose';

const settingsSchema = new Schema(
  {
    graceMinutes: { type: Number, default: 15 },
    halfDayHours: { type: Number, default: 4 },
    monthDivisor: { type: String, enum: ['days_in_month', '30', '26'], default: 'days_in_month' },
    missingCheckoutPolicy: { type: String, enum: ['half_day', 'present', 'flag'], default: 'half_day' },
    weekOffsPaid: { type: Boolean, default: true },
    holidaysPaid: { type: Boolean, default: true },
    sickLeavePaid: { type: Boolean, default: true },
    dailyPaysOffDays: { type: Boolean, default: false },
    outsideGeofencePolicy: { type: String, enum: ['block', 'request_approval'], default: 'block' },
    /** Ask the phone's own screen lock (fingerprint, face, PIN or pattern) at check-in. Nothing biometric reaches the server. */
    phoneLockPolicy: { type: String, enum: ['off', 'recommended', 'required'], default: 'recommended' },
    /** Compare check-in selfies with each person's approved face photo. Off until the owner turns it on. */
    faceMatchPolicy: { type: String, enum: ['off', 'review'], default: 'off' },
    language: { type: String, enum: ['en', 'hi'], default: 'hi' },
    digestTime: { type: String, default: '09:30' },
    roundToRupee: { type: Boolean, default: true },
    selfieRequired: { type: Boolean, default: true },
    maxDeviceTimeDriftMin: { type: Number, default: 10 },
    selfieRetentionDays: { type: Number, default: 90 },
    locationRetentionMonths: { type: Number, default: 12 },
    whatsappAlerts: { type: Boolean, default: false },
    minGpsAccuracyM: { type: Number, default: 150 },
  },
  { _id: false },
);

const companySchema = new Schema(
  {
    name: { type: String, required: true, trim: true },
    businessType: { type: String, default: 'shop' },
    ownerUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    country: { type: String, default: 'IN' },
    currency: { type: String, default: 'INR' },
    timezone: { type: String, default: 'Asia/Kolkata' },
    location: { lat: Number, lng: Number, address: String },
    settings: { type: settingsSchema, default: () => ({}) },
    planCode: { type: String, default: 'free' },
    messagingProvider: { type: String, default: null }, // per-company provider override
    paymentProvider: { type: String, default: null },
    jobState: {
      lastAutoAbsentDate: String,
      lastDigestDate: String,
      lastDraftMonth: String,
    },
    cancelledAt: { type: Date, default: null },
    exportAvailableUntil: { type: Date, default: null },
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true },
);

export type CompanySettings = InferSchemaType<typeof settingsSchema>;
export type CompanyDoc = HydratedDocument<InferSchemaType<typeof companySchema>>;
export const Company = model('Company', companySchema);

const userSchema = new Schema(
  {
    phone: { type: String, required: true, unique: true },
    name: { type: String, default: '' },
    email: { type: String, default: null, lowercase: true, trim: true },
    /** Profile photo in private storage. */
    photoKey: { type: String, default: null },
    role: { type: String, enum: ['owner', 'manager', 'employee', 'ca'], required: true },
    companyId: { type: Schema.Types.ObjectId, ref: 'Company', default: null, index: true },
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', default: null },
    branchIds: [{ type: Schema.Types.ObjectId, ref: 'Branch' }], // manager scope
    language: { type: String, enum: ['en', 'hi'], default: 'hi' },
    deviceIds: { type: [String], default: [] },
    pushTokens: { type: [{ token: String, platform: String, updatedAt: Date }], default: [] },
    lastLoginAt: Date,
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true },
);
export type UserDoc = HydratedDocument<InferSchemaType<typeof userSchema>>;
export const User = model('User', userSchema);

/**
 * One person's access to one business. A user (one phone) can own one shop,
 * work at another and be the accountant of a third; each session is opened
 * in exactly one membership.
 */
const membershipSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    companyId: { type: Schema.Types.ObjectId, ref: 'Company', required: true },
    role: { type: String, enum: ['owner', 'manager', 'employee', 'ca'], required: true },
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', default: null },
    branchIds: [{ type: Schema.Types.ObjectId, ref: 'Branch' }], // manager scope
    /** Staff phone binding, per business. */
    deviceIds: { type: [String], default: [] },
    status: { type: String, enum: ['active', 'inactive'], default: 'active' },
    lastUsedAt: { type: Date, default: null },
  },
  { timestamps: true },
);
membershipSchema.index({ userId: 1, companyId: 1 }, { unique: true });
membershipSchema.index({ companyId: 1, role: 1, status: 1 });
membershipSchema.index({ companyId: 1, employeeId: 1 });
export type MembershipDoc = HydratedDocument<InferSchemaType<typeof membershipSchema>>;
export const Membership = model('Membership', membershipSchema);

const refreshTokenSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    /** The business this device session is open in; null before any business exists. */
    membershipId: { type: Schema.Types.ObjectId, ref: 'Membership', default: null },
    tokenHash: { type: String, required: true, unique: true },
    family: { type: String, required: true, index: true },
    deviceId: String,
    expiresAt: { type: Date, required: true },
    revokedAt: { type: Date, default: null },
    replacedBy: { type: String, default: null },
  },
  { timestamps: true },
);
refreshTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
export const RefreshToken = model('RefreshToken', refreshTokenSchema);

const otpRequestSchema = new Schema(
  {
    phone: { type: String, required: true, index: true },
    codeHash: { type: String, required: true },
    channel: { type: String, default: 'sms' },
    provider: String,
    providerRef: String,
    attempts: { type: Number, default: 0 },
    consumedAt: { type: Date, default: null },
    expiresAt: { type: Date, required: true },
    ip: String,
  },
  { timestamps: true },
);
otpRequestSchema.index({ createdAt: 1 }, { expireAfterSeconds: 86400 });
export const OtpRequest = model('OtpRequest', otpRequestSchema);
