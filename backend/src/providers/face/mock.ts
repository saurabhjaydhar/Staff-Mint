import type { FaceCompareResult, FaceProvider } from '../types.js';

/**
 * Deterministic stand-in for development and tests. Identical bytes match;
 * probes containing the ASCII markers `noface`, `twofaces`, `stranger` or
 * `blurry` simulate those outcomes. Never used for real decisions: it throws
 * in production so a missing FACE_PROVIDER cannot approve anyone.
 */
export class MockFaceProvider implements FaceProvider {
  readonly name = 'mock';
  constructor(private readonly production = false) {}

  async compare(reference: Buffer, probe: Buffer): Promise<FaceCompareResult> {
    if (this.production) throw new Error('Face match is not configured (FACE_PROVIDER=mock)');
    const text = probe.toString('latin1');
    // An ID photo (reference) with no face on it.
    if (reference.toString('latin1').includes('noface') && !reference.equals(probe)) return { similarity: null, faces: 1 };
    if (text.includes('noface')) return { similarity: null, faces: 0 };
    if (text.includes('twofaces')) return { similarity: 97, faces: 2 };
    if (text.includes('stranger')) return { similarity: 12, faces: 1 };
    if (text.includes('blurry')) return { similarity: 82, faces: 1 };
    return { similarity: reference.equals(probe) ? 99.9 : 96.5, faces: 1 };
  }
}
