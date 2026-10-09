import { CompareFacesCommand, RekognitionClient } from '@aws-sdk/client-rekognition';
import type { FaceCompareResult, FaceProvider } from '../types.js';

/** AWS Rekognition CompareFaces. Default region ap-south-1 (Mumbai) keeps images in India. */
export class RekognitionFaceProvider implements FaceProvider {
  readonly name = 'rekognition';
  private client: RekognitionClient;

  constructor(cfg: { region: string; accessKeyId: string; secretAccessKey: string }) {
    this.client = new RekognitionClient({ region: cfg.region, credentials: { accessKeyId: cfg.accessKeyId, secretAccessKey: cfg.secretAccessKey } });
  }

  async compare(reference: Buffer, probe: Buffer): Promise<FaceCompareResult> {
    try {
      const out = await this.client.send(
        new CompareFacesCommand({ SourceImage: { Bytes: reference }, TargetImage: { Bytes: probe }, SimilarityThreshold: 0, QualityFilter: 'AUTO' }),
      );
      const matches = out.FaceMatches ?? [];
      const faces = matches.length + (out.UnmatchedFaces?.length ?? 0);
      if (!faces) return { similarity: null, faces: 0 };
      const best = Math.max(0, ...matches.map((m) => m.Similarity ?? 0));
      return { similarity: best, faces };
    } catch (e: any) {
      // Rekognition reports "no face in the image" as a parameter error.
      if (e?.name === 'InvalidParameterException') return { similarity: null, faces: 0 };
      throw e;
    }
  }
}
