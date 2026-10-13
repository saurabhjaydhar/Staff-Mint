/**
 * Mint orchestration (PRD F5): LLM extracts intent + entities; backend validates,
 * resolves names (ambiguous → buttons), and every write waits for explicit confirmation.
 */
import { Types } from 'mongoose';
import { randomUUID } from 'node:crypto';
import type { Ctx } from '../../lib/context.js';
import { AppError } from '../../lib/errors.js';
import { todayIn } from '../../lib/dates.js';
import { env } from '../../config/env.js';
import { logger } from '../../lib/logger.js';
import { AssistantSession, Company, Employee, Shift } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import type { LlmExtractResult } from '../../providers/types.js';
import { companyPlan } from '../billing/plans.js';
import { getConfig } from '../config/service.js';
import { employeeScope } from '../employees/service.js';
import { L, toolByName, toolsForRole, type ToolDef } from './tools.js';

export interface AssistantReply {
  sessionId: string;
  kind: 'answer' | 'confirm' | 'choose' | 'done' | 'cancelled' | 'error';
  text: string;
  options?: { id: string; label: string }[];
  pendingActionId?: string;
  preview?: { title: string; rows: { label: string; value: string }[] };
  data?: unknown;
  attachment?: { url: string; filename: string };
  intent?: string | null;
}

const MIN_CONFIDENCE = 0.6;

// ---------- Name resolution ----------
function levenshtein(a: string, b: string): number {
  const dp = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) dp[0][j] = j;
  for (let i = 1; i <= a.length; i++)
    for (let j = 1; j <= b.length; j++) dp[i][j] = Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  return dp[a.length][b.length];
}

/** Fuzzy match a spoken name against staff (handles Hinglish spelling variants like Rames/Ramesh, Sures/Suresh). */
export function matchEmployees<T extends { name: string }>(spoken: string, emps: T[]): T[] {
  const s = spoken.toLowerCase().trim().replace(/\s+/g, ' ');
  if (!s) return [];
  const exact = emps.filter((e) => e.name.toLowerCase() === s);
  if (exact.length) return exact;
  const byFirst = emps.filter((e) => e.name.toLowerCase().split(' ')[0] === s.split(' ')[0] && (s.split(' ').length === 1 || e.name.toLowerCase().includes(s)));
  if (byFirst.length) return byFirst;
  const contains = emps.filter((e) => e.name.toLowerCase().includes(s) || e.name.toLowerCase().split(' ').some((p) => p.startsWith(s) && s.length >= 3));
  if (contains.length) return contains;
  const first = s.split(' ')[0];
  const scored = emps
    .map((e) => ({ e, d: Math.min(...e.name.toLowerCase().split(' ').map((p) => levenshtein(p, first))) }))
    .filter((x) => x.d <= (first.length >= 6 ? 2 : 1));
  const best = Math.min(...scored.map((x) => x.d));
  return scored.filter((x) => x.d === best).map((x) => x.e);
}

// ---------- Sessions ----------
async function loadSession(ctx: Ctx, sessionId?: string) {
  if (sessionId && Types.ObjectId.isValid(sessionId)) {
    const s = await AssistantSession.findOne({ _id: sessionId, companyId: ctx.companyId, userId: ctx.userId });
    if (s) return s;
  }
  return AssistantSession.create({ companyId: ctx.companyId, userId: ctx.userId!, channel: ctx.channel, history: [], pending: [] });
}

function remember(session: any, role: 'user' | 'assistant', text: string) {
  session.history.push({ role, text: text.slice(0, 1000), at: new Date() });
  if (session.history.length > 30) session.history = session.history.slice(-30);
}

