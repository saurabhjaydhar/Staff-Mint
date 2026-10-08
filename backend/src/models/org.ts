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
