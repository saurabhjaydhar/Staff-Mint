import 'dotenv/config';
import { z } from 'zod';

/**
 * All configuration comes from environment variables. Every credential has a
 * placeholder default so the app boots in development with mock providers.
 * See docs/ENV_AND_CREDENTIALS.md for the list of real values needed before launch.
 */
const bool = (def: boolean) =>
  z
    .string()
    .optional()
    .transform((v) => (v === undefined || v === '' ? def : ['1', 'true', 'yes', 'on'].includes(v.toLowerCase())));

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(4000),
  PUBLIC_BASE_URL: z.string().default('http://localhost:4000'),
  WEB_APP_URL: z.string().default('http://localhost:3000'),
  CORS_ORIGINS: z.string().default('http://localhost:3000'),
  LOG_LEVEL: z.string().default('info'),

  MONGODB_URI: z.string().default('mongodb://localhost:27017/staffmint'),
  REDIS_URL: z.string().default('redis://localhost:6379'),
  JOBS_DRIVER: z.enum(['bullmq', 'inline', 'off']).default('inline'),

  JWT_ACCESS_SECRET: z.string().default('dev-access-secret-change-me-0000000000000000'),
  JWT_REFRESH_SECRET: z.string().default('dev-refresh-secret-change-me-000000000000000'),
  JWT_ACCESS_TTL: z.string().default('15m'),
  JWT_REFRESH_TTL_DAYS: z.coerce.number().default(60),
  FIELD_ENCRYPTION_KEY: z.string().default('ZGV2LWZpZWxkLWVuY3J5cHRpb24ta2V5LTMyYnl0ZXM='), // base64 of 32 bytes
  FILE_URL_SECRET: z.string().default('dev-file-url-secret'),
  ADMIN_API_KEY: z.string().default('dev-admin-key'),

  // Provider selection (mock = no external calls)
  OTP_PROVIDER: z.enum(['mock', 'msg91', 'twilio']).default('mock'),
  MESSAGING_PROVIDER: z.enum(['mock', 'meta', 'aisensy']).default('mock'),
  PUSH_PROVIDER: z.enum(['mock', 'fcm']).default('mock'),
  LLM_PROVIDER: z.enum(['rules', 'gemini']).default('rules'),
  SPEECH_PROVIDER: z.enum(['mock', 'gemini']).default('mock'),
  STORAGE_PROVIDER: z.enum(['local', 's3']).default('local'),
  PDF_PROVIDER: z.enum(['simple', 'puppeteer']).default('simple'),
  PAYMENT_PROVIDER: z.enum(['mock', 'razorpay']).default('mock'),
  EMAIL_PROVIDER: z.enum(['mock', 'resend']).default('mock'),
  GEO_PROVIDER: z.enum(['mock', 'google']).default('mock'),
  ANALYTICS_PROVIDER: z.enum(['mock', 'posthog']).default('mock'),
  FACE_PROVIDER: z.enum(['mock', 'rekognition']).default('mock'),
  VERIFICATION_PROVIDER: z.enum(['mock', 'cashfree']).default('mock'),

  // OTP
  OTP_MOCK_CODE: z.string().default('123456'),
  OTP_TTL_SEC: z.coerce.number().default(300),
  MSG91_AUTH_KEY: z.string().default('fake-msg91-auth-key'),
  MSG91_TEMPLATE_ID: z.string().default('fake-msg91-template-id'),
  TWILIO_ACCOUNT_SID: z.string().default('ACfakefakefakefakefakefakefakefake'),
  TWILIO_AUTH_TOKEN: z.string().default('fake-twilio-auth-token'),
  TWILIO_FROM: z.string().default('+15005550006'),

  // WhatsApp
  WHATSAPP_META_TOKEN: z.string().default('fake-meta-whatsapp-token'),
  WHATSAPP_META_PHONE_NUMBER_ID: z.string().default('000000000000000'),
  WHATSAPP_META_APP_SECRET: z.string().default('fake-meta-app-secret'),
  WHATSAPP_VERIFY_TOKEN: z.string().default('fake-verify-token'),
  WHATSAPP_GRAPH_VERSION: z.string().default('v21.0'),
  AISENSY_API_KEY: z.string().default('fake-aisensy-api-key'),
  AISENSY_WEBHOOK_SECRET: z.string().default('fake-aisensy-webhook-secret'),

  // Push (FCM) — service account JSON as base64
  FCM_SERVICE_ACCOUNT_BASE64: z.string().default(''),

  // LLM / speech (Google Gemini)
  GEMINI_API_KEY: z.string().default('fake-gemini-api-key'),
  GEMINI_MODEL: z.string().default('gemini-3.8-flash'),
  ASSISTANT_RULES_FASTPATH: bool(true),

  // Storage (Cloudflare R2 / S3)
  LOCAL_STORAGE_DIR: z.string().default('./storage'),
  S3_ENDPOINT: z.string().default('https://fake-account-id.r2.cloudflarestorage.com'),
  S3_REGION: z.string().default('auto'),
  S3_BUCKET: z.string().default('staffmint-private'),
  S3_ACCESS_KEY_ID: z.string().default('fake-r2-access-key-id'),
  S3_SECRET_ACCESS_KEY: z.string().default('fake-r2-secret-access-key'),
  SIGNED_URL_TTL_SEC: z.coerce.number().default(600),

  // PDF
  CHROME_EXECUTABLE_PATH: z.string().default('/usr/bin/chromium'),

  // Payments (Razorpay)
  RAZORPAY_KEY_ID: z.string().default('rzp_test_fakekeyid0000'),
  RAZORPAY_KEY_SECRET: z.string().default('fake-razorpay-key-secret'),
  RAZORPAY_WEBHOOK_SECRET: z.string().default('fake-razorpay-webhook-secret'),

  // Email
  RESEND_API_KEY: z.string().default('re_fake_resend_api_key'),
  EMAIL_FROM: z.string().default('StaffMint <no-reply@staffmint.app>'),

  // Geo
  GOOGLE_MAPS_API_KEY: z.string().default('fake-google-maps-api-key'),

  // Face match (selfie vs enrolled photo). Off per company until the owner turns it on.
  AWS_REGION: z.string().default('ap-south-1'),
  AWS_ACCESS_KEY_ID: z.string().default('fake-aws-access-key-id'),
  AWS_SECRET_ACCESS_KEY: z.string().default('fake-aws-secret-access-key'),
  /** Similarity at or above this is a match. */
  FACE_MATCH_THRESHOLD: z.coerce.number().min(50).max(100).default(90),
  /** Below the match threshold but at or above this is "unsure"; lower is a mismatch. */
  FACE_UNSURE_THRESHOLD: z.coerce.number().min(0).max(100).default(75),

  // Background verification (Cashfree Secure ID / Verification Suite)
  CASHFREE_VERIFY_CLIENT_ID: z.string().default('CF_FAKE_VERIFY_CLIENT_ID'),
  CASHFREE_VERIFY_CLIENT_SECRET: z.string().default('cf_fake_verify_client_secret'),
  CASHFREE_VERIFY_ENV: z.enum(['sandbox', 'production']).default('sandbox'),

  // Observability
  SENTRY_DSN: z.string().default(''),
  POSTHOG_API_KEY: z.string().default('phc_fake_posthog_key'),
  POSTHOG_HOST: z.string().default('https://us.i.posthog.com'),

  // Product
  SUPPORT_WHATSAPP: z.string().default('+910000000000'),
  MIN_APP_VERSION: z.string().default('0.1.0'),
  DEFAULT_COUNTRY: z.string().default('IN'),
  DEFAULT_TIMEZONE: z.string().default('Asia/Kolkata'),
  DEFAULT_CURRENCY: z.string().default('INR'),
});

