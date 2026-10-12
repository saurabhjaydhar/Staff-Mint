import { Schema, model, type InferSchemaType, type HydratedDocument } from 'mongoose';
import { tenantFields, tenantPlugin } from './tenant.js';

const employeeSchema = new Schema(
  {
    ...tenantFields,
    name: { type: String, required: true, trim: true },
    phone: { type: String, required: true },
    branchId: { type: Schema.Types.ObjectId, ref: 'Branch' },
    shiftId: { type: Schema.Types.ObjectId, ref: 'Shift' },
    wageType: { type: String, enum: ['monthly', 'daily'], default: 'monthly' },
    ratePaise: { type: Number, default: 0 },
    designation: String,
    joiningDate: String,
    exitDate: String,
    status: { type: String, enum: ['active', 'inactive'], default: 'active' },
    appRole: { type: String, enum: ['employee', 'manager'], default: 'employee' },
    /** null = follow the business setting (settings.attendanceMarking). */
    attendanceMarking: { type: String, enum: ['self', 'owner'], default: null },
    consent: { location: { type: Boolean, default: false }, at: Date },
    /** Face match reference photo. Explicit, separate consent; deleted on exit or withdrawal. */
    face: {
      status: { type: String, enum: ['none', 'pending', 'approved'], default: 'none' },
      refKey: { type: String, default: null },
      consentAt: { type: Date, default: null },
      enrolledAt: { type: Date, default: null },
      approvedAt: { type: Date, default: null },
      approvedBy: { type: Schema.Types.ObjectId, ref: 'User', default: null },
    },
    userId: { type: Schema.Types.ObjectId, ref: 'User', default: null },
    language: { type: String, enum: ['en', 'hi'], default: 'hi' },
    bankDetailsEnc: { type: String, default: null }, // field-level encrypted JSON
    bankUpdatedAt: { type: Date, default: null },
    /** Last app invite sent to this staff number (WhatsApp/SMS). */
    invitedAt: { type: Date, default: null },
    /** The number now belongs to someone else (recycled); no login attaches until the owner updates it. */
    phoneRecycledAt: { type: Date, default: null },
    emergencyContact: { name: String, phone: String, relation: String },
    /** Shown on salary slips: the shop's own staff number, and PF/ESI/PAN when the shop uses them. */
    employeeCode: { type: String, default: null },
    uan: { type: String, default: null },
    esicNumber: { type: String, default: null },
    panEnc: { type: String, default: null }, // field-level encrypted
    pfExempt: { type: Boolean, default: false },
    esiExempt: { type: Boolean, default: false },
    importSessionId: { type: Schema.Types.ObjectId, ref: 'ImportSession', default: null },
    openingLastNetPaise: { type: Number, default: null }, // last salary from the previous app (import), used for anomaly checks
  },
  { timestamps: true },
);
employeeSchema.plugin(tenantPlugin);
employeeSchema.index({ companyId: 1, phone: 1 }, { unique: true, partialFilterExpression: { deletedAt: null } });
employeeSchema.index({ phone: 1 });
export type EmployeeDoc = HydratedDocument<InferSchemaType<typeof employeeSchema>>;
export const Employee = model('Employee', employeeSchema);

const salaryStructureSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    effectiveFrom: { type: String, required: true },
    wageType: { type: String, enum: ['monthly', 'daily'], required: true },
    basePaise: { type: Number, required: true },
    allowances: { type: [{ name: String, amountPaise: Number }], default: [] },
    deductions: { type: [{ name: String, amountPaise: Number }], default: [] },
  },
  { timestamps: true },
);
salaryStructureSchema.plugin(tenantPlugin);
salaryStructureSchema.index({ companyId: 1, employeeId: 1, effectiveFrom: -1 });
export const SalaryStructure = model('SalaryStructure', salaryStructureSchema);
