import { Schema, model } from 'mongoose';
import { tenantFields, tenantPlugin } from './tenant.js';

const advanceSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true, index: true },
    amountPaise: { type: Number, required: true },
    date: { type: String, required: true },
    mode: { type: String, enum: ['installments', 'full_next'], default: 'full_next' },
    installments: { type: Number, default: 1 },
    skipMonths: { type: [String], default: [] },
    /** Repayments keyed by payroll month; replaced whenever that month's run is approved. */
    repayments: { type: [{ month: String, runId: Schema.Types.ObjectId, amountPaise: Number }], default: [] },
    openingRepaidPaise: { type: Number, default: 0 },
    status: { type: String, enum: ['active', 'closed'], default: 'active' },
    note: String,
    source: { type: String, default: 'app' },
    importSessionId: { type: Schema.Types.ObjectId, default: null },
  },
  { timestamps: true },
);
advanceSchema.plugin(tenantPlugin);
export const Advance = model('Advance', advanceSchema);

const adjustmentSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    month: { type: String, required: true },
    type: { type: String, enum: ['bonus', 'deduction'], required: true },
    amountPaise: { type: Number, required: true },
    note: String,
  },
  { timestamps: true },
);
adjustmentSchema.plugin(tenantPlugin);
adjustmentSchema.index({ companyId: 1, month: 1 });
export const Adjustment = model('Adjustment', adjustmentSchema);
