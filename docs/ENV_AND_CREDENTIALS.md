# StaffMint: pending credentials and config checklist

Everything currently runs on **fake keys and mock providers**, so the whole product works end to end in development:
- OTP is always `123456`.
- WhatsApp, push and payments are recorded locally instead of being sent.
- Mint uses the built-in Hinglish rule parser.
- PDFs, reports and files are generated locally.

To go live, send the values below. Each one is a single environment variable (or file) swap; no code changes are needed.

Legend: 🔴 required for launch · 🟡 strongly recommended · ⚪ optional / later

---

## 1. Backend (`backend/.env`; template in `backend/.env.example`)

### Core and security (🔴 generate these yourself; never reuse the dev values)
The server **refuses to start in production** while these still have their dev values.

| Variable | What it is | How to get it |
|---|---|---|
| `NODE_ENV` | `production` | — |
| `PUBLIC_BASE_URL` | Public API URL, e.g. `https://api.staffmint.app` | your domain |
| `WEB_APP_URL`, `CORS_ORIGINS` | Web dashboard URL, e.g. `https://app.staffmint.app` | your domain |
| `MONGODB_URI` | MongoDB Atlas connection string | Atlas → Connect → Drivers (M10+ with backups/PITR recommended) |
| `REDIS_URL` | Redis URL (BullMQ jobs) | Upstash / Redis Cloud / the docker `redis` service |
| `JOBS_DRIVER` | `bullmq` in production (run the `worker` service) | — |
| `JWT_ACCESS_SECRET` | random, ≥ 48 chars | `openssl rand -base64 48` |
| `JWT_REFRESH_SECRET` | random, ≥ 48 chars (different from the access secret) | `openssl rand -base64 48` |
| `FIELD_ENCRYPTION_KEY` | 32-byte key, base64 (field-level encryption) | `openssl rand -base64 32`. **Back it up; data encrypted with it cannot be read without it** |
| `FILE_URL_SECRET` | signs private file links | `openssl rand -base64 32` |
| `ADMIN_API_KEY` | protects `/api/v1/admin/*` (dynamic pricing, flags) | `openssl rand -hex 24` |

### OTP login (🔴)
Set `OTP_PROVIDER=msg91` (India) **or** `twilio`.

| Variable | Notes |
|---|---|
| `MSG91_AUTH_KEY` | MSG91 dashboard → API keys |
| `MSG91_TEMPLATE_ID` | DLT-approved OTP template ID. **DLT registration (entity + header + template) is required for Indian SMS** |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM` | Only if you use Twilio instead |

### WhatsApp (🟡 needed for WhatsApp payslips, alerts and owner commands)
Set `MESSAGING_PROVIDER=meta` (WhatsApp Cloud API) **or** `aisensy` (BSP). Open question #4 in the PRD: which BSP to launch with.

| Variable | Notes |
|---|---|
| `WHATSAPP_META_TOKEN` | Permanent system-user token (Meta Business → System users) |
| `WHATSAPP_META_PHONE_NUMBER_ID` | WhatsApp Manager → phone number ID |
| `WHATSAPP_META_APP_SECRET` | Meta app → Settings → Basic (used to verify webhook signatures) |
| `WHATSAPP_VERIFY_TOKEN` | Any random string. Enter the same value in the Meta webhook config |
| `AISENSY_API_KEY`, `AISENSY_WEBHOOK_SECRET` | Only if you use AiSensy |

Webhook URL to register: `https://<api>/api/v1/webhooks/messaging/meta` (or `/aisensy`).

**Utility templates to get approved** (names must match exactly; `{{n}}` = parameter order):

