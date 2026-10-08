import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { StorageProvider } from '../types.js';

/** S3-compatible storage (Cloudflare R2 by default). Bucket must be private. */
export class S3StorageProvider implements StorageProvider {
  readonly name = 's3';
  private client: S3Client;
  constructor(private cfg: { endpoint: string; region: string; bucket: string; accessKeyId: string; secretAccessKey: string }) {
    this.client = new S3Client({ endpoint: cfg.endpoint, region: cfg.region, credentials: { accessKeyId: cfg.accessKeyId, secretAccessKey: cfg.secretAccessKey }, forcePathStyle: true });
  }
  async put(key: string, data: Buffer, contentType: string) {
    await this.client.send(new PutObjectCommand({ Bucket: this.cfg.bucket, Key: key, Body: data, ContentType: contentType, ServerSideEncryption: undefined }));
  }
  async get(key: string) {
    const res = await this.client.send(new GetObjectCommand({ Bucket: this.cfg.bucket, Key: key }));
    return Buffer.from(await res.Body!.transformToByteArray());
  }
  async delete(key: string) {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.cfg.bucket, Key: key }));
  }
  async signedUrl(key: string, ttlSec: number, opts?: { filename?: string }) {
    return getSignedUrl(
      this.client,
      new GetObjectCommand({ Bucket: this.cfg.bucket, Key: key, ResponseContentDisposition: opts?.filename ? `attachment; filename="${opts.filename}"` : undefined }),
      { expiresIn: ttlSec },
    );
  }
}
