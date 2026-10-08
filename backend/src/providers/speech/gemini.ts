import { GoogleGenAI } from '@google/genai';
import type { SpeechProvider } from '../types.js';
import { AppError } from '../../lib/errors.js';

/** Speech-to-text using Gemini's audio understanding (handles Hindi/Hinglish well). */
export class GeminiSpeechProvider implements SpeechProvider {
  readonly name = 'gemini';
  private ai: GoogleGenAI;
  constructor(private cfg: { apiKey: string; model: string }) {
    this.ai = new GoogleGenAI({ apiKey: cfg.apiKey });
  }
  async transcribe(audio: Buffer, mime: string) {
    try {
      const res = await this.ai.models.generateContent({
        model: this.cfg.model,
        contents: [
          {
            role: 'user',
            parts: [
              { inlineData: { mimeType: mime, data: audio.toString('base64') } },
              { text: 'Transcribe this voice note verbatim. If it is Hindi, write it in Hinglish (Latin script). Output only the transcript.' },
            ],
          },
        ],
        config: { temperature: 0 },
      });
      return { text: (res.text ?? '').trim() };
    } catch (e: any) {
      throw new AppError('PROVIDER_ERROR', `Gemini STT: ${e?.message ?? 'failed'}`);
    }
  }
}