| Template | Params | Used for |
|---|---|---|
| `otp_code` | 1 code | WhatsApp OTP (authentication category) |
| `daily_digest` | present, total, late, on leave, pending actions | 9:30 AM owner digest |
| `leave_request` | name, dates, days, reason + quick replies Approve / Reject | Owner leave alert |
| `leave_status` | name, dates, status | Employee leave update |
| `payslip_ready` | name, month, net pay + **document header** | Payslip PDF to staff |
| `salary_ready` | month, staff count | Month-end "salary ready" alert |
| `punch_approval` | name, distance | Outside-geofence check-in alert |
| `mint_reply` | text | AiSensy only: carries Mint replies |
| `document_share` | caption + document | AiSensy only: reports |
| `staff_invite` | staff name, business name, staff phone, app link | Invite sent when an owner adds staff (and "Resend invite"). The app link is config `app.downloadUrl` — set the real Play Store URL at launch (`PUT /admin/config`) |

### Push notifications (🟡)
Set `PUSH_PROVIDER=fcm`.

| Variable / file | Notes |
|---|---|
| `FCM_SERVICE_ACCOUNT_BASE64` | Firebase console → Project settings → Service accounts → Generate key, then `base64 -w0 key.json` |
| `mobile/android/app/google-services.json` | **Currently a placeholder.** Replace with the real file (`flutterfire configure` or download from Firebase) |
| `mobile/ios/Runner/GoogleService-Info.plist` | Needed when iOS ships, plus an APNs key uploaded to Firebase |

### Face check (AWS Rekognition) (⚪ optional; off per company by default)
Set `FACE_PROVIDER=rekognition`. Until then the mock provider is used in development, and in production it refuses to decide, so face check simply reports "check failed" and never blocks anyone.

| Variable | Notes |
|---|---|
| `AWS_REGION` | Default `ap-south-1` (Mumbai), so photos are processed in India |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | IAM user with only `rekognition:CompareFaces` |
| AWS AI-services opt-out | Set an AWS Organizations AI services opt-out policy so AWS does not use the photos to train its models |
| `FACE_MATCH_THRESHOLD`, `FACE_UNSURE_THRESHOLD` | Default 90 / 75. Tune after the pilot |

Cost is about $0.001 per comparison (about ₹0.08 per check-in). The feature is in the Growth and Pro plans (`face_match`). For an existing database, add `face_match` to those plans with `PUT /api/v1/admin/plans/:code`.

**Before turning it on for customers:** have a lawyer review `docs/legal/FACE_CHECK_PRIVACY.md` and the in-app consent text.

**iOS (when it ships):** ML Kit needs iOS 15.5+ (already set in the Xcode project) and the Podfile `platform :ios, '15.5'` plus excluding `armv7`, as the google_mlkit_face_detection README describes. Run `pod install` on a Mac.

### Mint AI (Google Gemini) (🟡)
Set `LLM_PROVIDER=gemini` and `SPEECH_PROVIDER=gemini` (voice notes).

| Variable | Notes |
|---|---|
| `GEMINI_API_KEY` | Google AI Studio → Get API key (or Vertex AI) |
| `GEMINI_MODEL` | Default `gemini-3.8-flash` (fast, cheap, handles function calling and audio); change if you prefer another model |
| `ASSISTANT_RULES_FASTPATH` | `true` (default): the free rule parser handles confident phrases, and Gemini is only called for the rest (saves cost) |

### File storage (Cloudflare R2) (🔴 for multi-server or cloud deploys; local disk works on a single VPS)
Set `STORAGE_PROVIDER=s3`.

| Variable | Notes |
|---|---|
| `S3_ENDPOINT` | `https://<account-id>.r2.cloudflarestorage.com` |
| `S3_BUCKET` | Create a **private** bucket, e.g. `staffmint-private` |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | R2 → Manage API tokens (Object Read & Write, scoped to the bucket) |
| `S3_REGION` | `auto` for R2 |

### PDF (🔴 for Hindi payslips)
Set `PDF_PROVIDER=puppeteer` and `CHROME_EXECUTABLE_PATH`. The Docker image already sets both to the bundled Chromium and installs Noto Devanagari fonts.

### Payments (Razorpay) (🔴 to charge customers)
Set `PAYMENT_PROVIDER=razorpay`.

