import { Types } from 'mongoose';
import type { Ctx, Role } from '../../lib/context.js';
import { Leave, Membership, Notification, User } from '../../models/index.js';
import { membershipViews } from '../auth/memberships.js';
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

type Access = { companyId: Types.ObjectId; role: string; employeeId?: Types.ObjectId | null; branchIds?: Types.ObjectId[] | null };
type Choice = Access & { companyName: string };

/** A message waiting for "Which business?" is answered within this time. */
const PENDING_MS = 30 * 60_000;

/** Every business this number can use on WhatsApp, most recently used first, with names. */
async function whatsappChoices(userId: Types.ObjectId): Promise<Choice[]> {
  const list = await Membership.find({ userId, status: 'active' }).sort({ lastUsedAt: -1 }).lean();
  const views = await membershipViews(list);
  return list.map((m, i) => ({ companyId: m.companyId, role: m.role, employeeId: m.employeeId, branchIds: m.branchIds as Types.ObjectId[], companyName: views[i].companyName }));
}

/** "Which business?" with buttons (WhatsApp allows 3) and a numbered list for the rest. */
async function askBusiness(m: MessagingProvider, to: string, choices: Choice[], lang: 'en' | 'hi') {
  const text = L(lang, 'Which business is this for?', 'यह किस बिज़नेस के लिए है?');
  await m.sendButtons(to, text, choices.slice(0, 3).map((c) => ({ id: `biz:${c.companyId}`, title: c.companyName.slice(0, 20) })));
  if (choices.length > 3) {
    await m.sendText(to, `${choices.map((c, i) => `${i + 1}. ${c.companyName}`).join('\n')}\n${L(lang, 'Reply with the number.', 'नंबर लिखकर भेजें।')}`);
  }
}

/** Accepted: "switch", "switch to Gupta Sweets", "business badlo", "change business". */
const SWITCH_RX = /^(?:switch|change)(?:\s+(?:business|to))?\s*(.*)$|^(?:business|dukaan|dukan)\s+(?:badlo|change)\s*(.*)$/i;

async function handleInbound(m: MessagingProvider, ev: Extract<MessagingEvent, { type: 'message.inbound' }>, replay = false): Promise<void> {
  const found = await User.findOne({ phone: ev.from, deletedAt: null });
  const choices = found ? await whatsappChoices(found._id) : [];
  if (!found || !choices.length) {
    await m.sendText(ev.from, 'This number is not registered on StaffMint. Download the app to get started. / Yeh number StaffMint par registered nahi hai.');
    return;
  }
  const lang = (found.language as 'en' | 'hi') ?? 'hi';
  const text = ev.text?.trim() ?? '';
  const many = choices.length > 1;

  // Picking the business: a "Which business?" button, or a number reply to the list.
  const pending = found.whatsappPending?.at && Date.now() - found.whatsappPending.at.getTime() < PENDING_MS ? found.whatsappPending.text ?? '' : null;
  let picked: Choice | undefined;
  if (ev.buttonId?.startsWith('biz:')) picked = choices.find((c) => String(c.companyId) === ev.buttonId!.slice(4));
  else if (pending !== null && /^\d{1,2}$/.test(text)) picked = choices[Number(text) - 1];
  const sw = !ev.buttonId && many ? SWITCH_RX.exec(text) : null;
  if (sw) {
    const name = (sw[1] ?? sw[2] ?? '').trim().toLowerCase();
    const matches = name ? choices.filter((c) => c.companyName.toLowerCase().includes(name)) : [];
    if (matches.length === 1) picked = matches[0];
    else {
      found.whatsappPending = { text: '', at: new Date() } as any;
      await found.save();
      await askBusiness(m, ev.from, choices, lang);
      return;
    }
  }
  if (picked) {
    found.whatsappCompanyId = picked.companyId;
    found.whatsappPending = undefined as any;
    await found.save();
    await m.sendText(ev.from, L(lang, `Now using ${picked.companyName} on WhatsApp. Send "switch" to change.`, `अब WhatsApp पर ${picked.companyName}। बदलने के लिए "switch" भेजें।`));
    // The message that was waiting for this answer runs now.
    if (pending) await handleInbound(m, { ...ev, buttonId: undefined, text: pending }, true);
    return;
  }

  // Buttons from an alert belong to the business that sent it, whatever WhatsApp is set to.
  let access: Choice | undefined;
  if (ev.buttonId?.startsWith('leave:')) {
    const leave = await Leave.findById(ev.buttonId.split(':')[2]).setOptions({ skipTenant: true }).select('companyId').lean();
    access = choices.find((c) => String(c.companyId) === String(leave?.companyId));
  }
  access ??= many ? choices.find((c) => String(c.companyId) === String(found.whatsappCompanyId)) : choices[0];
  if (!access) {
    // Several businesses and none chosen yet: keep the message and ask.
    if (!replay) {
      found.whatsappPending = { text, at: new Date() } as any;
      await found.save();
    }
    await askBusiness(m, ev.from, choices, lang);
    return;
  }
  const user = { ...found.toObject(), companyId: access.companyId, role: access.role, employeeId: access.employeeId ?? null, branchIds: access.branchIds ?? [] };
  const reply = async (r: AssistantReply) => sendReply(m, ev.from, many ? { ...r, text: `*${access!.companyName}* · ${r.text}` } : r);
  const ctx = ctxForUser(user, 'whatsapp');
  const { plan } = await companyPlan({ _id: user.companyId });
  const isEmployee = user.role === 'employee';
  const allowed = isEmployee ? plan.features.includes('whatsapp_payslips') : plan.features.includes('whatsapp_assistant');
  try {
    if (ev.buttonId?.startsWith('leave:') && !isEmployee) {
      const [, decision, leaveId] = ev.buttonId.split(':');
      const leave = await decideLeave(ctx, leaveId, decision === 'approve' ? 'approved' : 'rejected');
      await m.sendText(ev.from, L(ctx.language, `Leave ${leave.status}.`, `छुट्टी ${leave.status === 'approved' ? 'मंज़ूर' : 'नामंज़ूर'} कर दी।`));
      return;
    }
    if (ev.buttonId?.startsWith('mint:')) {
      const [, pendingActionId, action, optionId] = ev.buttonId.split(':');
      const r = await confirm(ctx, { pendingActionId, action: action as any, optionId });
      await reply(r);
      return;
    }
    if (!allowed) {
      await m.sendText(ev.from, L(ctx.language, 'Please use the StaffMint app for this. WhatsApp commands are available on the Growth plan.', 'कृपया StaffMint ऐप इस्तेमाल करें। WhatsApp कमांड Growth प्लान में मिलते हैं।'));
      return;
    }
    let audio: { data: Buffer; mime: string } | undefined;
    if (ev.audio && m.fetchMedia) audio = await m.fetchMedia(ev.audio.mediaId);
    const r = await handleMessage(ctx, { text: ev.text, audio });
    await reply(r);
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

