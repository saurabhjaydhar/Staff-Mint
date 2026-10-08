import { Schema, model } from 'mongoose';
import { tenantFields, tenantPlugin } from './tenant.js';

const leaveSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true, index: true },
    type: { type: String, enum: ['paid', 'sick', 'unpaid'], required: true },
    from: { type: String, required: true },
    to: { type: String, required: true },
    halfDay: { type: Boolean, default: false },
    days: { type: Number, required: true },
    reason: String,
    status: { type: String, enum: ['pending', 'approved', 'rejected', 'cancelled'], default: 'pending' },
    requestedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    decidedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    decidedAt: Date,
    note: String,
  },
  { timestamps: true },
);
leaveSchema.plugin(tenantPlugin);
export const Leave = model('Leave', leaveSchema);

const leaveBalanceSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    year: { type: Number, required: true },
    paid: { type: Number, default: 0 },
    sick: { type: Number, default: 0 },
    usedPaid: { type: Number, default: 0 },
    usedSick: { type: Number, default: 0 },
  },
  { timestamps: true },
);
leaveBalanceSchema.plugin(tenantPlugin);
leaveBalanceSchema.index({ employeeId: 1, year: 1 }, { unique: true });
export const LeaveBalance = model('LeaveBalance', leaveBalanceSchema);
