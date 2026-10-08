import { env } from '../config/env.js';
import type {
  AnalyticsProvider,
  EmailProvider,
  GeoProvider,
  LlmProvider,
  MessagingProvider,
  OtpProvider,
  PaymentProvider,
  PdfRenderer,
  PushProvider,
  SpeechProvider,
  StorageProvider,
} from './types.js';
import { MockOtpProvider } from './otp/mock.js';
import { Msg91OtpProvider } from './otp/msg91.js';
import { TwilioOtpProvider } from './otp/twilio.js';
import { MockMessagingProvider } from './messaging/mock.js';
import { MetaCloudMessagingProvider } from './messaging/meta.js';
import { AiSensyMessagingProvider } from './messaging/aisensy.js';
import { MockPushProvider } from './push/mock.js';
import { RulesLlmProvider } from './llm/rules.js';
import { MockSpeechProvider } from './speech/mock.js';
import { LocalStorageProvider } from './storage/local.js';
import { SimplePdfRenderer } from './pdf/simple.js';
import { MockPaymentProvider } from './payments/mock.js';
import { RazorpayPaymentProvider } from './payments/razorpay.js';
import { MockEmailProvider } from './email/mock.js';
import { ResendEmailProvider } from './email/resend.js';
import { MockGeoProvider } from './geo/mock.js';
import { GoogleGeoProvider } from './geo/google.js';
import { MockAnalyticsProvider } from './analytics/mock.js';
import { PostHogAnalyticsProvider } from './analytics/posthog.js';

export interface Providers {
  otp: OtpProvider;
  messaging: MessagingProvider;
  push: PushProvider;
  llm: LlmProvider;
  /** Always-available deterministic parser used as fast path / fallback. */
  rules: LlmProvider;
  speech: SpeechProvider;
  storage: StorageProvider;
  pdf: PdfRenderer;
  payments: PaymentProvider;
  email: EmailProvider;
  geo: GeoProvider;
  analytics: AnalyticsProvider;
}

type Factories = { [K in keyof Providers]: Record<string, () => Providers[K] | Promise<Providers[K]>> };

/** Adapter factories keyed by config value. Adding a vendor = one adapter + one line here. */
const factories: Factories = {
  otp: {
    mock: () => new MockOtpProvider(),
    msg91: () => new Msg91OtpProvider({ authKey: env.MSG91_AUTH_KEY, templateId: env.MSG91_TEMPLATE_ID }),
    twilio: () => new TwilioOtpProvider({ accountSid: env.TWILIO_ACCOUNT_SID, authToken: env.TWILIO_AUTH_TOKEN, from: env.TWILIO_FROM }),
  },
  messaging: {
    mock: () => new MockMessagingProvider(),
    meta: () =>
      new MetaCloudMessagingProvider({ token: env.WHATSAPP_META_TOKEN, phoneNumberId: env.WHATSAPP_META_PHONE_NUMBER_ID, appSecret: env.WHATSAPP_META_APP_SECRET, graphVersion: env.WHATSAPP_GRAPH_VERSION }),
    aisensy: () => new AiSensyMessagingProvider({ apiKey: env.AISENSY_API_KEY, webhookSecret: env.AISENSY_WEBHOOK_SECRET }),
  },
  push: {
    mock: () => new MockPushProvider(),
    fcm: async () => new (await import('./push/fcm.js')).FcmPushProvider(env.FCM_SERVICE_ACCOUNT_BASE64),
  },
  llm: {
    rules: () => new RulesLlmProvider(),
    gemini: async () => new (await import('./llm/gemini.js')).GeminiLlmProvider({ apiKey: env.GEMINI_API_KEY, model: env.GEMINI_MODEL }),
  },
  rules: { rules: () => new RulesLlmProvider() },
  speech: {
    mock: () => new MockSpeechProvider(),
    gemini: async () => new (await import('./speech/gemini.js')).GeminiSpeechProvider({ apiKey: env.GEMINI_API_KEY, model: env.GEMINI_MODEL }),
  },
  storage: {
    local: () => new LocalStorageProvider({ dir: env.LOCAL_STORAGE_DIR, publicBaseUrl: env.PUBLIC_BASE_URL, secret: env.FILE_URL_SECRET }),
    s3: async () =>
      new (await import('./storage/s3.js')).S3StorageProvider({
        endpoint: env.S3_ENDPOINT,
        region: env.S3_REGION,
        bucket: env.S3_BUCKET,
        accessKeyId: env.S3_ACCESS_KEY_ID,
        secretAccessKey: env.S3_SECRET_ACCESS_KEY,
      }),
  },
  pdf: {
    simple: () => new SimplePdfRenderer(),
    puppeteer: async () => new (await import('./pdf/puppeteer.js')).PuppeteerPdfRenderer({ executablePath: env.CHROME_EXECUTABLE_PATH }),
  },
  payments: {
    mock: () => new MockPaymentProvider(),
    razorpay: () => new RazorpayPaymentProvider({ keyId: env.RAZORPAY_KEY_ID, keySecret: env.RAZORPAY_KEY_SECRET, webhookSecret: env.RAZORPAY_WEBHOOK_SECRET }),
  },
  email: {
    mock: () => new MockEmailProvider(),
    resend: () => new ResendEmailProvider({ apiKey: env.RESEND_API_KEY, from: env.EMAIL_FROM }),
  },
  geo: {
    mock: () => new MockGeoProvider(),
    google: () => new GoogleGeoProvider(env.GOOGLE_MAPS_API_KEY),
  },
  analytics: {
    mock: () => new MockAnalyticsProvider(),
    posthog: () => new PostHogAnalyticsProvider({ apiKey: env.POSTHOG_API_KEY, host: env.POSTHOG_HOST }),
  },
};

const selected: { [K in keyof Providers]: string } = {
  otp: env.OTP_PROVIDER,
  messaging: env.MESSAGING_PROVIDER,
  push: env.PUSH_PROVIDER,
  llm: env.LLM_PROVIDER,
  rules: 'rules',
  speech: env.SPEECH_PROVIDER,
  storage: env.STORAGE_PROVIDER,
  pdf: env.PDF_PROVIDER,
  payments: env.PAYMENT_PROVIDER,
  email: env.EMAIL_PROVIDER,
  geo: env.GEO_PROVIDER,
  analytics: env.ANALYTICS_PROVIDER,
};

const cache = new Map<string, unknown>();

async function resolve<K extends keyof Providers>(kind: K, name: string): Promise<Providers[K]> {
  const cacheKey = `${kind}:${name}`;
  if (!cache.has(cacheKey)) {
    const f = factories[kind][name];
    if (!f) throw new Error(`Unknown ${kind} provider "${name}"`);
    cache.set(cacheKey, await f());
  }
  return cache.get(cacheKey) as Providers[K];
}

/** Get the configured provider. `override` lets a company/country pick a different adapter (PRD §16 rule 3). */
export function provider<K extends keyof Providers>(kind: K, override?: string | null): Promise<Providers[K]> {
  return resolve(kind, override || selected[kind]);
}

export function providerName(kind: keyof Providers): string {
  return selected[kind];
}

/** Test hook: replace an adapter instance. */
export function setProvider<K extends keyof Providers>(kind: K, instance: Providers[K], name = selected[kind]): void {
  cache.set(`${kind}:${name}`, instance);
}

export function resetProviders(): void {
  cache.clear();
}
