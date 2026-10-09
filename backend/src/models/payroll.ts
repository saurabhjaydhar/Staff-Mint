import { Schema, model } from 'mongoose';
import { tenantFields, tenantPlugin } from './tenant.js';

const payrollRunSchema = new Schema(
  {
    ...tenantFields,
    month: { type: String, required: true },
    revision: { type: Number, default: 1 },
    status: { type: String, enum: ['draft', 'approved', 'paid', 'superseded'], default: 'draft' },
    engineVersion: { type: String, required: true },
    settingsSnapshot: { type: Schema.Types.Mixed },
    totals: { grossPaise: Number, deductionsPaise: Number, netPaise: Number, employees: Number },
    anomalies: { type: [{ employeeId: Schema.Types.ObjectId, employeeName: String, code: String, message: String, messageHi: String }], default: [] },
    approvedAt: Date,
    approvedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    paidAt: Date,
    previousRunId: { type: Schema.Types.ObjectId, default: null },
  },
  { timestamps: true },
);
payrollRunSchema.plugin(tenantPlugin);
payrollRunSchema.index({ companyId: 1, month: 1, revision: 1 }, { unique: true });
export const PayrollRun = model('PayrollRun', payrollRunSchema);

const lineSchema = new Schema(
  {
    code: String,
    kind: { type: String, enum: ['earning', 'deduction'] },
    amountPaise: Number,
    label: { en: String, hi: String },
    explanation: { en: String, hi: String },
    refId: { type: Schema.Types.ObjectId, default: null },
  },
  { _id: false },
);

const payslipSchema = new Schema(
  {
    ...tenantFields,
    runId: { type: Schema.Types.ObjectId, ref: 'PayrollRun', required: true, index: true },
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true, index: true },
    employeeName: String,
    employeePhone: String,
    month: { type: String, required: true },
    revision: { type: Number, default: 1 },
    wageType: String,
    ratePaise: Number,
    payableDays: Number,
    daysInMonth: Number,
    divisor: Number,
    summary: { present: Number, halfDay: Number, absent: Number, paidLeave: Number, unpaidLeave: Number, holidays: Number, weekOffs: Number, unmarked: Number },
    lines: { type: [lineSchema], default: [] },
    grossPaise: Number,
    deductionsPaise: Number,
    netPaise: Number,
    inputs: { type: Schema.Types.Mixed }, // snapshot for reproducibility
    status: { type: String, enum: ['draft', 'final', 'sent'], default: 'draft' },
    pdfKey: { type: String, default: null },
    sentAt: Date,
  },
  { timestamps: true },
);
payslipSchema.plugin(tenantPlugin);
payslipSchema.pre(['updateOne', 'findOneAndUpdate', 'updateMany'], async function (this: any) {
  // Payslips are immutable once sent; only delivery metadata may be touched.
  const update = this.getUpdate() ?? {};
  const set = { ...(update.$set ?? {}), ...Object.fromEntries(Object.entries(update).filter(([k]) => !k.startsWith('$'))) };
  const allowed = new Set(['status', 'sentAt', 'pdfKey', 'updatedAt']);
  const touchesContent = Object.keys(set).some((k) => !allowed.has(k));
  if (!touchesContent) return;
  const existing = await this.model.findOne(this.getFilter()).setOptions({ skipTenant: true }).select('status').lean();
  if (existing?.status === 'sent') throw new Error('Payslip is immutable after sending; create a revision instead');
});
export const Payslip = model('Payslip', payslipSchema);