async function addPending(session: any, p: { intent: string; args: any; stage: 'choose' | 'confirm'; chooseField?: string; options?: { id: string; label: string }[] }) {
  const ttl = await getConfig<number>('assistant.pendingTtlMinutes');
  for (const old of session.pending) if (old.status === 'open') old.status = 'expired'; // only one open action at a time
  const id = randomUUID();
  session.pending.push({ id, ...p, expiresAt: new Date(Date.now() + ttl * 60_000), status: 'open' });
  if (session.pending.length > 20) session.pending = session.pending.slice(-20);
  return id;
}

// ---------- Core ----------
async function extract(ctx: Ctx, text: string, history: { role: string; text: string }[]): Promise<LlmExtractResult> {
  const company = await Company.findById(ctx.companyId).lean();
  const today = todayIn(company!.timezone);
  const names = ctx.role === 'employee' ? [] : (await Employee.find({ ...employeeScope(ctx), status: 'active' }).select('name').lean()).map((e) => e.name);
  const shiftNames = ctx.role === 'employee' ? [] : (await Shift.find({ companyId: ctx.companyId, deletedAt: null }).select('name').lean()).map((s) => s.name);
  const input = { text, tools: toolsForRole(ctx.role), context: { today, language: ctx.language, employeeNames: names, shiftNames, role: ctx.role === 'system' ? 'owner' : ctx.role, history } };
  const rules = await provider('rules');
  const fast = await rules.extract(input);
  const llm = await provider('llm');
  if (llm.name === 'rules' || (env.ASSISTANT_RULES_FASTPATH && fast.intent && fast.confidence >= 0.85)) return fast;
  try {
    const r = await llm.extract(input);
    if (r.intent || r.reply) return r;
    return fast;
  } catch (err) {
    logger.warn({ err }, 'LLM extract failed; using rules result');
    return fast;
  }
}

function toolAllowed(ctx: Ctx, tool: ToolDef) {
  const role = ctx.role === 'system' ? 'owner' : ctx.role;
  return tool.roles.includes(role as any);
}

async function proceed(ctx: Ctx, session: any, tool: ToolDef, args: any, text: string): Promise<AssistantReply> {
  const sid = String(session._id);
  // Resolve employee name → id (ambiguous → buttons; none → ask).
  if (tool.employeeArg && args[tool.employeeArg] && !args.employeeId) {
    const emps = await Employee.find({ ...employeeScope(ctx), status: 'active' }).select('name phone designation').lean();
    const matches = matchEmployees(String(args[tool.employeeArg]), emps);
    if (matches.length === 0) {
      return { sessionId: sid, kind: 'error', intent: tool.name, text: L(ctx.language, `I couldn't find staff named "${args[tool.employeeArg]}". Please check the name.`, `"${args[tool.employeeArg]}" नाम का स्टाफ़ नहीं मिला। नाम जाँच लें।`) };
    }
    if (matches.length > 1) {
      const options = matches.slice(0, 5).map((e) => ({ id: String(e._id), label: `${e.name}${e.designation ? ` (${e.designation})` : ''} ·${e.phone.slice(-4)}` }));
      const pendingActionId = await addPending(session, { intent: tool.name, args, stage: 'choose', chooseField: 'employeeId', options });
      await session.save();
      return { sessionId: sid, kind: 'choose', intent: tool.name, pendingActionId, options, text: L(ctx.language, `Which ${args[tool.employeeArg]}?`, `कौन सा ${args[tool.employeeArg]}?`) };
    }
    args.employeeId = String(matches[0]._id);
    args.employeeLabel = matches[0].name;
  }
  if (args.employeeId && !args.employeeLabel) {
    const e = await Employee.findOne({ ...employeeScope(ctx), _id: args.employeeId }).select('name').lean();
    if (!e) throw new AppError('NOT_FOUND', 'Employee not found');
    args.employeeLabel = e.name;
  }

  if (tool.kind === 'read') {
    const r = await tool.execute(ctx, args, { text });
    return { sessionId: sid, kind: 'answer', intent: tool.name, text: r.text, data: r.data, attachment: r.attachment };
  }
  const preview = await tool.preview!(ctx, args);
  const pendingActionId = await addPending(session, { intent: tool.name, args, stage: 'confirm' });
  await session.save();
  return {
    sessionId: sid,
    kind: 'confirm',
    intent: tool.name,
    pendingActionId,
    preview,
    options: [
      { id: 'confirm', label: L(ctx.language, 'Yes, save', 'हाँ, कर दो') },
      { id: 'cancel', label: L(ctx.language, 'Cancel', 'नहीं') },
    ],
    text: `${preview.title}\n${preview.rows.map((r) => `${r.label}: ${r.value}`).join('\n')}`,
  };
}

