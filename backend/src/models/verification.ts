import { Schema, model } from 'mongoose';
import { tenantFields, tenantPlugin } from './tenant.js';

export const VERIFICATION_KINDS = ['aadhaar', 'pan', 'dl', 'voter', 'bank', 'uan', 'face'] as const;
export type VerificationKind = (typeof VERIFICATION_KINDS)[number];

/**
 * The owner asks a staff member to verify their documents. Nothing is checked until the staff member
 * agrees (consent). One open request per person.
 */
const verificationRequestSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    kinds: { type: [String], enum: VERIFICATION_KINDS, required: true },
    status: { type: String, enum: ['asked', 'in_progress', 'done', 'cancelled'], default: 'asked' },
    consent: {
      type: new Schema(
        {
          textVersion: String,
          acceptedAt: Date,
          userId: { type: Schema.Types.ObjectId, ref: 'User' },
          by: { type: String, enum: ['staff', 'owner_on_behalf'] },
          /** Owner did it for them: photo of the slip they signed (encrypted, like documents). */
          slipKey: { type: String, default: null },
          slipMime: { type: String, default: null },
        },
        { _id: false },
      ),
      default: null,
    },
    requestedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    /** Company-time month it counts against ("2026-10"). */
    month: { type: String, required: true },
    doneAt: { type: Date, default: null },
  },
  { timestamps: true },
);
verificationRequestSchema.plugin(tenantPlugin);
verificationRequestSchema.index({ companyId: 1, employeeId: 1, createdAt: -1 });
verificationRequestSchema.index({ companyId: 1, month: 1 });
export const VerificationRequest = model('VerificationRequest', verificationRequestSchema);

/**
 * One check against government records. Never keeps a full Aadhaar or bank number: only the last 4.
 * `details` is encrypted (e.g. date of birth from Aadhaar).
 */
const verificationCheckSchema = new Schema(
  {
    ...tenantFields,
    requestId: { type: Schema.Types.ObjectId, ref: 'VerificationRequest', required: true },
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    kind: { type: String, enum: VERIFICATION_KINDS, required: true },
    status: { type: String, enum: ['waiting', 'otp_sent', 'verified', 'mismatch', 'not_found', 'failed'], default: 'waiting' },
    last4: { type: String, default: null },
    nameOnRecord: { type: String, default: null },
    matchScore: { type: Number, default: null },
    detailsEnc: { type: String, default: null },
    provider: { type: String, default: null },
    providerRef: { type: String, default: null },
    costPaise: { type: Number, default: 0 },
    attempts: { type: Number, default: 0 },
    /** The owner looked at a name mismatch and accepted it. */
    override: {
      type: new Schema({ by: { type: Schema.Types.ObjectId, ref: 'User' }, reason: String, at: Date }, { _id: false }),
      default: null,
    },
    checkedAt: { type: Date, default: null },
  },
  { timestamps: true },
);
verificationCheckSchema.plugin(tenantPlugin);
verificationCheckSchema.index({ companyId: 1, requestId: 1 });
export const VerificationCheck = model('VerificationCheck', verificationCheckSchema);

export const DOCUMENT_KINDS = ['aadhaar', 'pan', 'dl', 'voter', 'passport', 'bank_proof', 'address', 'police', 'experience', 'other'] as const;
export type DocumentKind = (typeof DOCUMENT_KINDS)[number];

/**
 * A staff member's document (photo or PDF). Files are encrypted before they are stored and only opened
 * through short-lived links; every view is in History. Only the last 4 characters of the number are kept.
 */
const staffDocumentSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    kind: { type: String, enum: DOCUMENT_KINDS, required: true },
    /** Name for "other" ("Gas connection", "10th marksheet"). */
    label: { type: String, default: null },
    numberLast4: { type: String, default: null },
    files: {
      type: [new Schema({ key: { type: String, required: true }, mime: { type: String, required: true }, size: Number }, { _id: false })],
      default: [],
    },
    /** Company-local date it stops being valid ("2027-03-31"), for licences, passports, police certificates. */
    expiresOn: { type: String, default: null },
    /** The expiry date a reminder was already sent for, so each date reminds once. */
    remindedFor: { type: String, default: null },
    uploadedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    /** Staff uploaded it themselves, or the owner did with the staff member's agreement (signed slip photo). */
    consent: {
      type: new Schema(
        { by: { type: String, enum: ['staff', 'owner_on_behalf'], required: true }, at: Date, slipKey: { type: String, default: null }, slipMime: { type: String, default: null } },
        { _id: false },
      ),
      required: true,
    },
  },
  { timestamps: true },
);
staffDocumentSchema.plugin(tenantPlugin);
staffDocumentSchema.index({ companyId: 1, employeeId: 1, createdAt: -1 });
staffDocumentSchema.index({ companyId: 1, expiresOn: 1 });
export const StaffDocument = model('StaffDocument', staffDocumentSchema);
