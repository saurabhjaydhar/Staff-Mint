import { Schema, model } from 'mongoose';
import { tenantFields, tenantPlugin } from './tenant.js';

const importSessionSchema = new Schema(
  {
    ...tenantFields,
    kind: { type: String, enum: ['staff', 'attendance'], default: 'staff' },
    source: { type: String, default: 'auto' },
    detectedSource: String,
    fileKey: String,
    fileName: String,
    month: String,
    headers: { type: [String], default: [] },
    mapping: { type: Schema.Types.Mixed, default: {} },
    mappingMethod: { type: Schema.Types.Mixed, default: {} },
    rawRows: { type: [Schema.Types.Mixed], default: [] },
    fixes: { type: [{ row: Number, field: String, value: Schema.Types.Mixed }], default: [] },
    skipRows: { type: [Number], default: [] },
    status: { type: String, enum: ['review', 'committed', 'rolled_back'], default: 'review' },
    result: { type: Schema.Types.Mixed },
    createdEntities: { type: Schema.Types.Mixed },
    undoUntil: Date,
    rollbackUntil: Date,
    createdBy: { type: Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true },
);
importSessionSchema.plugin(tenantPlugin);
export const ImportSession = model('ImportSession', importSessionSchema);

const notificationSchema = new Schema(
  {
    ...tenantFields,
    userId: { type: Schema.Types.ObjectId, ref: 'User', index: true },
    employeeId: { type: Schema.Types.ObjectId, ref: 'Employee' },
    channel: { type: String, enum: ['push', 'whatsapp', 'sms', 'email', 'in_app'], required: true },
    template: String,
    title: String,
    body: String,
    data: Schema.Types.Mixed,
    to: String,
    status: { type: String, enum: ['queued', 'sent', 'delivered', 'read', 'failed'], default: 'queued' },
    provider: String,
    providerMsgId: { type: String, index: true },
    error: String,
    readAt: Date,
  },
  { timestamps: true },
);
notificationSchema.plugin(tenantPlugin);
export const Notification = model('Notification', notificationSchema);

const subscriptionSchema = new Schema(
  {
    ...tenantFields,
    provider: { type: String, required: true },
    providerSubId: { type: String, index: true },
    providerCustomerId: String,
    planCode: { type: String, required: true },
    interval: { type: String, enum: ['monthly', 'yearly'], default: 'monthly' },
    status: { type: String, enum: ['free', 'trialing', 'pending', 'active', 'past_due', 'cancelled'], default: 'free' },
    trialEndsAt: Date,
    currentPeriodEnd: Date,
    priceLockedUntil: Date,
    pricePaise: Number,
    currency: { type: String, default: 'INR' },
    cancelledAt: Date,
  },
  { timestamps: true },
);
subscriptionSchema.plugin(tenantPlugin);
export const Subscription = model('Subscription', subscriptionSchema);

/** Global (not tenant) — dynamic pricing. */
const planSchema = new Schema(
  {
    code: { type: String, required: true, unique: true },
    name: { type: String, required: true },
    country: { type: String, default: 'IN' },
    currency: { type: String, default: 'INR' },
    priceMonthlyPaise: { type: Number, default: 0 },
    priceYearlyPaise: { type: Number, default: 0 },
    taxPercent: { type: Number, default: 18 },
    staffLimit: { type: Number, default: 5 },
    extraStaffPricePaise: { type: Number, default: 0 },
    maxStaffHardCap: { type: Number, default: 50 },
    trialDays: { type: Number, default: 0 },
    features: { type: [String], default: [] },
    providerPlanIds: { type: Schema.Types.Mixed, default: {} }, // { razorpay: { monthly: 'plan_x', yearly: 'plan_y' } }
    sort: { type: Number, default: 0 },
    active: { type: Boolean, default: true },
  },
  { timestamps: true },
);
export const Plan = model('Plan', planSchema);

/** Global or per-company key/value config (attendance defaults, leave types, flags...). */
const configSchema = new Schema(
  {
    key: { type: String, required: true },
    companyId: { type: Schema.Types.ObjectId, default: null },
    value: Schema.Types.Mixed,
  },
  { timestamps: true },
);
configSchema.index({ key: 1, companyId: 1 }, { unique: true });
export const Config = model('Config', configSchema);

const featureFlagSchema = new Schema(
  {
    key: { type: String, required: true, unique: true },
    enabled: { type: Boolean, default: false },
    plans: { type: [String], default: [] },
    companyIds: { type: [Schema.Types.ObjectId], default: [] },
    description: String,
  },
  { timestamps: true },
);
export const FeatureFlag = model('FeatureFlag', featureFlagSchema);

const assistantSessionSchema = new Schema(
  {
    ...tenantFields,
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    channel: { type: String, default: 'app' },
    history: { type: [{ role: String, text: String, at: Date }], default: [] },
    pending: {
      type: [
        {
          id: String,
          intent: String,
          args: Schema.Types.Mixed,
          stage: { type: String, enum: ['choose', 'confirm'] },
          chooseField: String,
          options: [{ id: String, label: String }],
          expiresAt: Date,
          status: { type: String, enum: ['open', 'done', 'cancelled', 'expired'], default: 'open' },
        },
      ],
      default: [],
    },
  },
  { timestamps: true },
);
assistantSessionSchema.plugin(tenantPlugin);
export const AssistantSession = model('AssistantSession', assistantSessionSchema);

const auditLogSchema = new Schema(
  {
    ...tenantFields,
    actorId: { type: Schema.Types.ObjectId, ref: 'User', default: null },
    actorName: String,
    channel: { type: String, enum: ['app', 'web', 'assistant', 'whatsapp', 'system', 'import'], default: 'app' },
    action: { type: String, required: true },
    entity: { type: String, required: true },
    entityId: { type: Schema.Types.ObjectId, default: null },
    before: Schema.Types.Mixed,
    after: Schema.Types.Mixed,
    at: { type: Date, default: Date.now },
  },
  { versionKey: false },
);
auditLogSchema.plugin(tenantPlugin);
auditLogSchema.index({ companyId: 1, at: -1 });
// Append-only: block updates and deletes at the ODM layer.
for (const op of ['updateOne', 'updateMany', 'findOneAndUpdate', 'deleteOne', 'deleteMany', 'findOneAndDelete', 'replaceOne'] as const) {
  auditLogSchema.pre(op, function () {
    throw new Error('Audit log is append-only');
  });
}
export const AuditLog = model('AuditLog', auditLogSchema);

const webhookEventSchema = new Schema(
  {
    provider: String,
    kind: String,
    eventId: { type: String, required: true, unique: true },
    payload: Schema.Types.Mixed,
    processedAt: Date,
  },
  { timestamps: true },
);
export const WebhookEvent = model('WebhookEvent', webhookEventSchema);