export async function handleMessage(ctx: Ctx, input: { text?: string; audio?: { data: Buffer; mime: string }; sessionId?: string }): Promise<AssistantReply> {
  const { plan } = await companyPlan({ _id: ctx.companyId });
  if (!plan.features.includes('assistant')) {
    throw new AppError('FEATURE_NOT_IN_PLAN', L(ctx.language, 'Mint assistant is available on Starter and above.', 'Mint सहायक Starter प्लान और उससे ऊपर में मिलता है।'), { feature: 'assistant' });
  }
  let text = input.text?.trim() ?? '';
  if (!text && input.audio) text = (await (await provider('speech')).transcribe(input.audio.data, input.audio.mime, { languageHint: 'hi' })).text.trim();
  if (!text) throw new AppError('VALIDATION_ERROR', 'Say or type something');
  const session = await loadSession(ctx, input.sessionId);
  const sid = String(session._id);

  // Plain yes/no replies to an open confirmation (useful on WhatsApp without buttons).
  const open = session.pending.find((p: any) => p.status === 'open' && p.stage === 'confirm' && p.expiresAt > new Date());
  if (open && /^(haan|han|ha|yes|y|ok|okay|theek|thik|kar do|confirm|ji|haan ji)$/i.test(text)) return confirm(ctx, { pendingActionId: open.id!, action: 'confirm', sessionId: sid });
  if (open && /^(nahi|nahin|no|n|cancel|mat karo|rehne do)$/i.test(text)) return confirm(ctx, { pendingActionId: open.id!, action: 'cancel', sessionId: sid });

  remember(session, 'user', text);
  const r = await extract(ctx, text, session.history.map((h: any) => ({ role: h.role, text: h.text })));
  let reply: AssistantReply;
  const tool = r.intent ? toolByName.get(r.intent) : undefined;
  if (!tool || r.confidence < MIN_CONFIDENCE) {
    reply = {
      sessionId: sid,
      kind: 'answer',
      intent: null,
      text:
        r.reply ??
        L(ctx.language, 'Sorry, I did not understand. Try "Ramesh half day today" or ask "what can you do?"', 'समझ नहीं आया। ऐसे बोलिए: "Ramesh ko aaj half day laga do", या पूछिए "Kya kya kar sakte ho?"'),
    };
  } else if (!toolAllowed(ctx, tool)) {
    reply = { sessionId: sid, kind: 'error', intent: tool.name, text: L(ctx.language, 'You cannot do this from your account.', 'आपके अकाउंट से यह नहीं हो सकता।') };
  } else if (tool.feature && !plan.features.includes(tool.feature)) {
    reply = { sessionId: sid, kind: 'error', intent: tool.name, text: L(ctx.language, `This needs a higher plan (${tool.feature}).`, `इसके लिए बड़ा प्लान चाहिए (${tool.feature})।`) };
  } else {
    const company = await Company.findById(ctx.companyId).lean();
    const today = todayIn(company!.timezone);
    const parsed = tool.schema.safeParse(r.args ?? {});
    if (!parsed.success) {
      const missing = parsed.error.issues.map((i) => i.path.join('.')).filter(Boolean);
      reply = { sessionId: sid, kind: 'answer', intent: tool.name, text: missingText(ctx.language, tool.name, missing) };
    } else {
      const args: any = tool.normalize ? tool.normalize(parsed.data, ctx, today) : parsed.data;
      try {
        reply = await proceed(ctx, session, tool, args, text);
      } catch (e: any) {
        if (!(e instanceof AppError)) throw e;
        reply = { sessionId: sid, kind: 'error', intent: tool.name, text: e.message };
      }
    }
  }
  remember(session, 'assistant', reply.text);
  await session.save();
  return reply;
}

