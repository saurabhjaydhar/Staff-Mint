# StaffMint

**Staff & salary, sorted from your phone.** *Bolo ya tap karo — hajiri aur salary ho jaayegi.*

An AI-powered staff attendance and payroll product for owner-run businesses with 8–50 staff (shops, clinics, salons, restaurants). One Android app has an Owner mode and an Employee mode. "Mint" is a Hinglish chat and voice assistant that always asks before it writes anything.

Product spec: [`docs/StaffMint-PRD-v1.0.md`](docs/StaffMint-PRD-v1.0.md) · API contract: [`docs/API.md`](docs/API.md) · **Credentials still needed: [`docs/ENV_AND_CREDENTIALS.md`](docs/ENV_AND_CREDENTIALS.md)**

## Repository layout
| Path | What | Stack |
|---|---|---|
| `backend/` | API, background jobs, payroll engine, Mint assistant, provider adapters | Node 22 · Express 5 · TypeScript (ESM) · MongoDB/Mongoose · BullMQ · Zod · Vitest |
| `mobile/` | One Flutter app with Owner and Employee modes (Android first) | Flutter 3.47 · Riverpod · Dio · Hive (offline punches) · go_router |
| `web/` | Minimal dashboard: Excel import, bulk edits, payroll compare, reports, CA access | Next.js 16 · Tailwind 4 · Vitest |
| `docs/` | PRD, API contract, credentials checklist | |
| `deploy/` | Nginx example, Mongo backup script | |

## Quick start (everything mocked, no keys needed)
```bash
# 1. Infra
docker run -d -p 27017:27017 mongo:7 && docker run -d -p 6379:6379 redis:7-alpine

# 2. API  (http://localhost:4000)
cd backend && npm install && npm run seed:demo && npm run dev
#    Demo owner: phone 9999900001, OTP 123456 · demo staff: 9876500001 … 9876500006

# 3. Web  (http://localhost:3000)
cd web && npm install && npm run dev

# 4. Mobile (Android emulator)
cd mobile && flutter pub get && flutter run --dart-define-from-file=config/local.json
```
Or run the whole stack with `docker compose up -d --build` (copy `backend/.env.example` to `backend/.env` first).

## Tests
| Package | Command | Status at handover |
|---|---|---|
| backend | `npm run lint && npm run typecheck && npm test` | 163 tests: golden payroll files, rules engine, Hinglish parser, auth, tenant isolation, attendance, leave, payroll, import, assistant, WhatsApp, billing, reports, provider contracts, scheduler |
| web | `npm run lint && npm test && npm run build` | 64 tests |
| mobile | `flutter analyze && flutter test` | 79 tests, analyze clean |

CI runs all three: `.github/workflows/ci.yml`.

## How the PRD maps to code (MVP F1–F13)
| Feature | Where |
|---|---|
| F1 Signup & setup (OTP, ≤ 5 screens, smart defaults) | `backend/src/modules/{auth,company}` · `mobile/lib/features/{auth,setup}` |
| F2 Staff import (Excel/CSV/pasted text/contacts, auto-mapping, flagged-rows review, undo 30 s / rollback 24 h, history grid) | `backend/src/modules/imports` · `web/app/(app)/import` |
| F3 One app, two modes | `mobile/lib/features/{owner,employee}` |
| F4 Deterministic attendance rules + nightly auto-absent | `backend/src/modules/attendance/rules.ts` · `backend/src/jobs/handlers.ts` |
| F5 Mint assistant (Gemini adapter + Hinglish rule fast path, confirm-before-write, buttons for ambiguity, voice) | `backend/src/modules/assistant` · `mobile/lib/features/assistant` |
| F6 Leave · F7 Advances (udhaar) | `backend/src/modules/{leave,advances}` |
| F8 Payroll (pure engine, snapshots, revisions, immutable payslips, parallel-run compare) | `backend/src/modules/payroll` · golden files in `backend/test/golden/payroll` |
| F9 Employee WhatsApp · §11 WhatsApp strategy | `backend/src/modules/messaging` |
| F10 Reports (PDF/XLSX) · F13 audit log + one-click export | `backend/src/modules/{reports,export,audit}` |
| F11 Web dashboard | `web/` |
| F12 Dynamic billing (plans in DB, Razorpay adapter) | `backend/src/modules/billing` · admin API `/api/v1/admin/*` |
| §16 Pluggable providers | `backend/src/providers/*` (interfaces in `types.ts`, selection in `registry.ts`) |

## Key design rules (from the PRD)
- **Never guess with money.** The LLM only extracts intent and entities. Code calculates, and the owner confirms every write.
- **Money is integer paise.** The payroll engine is pure and deterministic, with its version (`engineVersion`) stored on every run.
- **Tenant isolation** has two layers: `companyId` always comes from the server-side user record, and a Mongoose guard rejects tenant queries that lack it.
- **Swap anything external.** Every vendor sits behind an adapter, and vendor SDKs are lint-restricted to `backend/src/providers/**`.
- **Customer owns the data.** Export is free and still works after cancellation.
