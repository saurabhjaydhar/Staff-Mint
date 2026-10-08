import type { SpeechProvider } from '../types.js';
import { AppError } from '../../lib/errors.js';

/** Dev/test: treats "audio" bytes as UTF-8 text so voice flows can be exercised without an STT vendor. */
export class MockSpeechProvider implements SpeechProvider {
  readonly name = 'mock';
  async transcribe(audio: Buffer, mime: string) {
    if (mime.startsWith('text/')) return { text: audio.toString('utf8') };
    throw new AppError('PROVIDER_ERROR', 'Voice is not configured on this server (SPEECH_PROVIDER=mock). Please type your message.');
  }
}