export type Env = z.infer<typeof schema>;

export const env: Env = schema.parse(process.env);

export const isProd = env.NODE_ENV === 'production';
export const isTest = env.NODE_ENV === 'test';

/** Refuse to boot in production with placeholder secrets. */
export function assertProductionConfig(): void {
  if (!isProd) return;
  const problems: string[] = [];
  if (env.JWT_ACCESS_SECRET.startsWith('dev-')) problems.push('JWT_ACCESS_SECRET');
  if (env.JWT_REFRESH_SECRET.startsWith('dev-')) problems.push('JWT_REFRESH_SECRET');
  if (env.FILE_URL_SECRET.startsWith('dev-')) problems.push('FILE_URL_SECRET');
  if (env.ADMIN_API_KEY.startsWith('dev-')) problems.push('ADMIN_API_KEY');
  if (env.FIELD_ENCRYPTION_KEY === 'ZGV2LWZpZWxkLWVuY3J5cHRpb24ta2V5LTMyYnl0ZXM=') problems.push('FIELD_ENCRYPTION_KEY');
  if (env.OTP_PROVIDER === 'mock') problems.push('OTP_PROVIDER=mock');
  if (problems.length) {
    throw new Error(`Refusing to start in production with placeholder config: ${problems.join(', ')}`);
  }
}
