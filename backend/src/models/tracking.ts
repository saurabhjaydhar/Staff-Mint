import { Schema, model } from 'mongoose';
import { tenantFields, tenantPlugin } from './tenant.js';

export const TRACKING_END_REASONS = ['punch_out', 'shift_end', 'midnight', 'consent_withdrawn', 'turned_off'] as const;
export const TRACKING_EVENTS = ['location_off', 'location_on', 'permission_removed', 'mock_location', 'low_battery', 'stopped'] as const;

/**
 * One person's location sharing for one working day: from the first point after punch-in until punch-out
 * (or shift end + 2 hours, or midnight). Never off-shift.
 */
const trackingSessionSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    /** Company-local date. */
    date: { type: String, required: true },
    startedAt: { type: Date, required: true },
    endedAt: { type: Date, default: null },
    endReason: { type: String, enum: [...TRACKING_END_REASONS, null], default: null },
    /** Sharing must stop by this time (shift end + 2 hours, capped at 11:59 PM). */
    endsBy: { type: Date, required: true },
    lastPingAt: { type: Date, default: null },
    last: { type: new Schema({ lat: Number, lng: Number, accuracyM: Number, battery: Number }, { _id: false }), default: null },
    points: { type: Number, default: 0 },
    distanceM: { type: Number, default: 0 },
    events: { type: [new Schema({ at: Date, type: { type: String, enum: TRACKING_EVENTS } }, { _id: false })], default: [] },
    /** Alerts already sent to the owner in this session ("not updating", "location off"…), so none repeats. */
    alerted: { type: [String], default: [] },
    consentVersion: { type: String, default: null },
  },
  { timestamps: true },
);
trackingSessionSchema.plugin(tenantPlugin);
trackingSessionSchema.index({ companyId: 1, employeeId: 1, date: 1 });
trackingSessionSchema.index({ companyId: 1, endedAt: 1 });
export const TrackingSession = model('TrackingSession', trackingSessionSchema);

/** One location point. Deleted automatically at `expireAt` (tracking.keepDays after it was taken). */
const locationPingSchema = new Schema(
  {
    ...tenantFields,
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee', required: true },
    sessionId: { type: Schema.Types.ObjectId, ref: 'TrackingSession', required: true },
    at: { type: Date, required: true },
    lat: { type: Number, required: true },
    lng: { type: Number, required: true },
    accuracyM: { type: Number, default: null },
    speed: { type: Number, default: null },
    battery: { type: Number, default: null },
    mock: { type: Boolean, default: false },
    expireAt: { type: Date, required: true },
  },
  { timestamps: false },
);
locationPingSchema.plugin(tenantPlugin);
locationPingSchema.index({ companyId: 1, sessionId: 1, at: 1 });
locationPingSchema.index({ expireAt: 1 }, { expireAfterSeconds: 0 });
export const LocationPing = model('LocationPing', locationPingSchema);