| Variable | Notes |
|---|---|
| `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` | Razorpay Dashboard → API keys (test first, then live) |
| `RAZORPAY_WEBHOOK_SECRET` | Set when adding the webhook `https://<api>/api/v1/webhooks/payments/razorpay`. Events: `subscription.*`, `payment.captured`, `payment.failed` |
| **Razorpay plan IDs** | Create one plan per paid plan × interval in Razorpay, then store them with the admin API: `PUT /api/v1/admin/plans/starter` with `providerPlanIds: { razorpay: { monthly: "plan_xxx", yearly: "plan_yyy" } }` (same for `growth` and `pro`) |

### Email, maps and observability (⚪ / 🟡)
| Variable | Notes |
|---|---|
| `EMAIL_PROVIDER=resend`, `RESEND_API_KEY`, `EMAIL_FROM` | Domain verified in Resend |
| `GEO_PROVIDER=google`, `GOOGLE_MAPS_API_KEY` | Geocoding API (reverse geocodes the shop pin into an address) |
| `SENTRY_DSN` | 🟡 Sentry project DSN (errors) |
| `ANALYTICS_PROVIDER=posthog`, `POSTHOG_API_KEY`, `POSTHOG_HOST` | PostHog project key |
| `SUPPORT_WHATSAPP` | Your support WhatsApp number shown in the app |

---

## 2. Web dashboard (`web/.env`, build-time)
| Variable | Notes |
|---|---|
| `NEXT_PUBLIC_API_BASE_URL` | e.g. `https://api.staffmint.app/api/v1`. Baked in at build time, so pass it as a Docker build arg |

## 3. Mobile app (build-time)
| Item | Notes |
|---|---|
| `--dart-define=API_BASE_URL=https://api.staffmint.app/api/v1` | Default is `http://10.0.2.2:4000/api/v1` (Android emulator) |
| `--dart-define=MAP_TILE_URL=...` | 🟡 Production map tiles (OpenStreetMap public tiles are for dev only); e.g. MapTiler or Stadia key |
| `android/app/google-services.json` | 🔴 Real Firebase file (see Push above) |
| `android/key.properties` + upload keystore `.jks` | 🔴 Play Store signing (`keytool -genkey ...`). Both are gitignored; **back them up** |
| App icon and splash | 🟡 Still the Flutter defaults; send a 1024×1024 logo |
| Play Console account ($25) | 🔴 For release; store listing in Hindi and English |
| iOS (later) | Apple developer account, signing team, APNs key, `GoogleService-Info.plist` |

## 4. Product decisions still open (PRD §28). Current defaults, all editable without a release
| Question | Current default | Where to change |
|---|---|---|
| Salary divisor | `days_in_month` (your choice) | Per company in Settings |
| Mint on Free plan | **Off** (your choice) | `PUT /api/v1/admin/plans/free` features |
| Prices | Free ₹0 (≤5 staff) · Starter ₹499 (≤15) · Growth ₹999 (≤30) · Pro ₹1,799 (≤50, +₹30/extra staff); yearly = 10× | Admin plans API |
| Trial | 14 days of Starter for new signups | `signup.trialPlan` config + plan `trialDays` |
| WhatsApp BSP | Meta Cloud API adapter + AiSensy adapter ready | `MESSAGING_PROVIDER` |
| First vertical | Not encoded anywhere (generic `businessType`) | — |
| Holiday template | India 2026–2027 list in `backend/src/modules/config/defaults.ts` | Verify dates, especially lunar festivals |

## 5. Things I need from you to finish features that depend on real data
1. **SalaryBox and PagarBook export samples** (3–5 real files). Their header templates in `backend/src/modules/imports/mapping.ts` (`TEMPLATES`) are a best guess and must be checked against real exports.
2. **200 real owner phrases** from the pilot, to extend `backend/test/unit.parser.test.ts` toward the ≥ 90% intent accuracy target.
3. **3 real salary sheets** to cross-check the golden payroll tests (launch checklist item).
4. **Domain**: is it staffmint.com, .in or .app? Also the trademark check and Play Store name check.
5. **Legal**: privacy policy, terms, refund policy, and a DPDP Act review. The in-app consent text is a draft.
