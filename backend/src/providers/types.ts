/**
 * Pluggable service interfaces (PRD §16). Business code depends only on these.
 * Vendor SDKs/HTTP calls live exclusively in the adapter files next to this one.
 */

// ---------- OTP ----------
export interface OtpSendResult {
  providerRef?: string;
  /** Only mock adapters return the code (for dev builds). */
  devCode?: string;
}
export interface OtpProvider {
  readonly name: string;
  /** Deliver `code` to `phone` (E.164). Provider may also verify itself (Twilio Verify) — we always verify our own hash. */
  send(phone: string, code: string, channel: 'sms' | 'whatsapp'): Promise<OtpSendResult>;
}

// ---------- Messaging (WhatsApp) ----------
export interface MessageButton {
  id: string;
  title: string;
}
export interface SendResult {
  providerMsgId: string;
}
export type MessagingEvent =
  | { type: 'message.inbound'; from: string; text?: string; buttonId?: string; audio?: { mediaId: string; mime?: string }; providerMsgId: string; at: Date }
  | { type: 'message.status'; providerMsgId: string; status: 'sent' | 'delivered' | 'read' | 'failed'; error?: string };
export interface MessagingProvider {
  readonly name: string;
  sendTemplate(to: string, template: string, params: string[], opts?: { language?: 'en' | 'hi'; buttons?: MessageButton[]; documentUrl?: string; filename?: string }): Promise<SendResult>;
  sendText(to: string, text: string): Promise<SendResult>;
  sendButtons(to: string, body: string, buttons: MessageButton[]): Promise<SendResult>;
  sendDocument(to: string, url: string, filename: string, caption?: string): Promise<SendResult>;
  verifyWebhook(headers: Record<string, string | string[] | undefined>, rawBody: Buffer): boolean;
  parseWebhook(body: any): MessagingEvent[];
  /** Download inbound media (voice notes). */
  fetchMedia?(mediaId: string): Promise<{ data: Buffer; mime: string }>;
}

// ---------- Push ----------
export interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}
export interface PushProvider {
  readonly name: string;
  send(tokens: string[], msg: PushMessage): Promise<{ successCount: number; invalidTokens: string[] }>;
}

// ---------- LLM ----------
export interface LlmTool {
  name: string;
  description: string;
  /** JSON schema for the arguments */
  parameters: Record<string, unknown>;
}
export interface LlmExtractInput {
  text: string;
  tools: LlmTool[];
  context: { today: string; language: 'en' | 'hi'; employeeNames: string[]; shiftNames?: string[]; role: string; history?: { role: string; text: string }[] };
}
export interface LlmExtractResult {
  intent: string | null;
  args: Record<string, unknown>;
  confidence: number;
  /** Free-text reply when the model chose no tool (e.g. a clarifying question). */
  reply?: string;
  provider: string;
}
export interface LlmProvider {
  readonly name: string;
  extract(input: LlmExtractInput): Promise<LlmExtractResult>;
}

// ---------- Speech ----------
export interface SpeechProvider {
  readonly name: string;
  transcribe(audio: Buffer, mime: string, opts?: { languageHint?: string }): Promise<{ text: string; language?: string }>;
}

// ---------- Storage ----------
export interface StorageProvider {
  readonly name: string;
  put(key: string, data: Buffer, contentType: string): Promise<void>;
  get(key: string): Promise<Buffer>;
  delete(key: string): Promise<void>;
  signedUrl(key: string, ttlSec: number, opts?: { filename?: string }): Promise<string>;
}

// ---------- PDF ----------
export interface PdfRenderer {
  readonly name: string;
  render(html: string, opts?: { landscape?: boolean }): Promise<Buffer>;
}

// ---------- Payments ----------
export type PaymentEvent =
  | {
      type: 'subscription.activated' | 'subscription.charged' | 'subscription.pending' | 'subscription.halted' | 'subscription.cancelled' | 'subscription.completed';
      eventId: string;
      providerSubId: string;
      currentPeriodEnd?: Date;
      /** The money taken with this event, when there was one (kept as a receipt). */
      payment?: PaymentInfo;
      raw: unknown;
    }
  | { type: 'payment.succeeded' | 'payment.failed'; eventId: string; providerSubId?: string; providerPaymentId: string; amountPaise: number; invoiceId?: string | null; raw: unknown };
