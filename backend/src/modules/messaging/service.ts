import { Types } from 'mongoose';
import type { Ctx, Role } from '../../lib/context.js';
import { Notification, User } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import type { MessagingEvent, MessagingProvider } from '../../providers/types.js';
import { logger } from '../../lib/logger.js';
import { companyPlan } from '../billing/plans.js';
import { handleMessage, confirm, type AssistantReply } from '../assistant/service.js';
import { decideLeave } from '../leave/service.js';
import { L } from '../assistant/tools.js';

export function ctxForUser(user: any, channel: Ctx['channel']): Ctx {
  return {
    userId: user._id,
    companyId: user.companyId,
    role: user.role as Role,
    employeeId: user.employeeId ?? null,
    branchIds: (user.branchIds ?? []) as Types.ObjectId[],
    actorName: user.name || user.phone,
    channel,
    language: (user.language as 'en' | 'hi') ?? 'hi',
  };
}

async function sendReply(m: MessagingProvider, to: string, r: AssistantReply) {
  if ((r.kind === 'confirm' || r.kind === 'choose') && r.options?.length && r.pendingActionId) {
    const buttons = r.options.slice(0, 3).map((o) => ({ id: r.kind === 'choose' ? `mint:${r.pendingActionId}:choose:${o.id}` : `mint:${r.pendingActionId}:${o.id}`, title: o.label.slice(0, 20) }));
    await m.sendButtons(to, r.text, buttons);
    if (r.kind === 'choose' && r.options.length > 3) await m.sendText(to, r.options.slice(3).map((o, i) => `${i + 4}. ${o.label}`).join('\n'));
    return;
  }
  if (r.attachment) await m.sendDocument(to, r.attachment.url, r.attachment.filename, r.text);
  else await m.sendText(to, r.text);
}

async function handleInbound(m: MessagingProvider, ev: Extract<MessagingEvent, { type: 'message.inbound' }>) {
  const user = await User.findOne({ phone: ev.from, deletedAt: null }).lean();
  if (!user?.companyId) {
    await m.sendText(ev.from, 'This number is not registered on StaffMint. Download the app to get started. / Yeh number StaffMint par registered nahi hai.');
    return;
  }
  const ctx = ctxForUser(user, 'whatsapp');
  const { plan } = await companyPlan({ _id: user.companyId });
  const isEmployee = user.role === 'employee';
  const allowed = isEmployee ? plan.features.includes('whatsapp_payslips') : plan.features.includes('whatsapp_assistant');
  try {
    if (ev.buttonId?.startsWith('leave:') && !isEmployee) {
      const [, decision, leaveId] = ev.buttonId.split(':');
      const leave = await decideLeave(ctx, leaveId, decision === 'approve' ? 'approved' : 'rejected');
      await m.sendText(ev.from, L(ctx.language, `Leave ${leave.status}.`, `Chutti ${leave.status === 'approved' ? 'manzoor' : 'na-manzoor'} kar di.`));
      return;
    }
    if (ev.buttonId?.startsWith('mint:')) {
      const [, pendingActionId, action, optionId] = ev.buttonId.split(':');
      const r = await confirm(ctx, { pendingActionId, action: action as any, optionId });
      await sendReply(m, ev.from, r);
      return;
    }
    if (!allowed) {
      await m.sendText(ev.from, L(ctx.language, 'Please use the StaffMint app for this. WhatsApp commands are available on the Growth plan.', 'Kripya StaffMint app use karein. WhatsApp commands Growth plan mein milte hain.'));
      return;
    }
    let audio: { data: Buffer; mime: string } | undefined;
    if (ev.audio && m.fetchMedia) audio = await m.fetchMedia(ev.audio.mediaId);
    const r = await handleMessage(ctx, { text: ev.text, audio });
    await sendReply(m, ev.from, r);
  } catch (err: any) {
    logger.warn({ err }, 'whatsapp inbound failed');
    await m.sendText(ev.from, err?.message ?? 'Something went wrong');
  }
}

export async function processMessagingEvents(providerName: string, events: MessagingEvent[]) {
  const m = await provider('messaging', providerName);
  for (const ev of events) {
    if (ev.type === 'message.status') {
      await Notification.updateOne({ providerMsgId: ev.providerMsgId }, { status: ev.status, error: ev.error }).setOptions({ skipTenant: true });
      continue;
    }
    await handleInbound(m, ev);
  }
}