function missingText(lang: 'en' | 'hi', intent: string, missing: string[]) {
  const what = missing.map((m) => ({ employeeName: L(lang, 'staff name', 'स्टाफ़ का नाम'), amount: L(lang, 'amount', 'रक़म'), phone: L(lang, 'phone number', 'फ़ोन नंबर'), name: L(lang, 'name', 'नाम'), from: L(lang, 'date', 'तारीख़'), date: L(lang, 'date', 'तारीख़') })[m] ?? m);
  return L(lang, `Please tell me the ${what.join(' and ')}.`, `कृपया ${what.join(' और ')} बताइए।`) + (intent === 'add_employee' ? L(lang, ' e.g. "New staff Pooja 9876543210 12000"', ' जैसे: "Naya banda Pooja 9876543210 12000"') : '');
}

export async function confirm(ctx: Ctx, input: { pendingActionId: string; action: 'confirm' | 'cancel' | 'choose'; optionId?: string; sessionId?: string }): Promise<AssistantReply> {
  const session = await AssistantSession.findOne({ companyId: ctx.companyId, userId: ctx.userId, 'pending.id': input.pendingActionId });
  if (!session) throw new AppError('NOT_FOUND', 'This action has expired. Please say it again.');
  const sid = String(session._id);
  const p: any = session.pending.find((x: any) => x.id === input.pendingActionId);
  if (p.status !== 'open' || p.expiresAt < new Date()) {
    if (p.status === 'open') p.status = 'expired';
    await session.save();
    return { sessionId: sid, kind: 'error', text: L(ctx.language, 'This action has expired. Please say it again.', 'यह अनुरोध पुराना हो गया। दोबारा बोलिए।') };
  }
  const tool = toolByName.get(p.intent)!;
  if (input.action === 'cancel') {
    p.status = 'cancelled';
    remember(session, 'assistant', 'cancelled');
    await session.save();
    return { sessionId: sid, kind: 'cancelled', intent: p.intent, text: L(ctx.language, 'Cancelled. Nothing was saved.', 'ठीक है, कुछ सेव नहीं किया।') };
  }
  if (input.action === 'choose') {
    if (p.stage !== 'choose' || !input.optionId || !p.options.some((o: any) => o.id === input.optionId)) throw new AppError('VALIDATION_ERROR', 'Pick one of the options');
    p.status = 'done';
    await session.save();
    const args = { ...p.args, [p.chooseField]: input.optionId };
    try {
      const reply = await proceed(ctx, session, tool, args, '');
      remember(session, 'assistant', reply.text);
      await session.save();
      return reply;
    } catch (e: any) {
      if (!(e instanceof AppError)) throw e;
      return { sessionId: sid, kind: 'error', intent: p.intent, text: e.message };
    }
  }
  if (p.stage !== 'confirm') throw new AppError('VALIDATION_ERROR', 'Choose an option first');
  p.status = 'done';
  await session.save();
  try {
    const r = await tool.execute({ ...ctx, channel: ctx.channel === 'whatsapp' ? 'whatsapp' : 'assistant' }, p.args, { text: session.history.filter((h: any) => h.role === 'user').pop()?.text ?? '' });
    remember(session, 'assistant', r.text);
    await session.save();
    return { sessionId: sid, kind: 'done', intent: p.intent, text: r.text, data: r.data, attachment: r.attachment };
  } catch (e: any) {
    if (!(e instanceof AppError)) throw e;
    return { sessionId: sid, kind: 'error', intent: p.intent, text: e.message };
  }
}
