import { Types } from 'mongoose';
import { Company, Employee, Membership, Notification, User } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import { logger } from '../../lib/logger.js';

export interface NotifyMessage {
  template: string;
  title: string;
  titleHi?: string;
  body: string;
  bodyHi?: string;
  data?: Record<string, string>;
  /** WhatsApp utility template + params. Sent only when the channel is allowed. */
  whatsapp?: { template: string; params: string[]; documentUrl?: string; filename?: string; buttons?: { id: string; title: string }[] };
}

const pick = (lang: string | undefined, en: string, hi?: string) => (lang === 'hi' && hi ? hi : en);

async function pushToUser(companyId: Types.ObjectId, user: any, msg: NotifyMessage, employeeId?: Types.ObjectId | null) {
  const title = pick(user.language, msg.title, msg.titleHi);
  const body = pick(user.language, msg.body, msg.bodyHi);
  await Notification.create({ companyId, userId: user._id, employeeId: employeeId ?? null, channel: 'in_app', template: msg.template, title, body, data: msg.data, status: 'delivered' });
  const tokens = (user.pushTokens ?? []).map((t: any) => t.token).filter(Boolean);
  if (!tokens.length) return;
  try {
    const push = await provider('push');
    // A person's phone may be open in another of their businesses; the app uses companyId to switch on tap.
    const r = await push.send(tokens, { title, body, data: { ...(msg.data ?? {}), companyId: String(companyId) } });
    await Notification.create({ companyId, userId: user._id, employeeId: employeeId ?? null, channel: 'push', template: msg.template, title, body, data: msg.data, status: 'sent', provider: push.name });
    if (r.invalidTokens.length) await User.updateOne({ _id: user._id }, { $pull: { pushTokens: { token: { $in: r.invalidTokens } } } });
  } catch (err) {
    logger.warn({ err }, 'push failed');
  }
}

export async function sendWhatsApp(companyId: Types.ObjectId, to: string, wa: NonNullable<NotifyMessage['whatsapp']>, meta: { userId?: Types.ObjectId | null; employeeId?: Types.ObjectId | null; language?: 'en' | 'hi' } = {}) {
  const company = await Company.findById(companyId).lean();
  const n = await Notification.create({ companyId, userId: meta.userId ?? null, employeeId: meta.employeeId ?? null, channel: 'whatsapp', template: wa.template, to, data: { params: wa.params }, status: 'queued' });
  try {
    const messaging = await provider('messaging', company?.messagingProvider);
    const r = await messaging.sendTemplate(to, wa.template, wa.params, { language: meta.language, documentUrl: wa.documentUrl, filename: wa.filename, buttons: wa.buttons });
    n.status = 'sent';
    n.provider = messaging.name;
    n.providerMsgId = r.providerMsgId;
  } catch (err: any) {
    n.status = 'failed';
    n.error = err?.message;
    logger.warn({ err, template: wa.template }, 'whatsapp send failed');
  }
  await n.save();
  return n;
}

/** Owner alerts: push first, WhatsApp only when the owner turned it on (PRD §11). */
export async function notifyOwners(companyId: Types.ObjectId, msg: NotifyMessage, opts: { includeManagers?: boolean } = {}) {
  const company = await Company.findById(companyId).lean();
  const roles: ('owner' | 'manager')[] = opts.includeManagers === false ? ['owner'] : ['owner', 'manager'];
  const ms = await Membership.find({ companyId, role: { $in: roles }, status: 'active' }).select('userId role').lean();
  const roleOf = new Map(ms.map((m) => [String(m.userId), m.role]));
  const users = ms.length ? await User.find({ _id: { $in: ms.map((m) => m.userId) }, deletedAt: null }).lean() : [];
  for (const u of users) {
    await pushToUser(companyId, u, msg);
    if (msg.whatsapp && company?.settings?.whatsappAlerts && roleOf.get(String(u._id)) === 'owner') await sendWhatsApp(companyId, u.phone, msg.whatsapp, { userId: u._id, language: u.language as any });
  }
}

export async function notifyEmployee(companyId: Types.ObjectId, employeeId: Types.ObjectId, msg: NotifyMessage, opts: { whatsapp?: boolean } = {}) {
  const emp = await Employee.findOne({ _id: employeeId, companyId }).lean();
  if (!emp) return;
  const user = emp.userId ? await User.findById(emp.userId).lean() : null;
  if (user) await pushToUser(companyId, user, msg, emp._id);
  if (opts.whatsapp && msg.whatsapp) await sendWhatsApp(companyId, emp.phone, msg.whatsapp, { userId: user?._id, employeeId: emp._id, language: emp.language as any });
}

export async function listMyNotifications(companyId: Types.ObjectId, userId: Types.ObjectId) {
  const list = await Notification.find({ companyId, userId, channel: 'in_app' }).sort({ createdAt: -1 }).limit(50).lean();
  return list.map((n) => ({ id: String(n._id), title: n.title, body: n.body, data: n.data ?? {}, readAt: n.readAt ?? null, createdAt: n.createdAt }));
}

export async function markRead(companyId: Types.ObjectId, userId: Types.ObjectId, ids: string[]) {
  await Notification.updateMany({ companyId, userId, _id: { $in: ids } }, { readAt: new Date() });
}

export async function registerPushToken(userId: Types.ObjectId, token: string, platform: string) {
  await User.updateOne({ _id: userId }, { $pull: { pushTokens: { token } } });
  await User.updateOne({ _id: userId }, { $push: { pushTokens: { $each: [{ token, platform, updatedAt: new Date() }], $slice: -5 } } });
}
