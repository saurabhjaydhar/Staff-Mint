import { Schema, model } from 'mongoose';
import { tenantFields, tenantPlugin } from './tenant.js';

const branchSchema = new Schema(
  {
    ...tenantFields,
    name: { type: String, required: true },
    geo: { type: { type: String, enum: ['Point'], default: 'Point' }, coordinates: { type: [Number], default: undefined } },
    address: String,
    radiusM: { type: Number, default: 100 },
    shiftId: { type: Schema.Types.ObjectId, ref: 'Shift' },
    isDefault: { type: Boolean, default: false },
  },
  { timestamps: true },
);
branchSchema.plugin(tenantPlugin);
export const Branch = model('Branch', branchSchema);

const shiftSchema = new Schema(
  {
    ...tenantFields,
    name: { type: String, default: 'General' },
    start: { type: String, required: true },
    end: { type: String, required: true },
    graceMinutes: { type: Number, default: null },
    weeklyOff: { type: [Number], default: [0] },
    isDefault: { type: Boolean, default: false },
  },
  { timestamps: true },
);
shiftSchema.plugin(tenantPlugin);
export const Shift = model('Shift', shiftSchema);

const holidaySchema = new Schema(
  {
    ...tenantFields,
    date: { type: String, required: true },
    name: { type: String, required: true },
    source: { type: String, default: 'manual' },
  },
  { timestamps: true },
);
holidaySchema.plugin(tenantPlugin);
holidaySchema.index({ companyId: 1, date: 1 }, { unique: true });
export const Holiday = model('Holiday', holidaySchema);

/**
 * One person's plan for one day. `kind`/`shiftId` is what the owner has set (may not be sent yet);
 * `sent` is what staff were last sent: attendance and salary use only that.
 * kind 'usual' means "back to their usual shift" (removed once sent).
 */
const rosterEntrySchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    date: { type: String, required: true },
    kind: { type: String, enum: ['shift', 'off', 'usual'], required: true },
    shiftId: { type: Schema.Types.ObjectId, ref: 'Shift', default: null },
    sent: {
      type: new Schema({ kind: { type: String, enum: ['shift', 'off'] }, shiftId: { type: Schema.Types.ObjectId, default: null }, at: Date }, { _id: false }),
      default: null,
    },
    updatedBy: { type: Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true },
);
rosterEntrySchema.plugin(tenantPlugin);
rosterEntrySchema.index({ employeeId: 1, date: 1 }, { unique: true });
rosterEntrySchema.index({ companyId: 1, date: 1 });
export const RosterEntry = model('RosterEntry', rosterEntrySchema);
