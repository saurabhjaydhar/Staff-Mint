import { Schema, model, type InferSchemaType, type HydratedDocument } from 'mongoose';
import { tenantFields, tenantPlugin } from './tenant.js';

export const ATTENDANCE_STATUSES = ['present', 'absent', 'half_day', 'leave', 'holiday', 'week_off'] as const;
export type AttendanceStatus = (typeof ATTENDANCE_STATUSES)[number];

const punchSchema = new Schema({
  type: { type: String, enum: ['in', 'out'], required: true },
  /** Effective time used by rules: server time for online punches, device time for offline-synced punches. */
  clientTime: { type: Date, required: true },
  deviceTime: { type: Date },
  serverTime: { type: Date, required: true },
  geo: { lat: Number, lng: Number, accuracyM: Number },
  distanceM: { type: Number, default: null },
  insideGeofence: { type: Boolean, default: null },
  selfieKey: { type: String, default: null },
  mockLocation: { type: Boolean, default: false },
  /** Result of the phone screen-lock prompt; only pass/fail is known, never the biometric itself. */
  lockCheck: { type: String, enum: ['passed', 'failed', 'unavailable', null], default: null },
  /** Selfie vs approved face photo; null when face check is off or the person is not enrolled. */
  face: {
    result: { type: String, enum: ['match', 'unsure', 'mismatch', 'no_face', 'many_faces', 'error', null], default: null },
    similarity: { type: Number, default: null },
  },
  deviceId: String,
  clientPunchId: { type: String, index: true },
  source: { type: String, enum: ['app', 'offline_sync', 'owner', 'assistant', 'import'], default: 'app' },
  flags: { type: [String], default: [] },
  approval: { type: String, enum: ['not_required', 'pending', 'approved', 'rejected'], default: 'not_required' },
});

const attendanceSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    date: { type: String, required: true },
    status: { type: String, enum: [...ATTENDANCE_STATUSES, null], default: null },
    leaveType: { type: String, enum: ['paid', 'sick', 'unpaid', null], default: null },
    punches: { type: [punchSchema], default: [] },
    lateMinutes: { type: Number, default: 0 },
    earlyOutMinutes: { type: Number, default: 0 },
    workedMinutes: { type: Number, default: 0 },
    overridden: { type: Boolean, default: false },
    overrideReason: String,
    overriddenBy: { type: Schema.Types.ObjectId, ref: 'User' },
    autoMarked: { type: Boolean, default: false },
    flags: { type: [String], default: [] },
    importSessionId: { type: Schema.Types.ObjectId, default: null },
  },
  { timestamps: true },
);
attendanceSchema.plugin(tenantPlugin);
attendanceSchema.index({ employeeId: 1, date: 1 }, { unique: true });
attendanceSchema.index({ companyId: 1, date: 1 });
export type AttendanceDoc = HydratedDocument<InferSchemaType<typeof attendanceSchema>>;
export const Attendance = model('Attendance', attendanceSchema);