export interface PaymentInfo {
  id: string;
  amountPaise: number;
  invoiceId?: string | null;
}
export interface CreateSubscriptionInput {
  planCode: string;
  providerPlanId?: string;
  interval: 'monthly' | 'yearly';
  amountPaise: number;
  currency: string;
  customer: { name: string; phone: string; companyId: string };
  trialDays?: number;
}
export interface PaymentProvider {
  readonly name: string;
  createSubscription(input: CreateSubscriptionInput): Promise<{ providerSubId: string; checkoutUrl: string; keyId?: string }>;
  cancelSubscription(providerSubId: string): Promise<void>;
  verifyWebhook(headers: Record<string, string | string[] | undefined>, rawBody: Buffer): boolean;
  parseWebhook(body: any): PaymentEvent[];
  /** Link to the gateway's invoice (with GST) for a payment, when it makes one. */
  invoiceUrl?(invoiceId: string): Promise<string | null>;
  /** Gateways that bill against their own plan objects (Razorpay): make one for this exact price. */
  createPlan?(input: { planCode: string; name: string; interval: 'monthly' | 'yearly'; amountPaise: number; currency: string }): Promise<string>;
}

// ---------- Email ----------
export interface EmailProvider {
  readonly name: string;
  send(to: string, subject: string, html: string, attachments?: { filename: string; content: Buffer }[]): Promise<{ id: string }>;
}

// ---------- Geo ----------
export interface GeoPlace {
  name: string;
  address: string;
  lat: number;
  lng: number;
}

export interface GeoProvider {
  readonly name: string;
  reverseGeocode(lat: number, lng: number, language?: 'en' | 'hi'): Promise<{ address: string | null }>;
  /** Shops, markets and areas matching what the owner typed, nearest to [near] first. */
  search(query: string, opts?: { near?: { lat: number; lng: number }; language?: 'en' | 'hi' }): Promise<GeoPlace[]>;
}

// ---------- Analytics ----------
export interface AnalyticsProvider {
  readonly name: string;
  capture(distinctId: string, event: string, properties?: Record<string, unknown>): void;
}

// ---------- Face match ----------
export interface FaceCompareResult {
  /** 0–100 similarity of the best face in the probe to the reference; null when the probe has no face. */
  similarity: number | null;
  /** Faces found in the probe image. */
  faces: number;
}

// ---------- Background verification ----------
/** What a government record says. `found: false` = no such PAN / account; errors throw. */
export interface VerifyRecord {
  found: boolean;
  nameOnRecord: string | null;
  providerRef: string | null;
  /** What this call cost us, as the provider charges it. */
  costPaise: number;
  /** Extra details worth keeping (encrypted at rest), e.g. Aadhaar date of birth. Never a full Aadhaar number. */
  details?: Record<string, string>;
  /** UAN: jobs on the EPFO record, newest first. */
  employers?: PastEmployer[];
}

export interface PastEmployer {
  name: string;
  /** "2022-04-15" */
  joined: string | null;
  /** null while still working there. */
  left: string | null;
}

export interface VerificationProvider {
  readonly name: string;
  verifyPan(input: { pan: string; name: string }): Promise<VerifyRecord>;
  /** ₹1 test transfer to the account ("penny drop"), returns the name the bank has. */
  verifyBank(input: { accountNumber: string; ifsc: string; name: string; phone?: string }): Promise<VerifyRecord>;
  /** Aadhaar OTP to the mobile linked with Aadhaar. Returns the reference to verify with. */
  aadhaarSendOtp(input: { aadhaar: string }): Promise<{ ref: string }>;
  aadhaarVerifyOtp(input: { ref: string; otp: string }): Promise<VerifyRecord>;
  /** Driving licence: valid, the name on it and till when (date of birth "1995-04-12" is part of the lookup). */
  verifyDl(input: { number: string; dob: string; name: string }): Promise<VerifyRecord>;
  /** Voter ID (EPIC): valid and the name on it. */
  verifyVoter(input: { epic: string; name: string }): Promise<VerifyRecord>;
  /** UAN (EPFO): the name on it and past employers, so job history can be checked. */
  verifyUan(input: { uan: string; name: string; phone?: string }): Promise<VerifyRecord>;
}

export interface FaceProvider {
  readonly name: string;
  /** Compares a check-in selfie (probe) with the employee's enrolled reference photo. */
  compare(reference: Buffer, probe: Buffer): Promise<FaceCompareResult>;
}
