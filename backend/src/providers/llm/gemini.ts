import { GoogleGenAI, FunctionCallingConfigMode } from '@google/genai';
import type { LlmExtractInput, LlmExtractResult, LlmProvider } from '../types.js';
import { AppError } from '../../lib/errors.js';

const SYSTEM = (ctx: LlmExtractInput['context']) => `You are "Mint", the assistant inside StaffMint, a staff attendance & salary app for small Indian businesses.
Owners speak Hindi, English or Hinglish (Hindi in Latin script), often casually.
Your ONLY job: pick exactly one tool that matches the user's request and extract its arguments. Never compute money or make up data.
- Today is ${ctx.today} (company timezone). Convert relative dates: aaj=today, kal=yesterday when talking about past events (attendance, absence), kal=tomorrow for future plans (holiday, leave). Output dates as YYYY-MM-DD and months as YYYY-MM.
- Amounts: "5000", "5k", "5 hazaar" → rupees as a number (5000). "1.5 lakh" → 150000.
- Employee names must be copied as spoken; known staff: ${ctx.employeeNames.slice(0, 200).join(', ') || '(none yet)'}.
- Attendance statuses: present, absent, half_day, leave, holiday, week_off. "nahi aaya"=absent, "aadha din/half day"=half_day, "chutti"=leave (for a person) or holiday (for everyone).
- User role: ${ctx.role}.
- If the request is unclear or not supported, do not call a tool; reply with one short clarifying question in the user's language.`;

export class GeminiLlmProvider implements LlmProvider {
  readonly name = 'gemini';
  private ai: GoogleGenAI;
  constructor(private cfg: { apiKey: string; model: string }) {
    this.ai = new GoogleGenAI({ apiKey: cfg.apiKey });
  }
  async extract(input: LlmExtractInput): Promise<LlmExtractResult> {
    const contents = [
      ...(input.context.history ?? []).slice(-6).map((h) => ({ role: h.role === 'assistant' ? 'model' : 'user', parts: [{ text: h.text }] })),
      { role: 'user', parts: [{ text: input.text }] },
    ];
    try {
      const res = await this.ai.models.generateContent({
        model: this.cfg.model,
        contents,
        config: {
          systemInstruction: SYSTEM(input.context),
          temperature: 0,
          tools: [{ functionDeclarations: input.tools.map((t) => ({ name: t.name, description: t.description, parametersJsonSchema: t.parameters })) }],
          toolConfig: { functionCallingConfig: { mode: FunctionCallingConfigMode.AUTO } },
        },
      });
      const call = res.functionCalls?.[0];
      if (call?.name) return { intent: call.name, args: (call.args ?? {}) as Record<string, unknown>, confidence: 0.9, provider: this.name };
      return { intent: null, args: {}, confidence: 0, reply: res.text ?? undefined, provider: this.name };
    } catch (e: any) {
      throw new AppError('PROVIDER_ERROR', `Gemini: ${e?.message ?? 'request failed'}`);
    }
  }
}
