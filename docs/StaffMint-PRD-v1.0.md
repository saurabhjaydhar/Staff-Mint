# StaffMint — Product Requirements Document (A to Z)
**Version:** 1.0 · **Owner:** Saurabh / Scaleroot · **Date:** 9 Oct 2026 · **Status:** Approved for MVP build
**Product:** AI-powered staff attendance & salary app for small businesses (India-first, global-ready)

---

## Contents
1. Executive summary
2. Brand
3. Problem & opportunity
4. Market & competition
5. Target customers & personas
6. Positioning & differentiators
7. Goals, non-goals & success metrics
8. Product principles
9. MVP feature requirements (F1–F13)
10. AI assistant "Mint" — use cases
11. WhatsApp strategy
12. UX — screens & flows
13. Non-functional requirements
14. System architecture
15. Tech stack
16. Pluggable services & dynamic configuration
17. Data model
18. API design
19. Security, privacy & compliance
20. Pricing & monetisation (dynamic)
21. Unit economics (estimates)
22. Go-to-market
23. Build plan — milestones 1–8
24. Timeline & roadmap (12 months)
25. Operating costs
26. Risks & mitigations
27. Launch checklist
28. Open questions
29. Backlog (V2 / V3 / avoid)
30. Glossary

---

## 1. Executive summary
StaffMint is a **mobile-app-first** attendance and payroll product for owner-run businesses with **8–50 staff** (shops, clinics, salons, restaurants, small offices). **One Android app** has an **Owner mode** and an **Employee mode**. Owners run attendance, leave, advances and salary from their phone; staff check in with selfie + GPS.

What makes it different from SalaryBox and others:
1. **"Mint" AI assistant** inside the app — Hinglish chat and voice ("Ramesh ko aaj half day laga do") with confirm-before-write.
2. **Switch in under 10 minutes** — automatic import from Excel/competitor exports and a parallel-run salary comparison.
3. **Fair, simple pricing** — basic payroll and advances included at entry level; no renewal surprises; free data export.
4. **Trust** — audit log for every change, transparent attendance rules, explainable payslips.

**MVP target:** 10 paying pilot shops within ~14 weeks (part-time build), then 50 paying in the following 90 days.

## 2. Brand
| Item | Decision |
|---|---|
| Product name | **StaffMint** (staff + mint = fresh, money) |
| AI assistant | **"Mint"** — in-app chat/voice + optional WhatsApp |
| Tagline (EN) | "Staff & salary, sorted from your phone." |
| Tagline (Hinglish) | "Bolo ya tap karo — hajiri aur salary ho jaayegi." |
| Store title | **StaffMint – Salary & Staff Attendance** |
| Colour | Mint green (#2BB673) primary |
| Markets | India → UAE/Saudi (South Asian–run SMBs) → Southeast Asia |
| Pending checks | staffmint.com / .in / .app · WIPO + IP India (Class 9, 42) · Play/App Store exact search · social handles |

Naming note: Pay/Salary/Staff + common-word names (PayWise, SalaryBook, Staffly, PayZen) are taken or generic; "Zen" is crowded in HR (ZenHR in the Gulf). "Mint" has staffing-agency uses (Mint People, Mint Staffing) but no payroll-app conflict was found.

## 3. Problem & opportunity
**Problem**
- The owner is HR, accountant and supervisor at once, managing everything from a phone between customers.
- Paper registers / Excel / WhatsApp groups cause salary disputes, proxy attendance, lost advance records and hours of month-end work.
- Existing apps are either free-but-basic registers (OkStaff, Pagarkhata, PagarBook) or feature-heavy and gated (SalaryBox puts payroll behind its higher tier; Keka/greytHR are built for larger companies).

**Evidence from SalaryBox reviews (sample)**
- Renewal price jumps and minimum-staff rules; lost access to old data.
- Login/sign-out bugs; location mismatches; "punch-in only = full day" logic complaints.
- Inconsistent support.

**Opportunity:** owners with 8–50 staff are over-served on features and under-served on simplicity, fairness and AI help.

## 4. Market & competition
| Competitor | Type | Strength | Weakness we exploit |
|---|---|---|---|
| **SalaryBox** | Paid mobile-first | Full features, selfie/GPS, big install base | Base fee + per-user cost hurts small shops; payroll gated; renewal complaints; no owner AI assistant |
| OkStaff / Pagarkhata / PagarBook | Free/freemium registers | Free, simple | Basic; limited verification; no AI |
| Keka / greytHR / Zoho People | Mid-market HRMS | Deep HR + compliance | Overbuilt and expensive for 8–50 staff |
| Autowhat / uKnowva / Pocket HRMS | WhatsApp HR bots/add-ons | WhatsApp-native | Employee-side bots; not an owner command layer |

**SalaryBox reference pricing (from its pricing page, Oct 2026 snapshot):** Starter ≈ ₹1,500/mo + ₹30/user; Business ≈ ₹75/user + base fee; live GPS add-on ₹100/user. At 10 staff on payroll this is several hundred ₹ per employee per month.

## 5. Target customers & personas
**Ideal customer profile (first niche)**
- Owner-run business, **8–30 staff** (MVP), up to 50 (V2), 1–3 locations.
- Monthly salary or daily wage; advances common; mostly below or just crossing PF thresholds.
- Owner uses an Android phone and WhatsApp all day; Hindi/Hinglish preferred.
- Start with **one vertical in one city** (pharmacy, clinic, salon or restaurant — decision pending).

| Persona | Description | Main jobs |
|---|---|---|
| **Owner (primary)** | Runs the business, low patience for software | Know who's present, approve leave, record advances, pay correct salary |
| **Employee** | Android phone, Hindi preferred, may be low-literacy | Check in/out, request leave, see salary/payslip |
| **Manager (optional)** | Branch supervisor | Fix attendance, approve leave for branch |
| **CA/Accountant (V2)** | Handles owner's books | Pull salary reports |

## 6. Positioning & differentiators
**Positioning:** "The easiest way for a small business owner to run staff attendance and salary from their phone — just tap or say it."

| Differentiator | Why it matters | Copyable? |
|---|---|---|
| Mint AI assistant (Hinglish, voice, confirm-before-write) | Owners don't need to learn screens | Medium — move fast |
| <10-min switching (importer + parallel run) | Removes the #1 fear of switching | Medium |
| Fair pricing, no surprises, free export | Direct answer to competitor complaints | Easy to copy, hard for incumbents to adopt |
| Explainable salary for employees | Fewer disputes | Medium |
| Audit log at entry tier | Trust | Easy |

## 7. Goals, non-goals & success metrics
**MVP goals**
1. First staff attendance live in **< 10 min** from signup.
2. Owner's daily check in **< 30 seconds**; ≥ **40%** of owners use Mint weekly.
3. Month-end salary run in **< 5 min** with zero manual calculation.
4. Switching needs **no manual typing**.

**Non-goals (MVP)**
PF/ESI/PT/TDS filing, biometric devices, live GPS tracking, performance/OKRs, recruitment, payouts/lending, iOS app, custom report builder, open-ended chatbot.

**Success metrics (first 90 days after launch)**
| Metric | Target |
|---|---|
| Paying companies | 10 pilot → 50 |
| Activation (≥ 3 staff checked in within 48h) | ≥ 70% of signups |
| Week-4 owner retention | ≥ 60% |
| Payroll runs / active companies | ≥ 80% monthly |
| Escalated salary disputes | < 5% of payslips |
| Monthly logo churn | < 5% |

## 8. Product principles
1. **Phone first.** Everything daily works in the app; web is optional.
2. **Defaults over settings.** Ask only what's necessary; smart defaults for the rest.
3. **Never guess with money.** AI suggests, code calculates, owner confirms.
4. **Explain everything.** Every salary number has a reason a non-accountant can read.
5. **Customer owns the data.** Free export, always.
6. **Swap anything external.** Every vendor sits behind an adapter.

## 9. MVP feature requirements (F1–F13)

### F1. Signup & company setup
- Owner signs up with phone OTP (WhatsApp or SMS).
- Asks only: business name, business type, shop location (map pin), opening time, weekly off.
- Smart defaults: grace 15 min, half-day < 4 hrs worked, 1 shift, India holiday template.

**Acceptance:** setup completes in ≤ 5 screens; owner can change every default later in Settings.

### F2. Staff import (switching)
| Source | MVP? |
|---|---|
| Excel/CSV upload (web + forward to WhatsApp) | ✅ |
| Competitor export templates (SalaryBox, PagarBook — needs sample files) | ✅ |
| Pasted text on WhatsApp | ✅ |
| Phone contacts picker | ✅ |
| Photo of register / voice note | V2 |

- Auto column mapping: template match → Hindi/English synonym list → value sniffing → LLM fallback.
- Auto-clean phones, salary formats ("12k", "₹12,000/-"), dates (DD/MM default).
- Review screen shows only flagged rows; inline fix; column remap applies to all rows.
- Optional history import: last 1–3 months attendance grid (P/A/HD/L/WO/H codes), advance balances, leave balances, last salary.
- Undo within 30s; full rollback within 24h; dedupe by phone; audit logged.

**Acceptance:** a 30-row Excel with non-standard headers imports with ≤ 3 owner corrections; no existing data overwritten without confirmation.

### F3. Mobile app — one app, two modes (Flutter, Android first)
**App model:** single app; role decided at login (Owner / Manager / Employee). Mirrors SalaryBox's mobile-first approach so owners never need a computer.

**F3a. Owner mode (primary admin surface)**
| Tab | Contents |
|---|---|
| Home | Today: present / late / absent / on leave counts; "Needs action" (leave requests, corrections); quick actions (Mark attendance, Add advance, Add staff) |
| Staff | List + search; add (manual, contacts, import); profile: salary, shift, advances, documents (V2) |
| Attendance | Day view with tap-to-edit status; month grid; selfie + location on tap |
| Salary | Month selector → preview → approve → send payslips (WhatsApp/app); advances list |
| More | Leave, Reports (PDF/Excel), Settings (shift, geofence pin, rules, holidays), Billing, Audit log, Export, Help |
| Mint (floating button) | AI chat + voice in Hinglish (see F5) |

**Acceptance:** an owner with zero training can mark attendance, approve leave and run salary on the phone without any web dashboard.

**F3b. Employee mode**
- Login via OTP; device bound to employee.
- Home: one big Check-in / Check-out button, today's status, shift time.
- Check-in captures: selfie, GPS + accuracy, device time, mock-location flag.
- Geofence: one radius per branch (default 100 m); outside radius → blocked with clear message, or "request approval" option (owner setting).
- **Offline:** punches queued locally, synced later; server compares device time vs sync time and flags large gaps.
- Screens: Home, Attendance calendar, Leave, Salary (running estimate + payslips + advance balance), Profile (language: Hindi/English).

**Acceptance:** check-in completes in ≤ 3 taps and ≤ 5 seconds on a low-end Android on 3G; offline punches sync with original timestamp and a flag.

### F4. Attendance rules engine (deterministic)
- Statuses: Present, Absent, Half Day, Leave, Holiday, Week Off.
- Late = check-in after shift start + grace. Early-out flagged.
- Missing check-out → configurable: Half Day (default) / Present / flag for owner.
- Nightly job at 11:59 PM marks no-punch staff Absent (unless leave/holiday/week off).
- Owner/manager override with reason → audit log.
- Rules visible in plain language in Settings ("Agar punch-out nahi kiya to Half Day lagega").

### F5. AI assistant "Mint" — in-app first, WhatsApp second (core differentiator)
**Channels:** (1) In-app chat + voice (primary, free to run, no WhatsApp cost); (2) WhatsApp for owners who prefer it (same brain, same tools).
**Rules:** LLM extracts intent + entities only; all writes go through backend tools; **every write requires confirmation**; ambiguous names → buttons; low confidence → ask, never guess.

| Intent | Example | Type |
|---|---|---|
| Mark attendance | "Ramesh ko aaj half day laga do" | Write + confirm |
| Mark absent/present | "Suresh aaj nahi aaya" | Write + confirm |
| Who's late/absent | "Kaun late aaya?" "Kal kaun absent tha?" | Read |
| Approve/reject leave | Button reply on notification | Write |
| Record advance | "Amit ko 5000 advance diya" | Write + confirm |
| Bonus/deduction | "Raju ko 500 bonus" | Write + confirm |
| Add employee | "Naya banda Pooja 98765xxxxx 12000" | Write + confirm |
| Holiday | "Kal sabki chutti hai" | Write + confirm |
| Salary preview | "Is month salary kitni banegi?" | Read |
| Salary report | "October ka salary report bhejo" | Read (PDF/Excel) |
| Send payslips | "Sab ki payslip bhej do" | Write + preview + confirm |
| Help | "Kya kya kar sakte ho?" | Read |

**Not via chat/WhatsApp (open the app screen instead):** salary structure edits for many staff, deleting staff/data, role changes, billing, bulk edits.

**Automated owner alerts:** push notification first, WhatsApp as optional backup — 9:30 AM daily digest, leave request alerts, month-end "salary ready".

**Acceptance:** ≥ 90% correct intent on a test set of 200 real owner phrases (collected during pilot); 0 writes without confirmation.

### F6. Leave
- 3 types: Paid, Sick, Unpaid. Balances set manually (import or owner entry).
- Employee applies in app → owner gets push notification (and optional WhatsApp) with Approve/Reject → employee notified.
- Holiday list from India template, editable.

### F7. Advances (udhaar)
- Record advance (amount, date, installments or "full next salary").
- Auto-deduct in payroll per schedule; owner can skip a month.
- Employee sees remaining balance in app/WhatsApp.

### F8. Payroll (simple, deterministic)
- Wage types: Monthly, Daily.
- Monthly: salary ÷ days in month (or 30 / 26 — owner setting) × payable days.
- Payable days = present + half-day×0.5 + paid leave + paid holidays + week offs (setting).
- Add: bonus/incentive lines. Subtract: advances, manual deductions.
- Flow: Draft (auto on 1st) → Owner preview (anomalies flagged: big change vs last month, negative net) → Approve → Payslips PDF (Hindi + English) → Send via WhatsApp → Mark Paid.
- Run is snapshotted (inputs + engine version); re-runs reproducible; payslips immutable after sending (corrections = new revision).
- **Parallel-run compare:** owner uploads old app's salary report → line-by-line diff with plain-language reasons.

**Acceptance:** golden-file tests cover all rules; salary for 30 staff computed in < 5 s.

### F9. Employee WhatsApp (companion, limited)
- Main experience is the app; WhatsApp only receives payslip, leave status, reminders (useful for staff who rarely open the app).
- Ask "Meri salary kitni bani?" / "Meri salary kam kyun?" → itemised breakdown.
- Apply leave via chat.

### F10. Reports
- Monthly attendance sheet, salary register, advances, late list → PDF/Excel, on web or via WhatsApp.

### F11. Web dashboard (secondary, minimal)
Only for jobs easier on a big screen: Excel import, bulk edits, report downloads, CA/accountant access. Everything daily must work in the app. Full web parity → V2.

### F12. Billing
- Razorpay subscriptions; **pricing is dynamic**: plans, limits, prices and trial length live in a server-side `plans` config (no app release needed to change them).
- Support multiple currencies/tax settings in the data model from day one (INR now; AED/SAR later), even if only INR is enabled.
- Free data export always available, including after cancellation (30-day window).

### F13. Trust features
- Audit log (who/what/before/after/channel) visible to owner.
- One-click full export (Excel + PDFs).

## 10. AI assistant "Mint" — use cases (ranked)
**Design rule:** the LLM only extracts intent + entities; backend tools execute; every write needs confirmation; ambiguous names → buttons; low confidence → ask.

| # | Use case | Example | Type | Stage |
|---|---|---|---|---|
| 1 | Mark/correct attendance | "Ramesh ko aaj half day laga do" | Write | MVP |
| 2 | Daily digest | 9:30 AM: "15/18 present, 2 late, 1 leave" | Auto | MVP |
| 3 | Who's late/absent | "Kaun late aaya?" "Kal kaun absent tha?" | Read | MVP |
| 4 | Salary preview | "Is month salary kitni banegi?" | Read | MVP |
| 5 | Salary report | "October ka salary report bhejo" | Read | MVP |
| 6 | Send payslips | "Sab ki payslip bhej do" | Write | MVP |
| 7 | Record advance | "Amit ko 5000 advance diya" | Write | MVP |
| 8 | Approve leave | Button on notification | Write | MVP |
| 9 | Add employee | "Naya banda Pooja 98765xxxxx 12000" | Write | MVP |
| 10 | Bonus/deduction | "Raju ko 500 bonus" | Write | MVP |
| 11 | Holiday | "Kal sabki chutti hai" | Write | MVP |
| 12 | Employee salary explanation | "Meri salary kam kyun?" | Read | MVP |
| 13 | Voice input (Hindi/Hinglish) | Voice note → same commands | Input | MVP-lite |
| 14 | Edit salary | "Ramesh ki salary 15000 kar do" (double confirm) | Write | V2 |
| 15 | Overtime | "Raju ne 2 ghante extra kaam kiya" | Write | V2 |
| 16 | Cash planning | "Is mahine kitna cash lagega?" | Read | V2 |
| 17 | Pattern alerts | "Vikas 2 hafte mein 6 baar late" | Auto | V2 |
| 18 | Photo of register → import | Photo → attendance grid | Input | V2 |
| 19 | Exit/F&F | "Ravi ko hata do, last day 15" | Write | V2 |
| 20 | Month comparison | "Pichle mahine se OT zyada kyun?" | Read | V3 |

**Acceptance:** ≥ 90% correct intent on 200 real owner phrases from the pilot; 0 writes without confirmation.

## 11. WhatsApp strategy
WhatsApp is a **companion channel**, not the main interface.

| Use | Channel |
|---|---|
| Owner daily work | App (Mint button) |
| Owner alerts | Push first, WhatsApp optional |
| Employee check-in | App only (selfie + GPS; WhatsApp location is spoofable) |
| Payslips, leave status, reminders to staff | WhatsApp (utility templates) |
| Owner commands via WhatsApp | Optional, same Mint brain (V2 if cost is a concern) |

**Never via chat/WhatsApp:** bulk salary edits, deleting staff/data, role changes, billing, bank details.
**Cost control:** utility templates only; owner-initiated chats; budget ~₹30–40/company/month at 20 staff (verify current Meta rates).

## 12. UX — screens & flows
**Principles:** 3 taps max for daily tasks · large text · Hindi/English toggle · no long setup wizard.

**Owner mode**
| Tab | Contents |
|---|---|
| Home | Present/late/absent/leave counts; "Needs action"; quick actions |
| Staff | List, search, add (manual/contacts/import), profile, advances |
| Attendance | Day view tap-to-edit; month grid; selfie + location on tap |
| Salary | Month → preview (anomalies flagged) → approve → send payslips; advances |
| More | Leave, reports, settings (shift, geofence, rules, holidays), billing, audit log, export, help |
| Mint (floating) | Chat + voice |

**Employee mode:** Home (big Check-in/out button) · Attendance calendar · Leave · Salary (running estimate, payslips, advance balance) · Profile.

**Key flows**
1. Signup → business details → map pin → add staff (import) → invite staff → first check-in.
2. Daily: notification digest → open Home → approve leave → done.
3. Month end: "Salary ready" → preview → fix flags → approve → payslips sent.
4. Switching: import file → review flagged rows → import history → parallel-run month.


## 13. Non-functional requirements
| Area | Requirement |
|---|---|
| Performance | API p95 < 500 ms; app cold start < 3 s on low-end Android |
| Offline | Check-in works fully offline; queue survives app restart |
| Availability | 99.5% monthly |
| Languages | Hindi + English (UI, PDFs, WhatsApp); Devanagari fonts in PDFs; i18n-ready strings for Arabic/regional later |
| Globalisation | Country, currency, timezone and phone format stored per company; no India-only hard-coding outside the payroll rules module |
| Security | Tenant isolation by `companyId` server-side; RBAC; JWT + refresh; rate limiting; signed URLs for files; WhatsApp webhook signature verification |
| Privacy | Location captured only at punch; consent screen on employee first login; selfie retention 90 days default; DPDP Act review before launch |
| Auditability | All writes from any channel logged |
| Cost | Infra + WhatsApp + AI ≤ ₹200 per company/month at 20 staff |

## 14. System architecture
```
Flutter app (Owner + Employee) ─┐
Next.js mini web               ├─► Node.js + Express (TypeScript) ─► MongoDB Atlas
Webhooks (WhatsApp, payments)  ─┘        ├─► Redis + BullMQ (jobs)
                                          ├─► Object storage (R2/S3)
                                          └─► Providers: payments · messaging · otp · push · llm · speech · pdf
```
- **Modular monolith** — modules: auth, staff, attendance, leave, payroll, advances, ai, whatsapp, billing, import, reports.
- **Background jobs:** nightly auto-absent, 9:30 digest, payroll draft (1st), payslip PDFs, WhatsApp sends.
- **No microservices, Kubernetes or GraphQL** at MVP.

## 15. Tech stack
| Layer | Choice |
|---|---|
| Mobile | Flutter (Android first, iOS V2); Hive offline queue; geolocator; camera |
| Web | Next.js (minimal) |
| Backend | Node.js 20 + Express + TypeScript (ESM) |
| Validation | Zod (also used for AI tool schemas and OpenAPI) |
| Database | MongoDB Atlas + Mongoose (money in integer paise) |
| Jobs | Redis + BullMQ |
| Auth | Phone OTP + JWT access/refresh |
| Files | Cloudflare R2 (S3-compatible), signed URLs |
| PDF | Puppeteer + HTML templates (Devanagari fonts) |
| Push | Firebase Cloud Messaging |
| WhatsApp | BSP (AiSensy/Interakt/Gupshup) → Meta Cloud API later |
| AI | LLM with function calling via adapter |
| Payments | Razorpay Subscriptions via adapter |
| Logs/errors | Pino + Sentry |
| Analytics | PostHog |
| Tests | Vitest + golden-file payroll tests |
| Deploy | Docker on VPS + Nginx + GitHub Actions |

## 16. Pluggable services & dynamic configuration
**Rule:** business code talks only to interfaces; adapters are chosen by config. Switching a vendor = write one adapter + change one setting.

| Interface | Default | Alternatives |
|---|---|---|
| PaymentProvider | Razorpay | Cashfree, PhonePe PG, Stripe (Gulf) |
| MessagingProvider | BSP | Meta Cloud API, Gupshup |
| OtpProvider | MSG91 | Firebase Auth, Twilio |
| PushProvider | FCM | OneSignal |
| LlmProvider | Any LLM API | Other models |
| SpeechProvider | Any STT API | Bhashini, Whisper |
| StorageProvider | R2 | S3, GCS |
| PdfRenderer | Puppeteer | External API |
| EmailProvider | Resend/SES | SendGrid |
| GeoProvider | Google Maps | OpenStreetMap |
| PayoutProvider (V2) | RazorpayX | Cashfree Payouts |

**Rules**
1. Adapters translate vendor webhooks into internal events (`payment.succeeded`, `subscription.cancelled`…).
2. Records store `provider` + provider IDs, so old and new providers can coexist.
3. Provider selectable per country/company.
4. Vendor SDKs imported only inside their adapter folder.
5. One shared contract test suite per interface.
6. **Dynamic config in DB:** plans, prices, limits, trial length, attendance rules (grace, half-day), leave types, payroll settings (divisor), feature flags per plan/company.
7. Don't abstract internal modules or the database.

## 17. Data model (MongoDB)
All tenant collections carry `companyId`, `createdAt`, `updatedAt`, `deletedAt?`.

| Collection | Key fields |
|---|---|
| companies | name, ownerUserId, country, currency, timezone, settings{graceMinutes, halfDayHours, monthDivisor, language}, plan |
| users | phone (unique), role (owner/manager/employee/ca), employeeId, deviceIds |
| branches | name, geo point, radiusM, shiftId |
| employees | name, phone, branchId, wageType, ratePaise, shift, status, consent{location} |
| shifts | start, end, graceMinutes, weeklyOff |
| attendance | employeeId, date, punches[{type, clientTime, serverTime, geo, selfieKey, mockFlag, deviceId, source}], status, lateMinutes, overridden — unique(employeeId, date) |
| leaves / leaveBalances / holidays | type, dates, status, decidedBy · balances per year · company holidays |
| salaryStructures | employeeId, effectiveFrom, base, allowances, deductions (versioned) |
| payrollRuns / payslips | month, status, totals, engineVersion · lines[], gross, net, pdfKey, sentAt (immutable after send) |
| advances | amount, date, installments, repaid, status |
| importSessions | source, fileKey, mapping, rows, issues, status, rollbackUntil |
| notifications | channel, template, status, providerMsgId |
| subscriptions | provider, providerSubId, planCode, status, currentPeriodEnd |
| plans / configs / featureFlags | dynamic pricing and rules |
| assistantSessions | pending AI confirmations |
| auditLogs | actorId, channel, action, entity, before, after, at (append-only) |

## 18. API design (v1, JWT bearer, companyId from token)
| Method | Path | Role |
|---|---|---|
| POST | /auth/otp/request · /auth/otp/verify · /auth/refresh | public/any |
| GET/POST/PATCH | /employees(/:id) · POST /employees/import | owner/manager |
| POST | /attendance/check-in · /check-out · /sync | employee |
| GET/PATCH | /attendance · /attendance/:id | scoped |
| POST/PATCH | /leaves · /leaves/:id/decision | scoped |
| GET/POST | /advances | owner |
| POST/GET | /payroll/runs · /payroll/runs/:id/approve | owner |
| GET/POST | /payslips/:id · /payslips/send | owner; employee own |
| GET | /reports/attendance · /reports/salary?format=pdf\|xlsx | owner/ca |
| POST | /assistant/message · /assistant/confirm | owner |
| POST | /webhooks/payments · /webhooks/messaging | provider (signature verified) |
| GET | /audit-logs · /export | owner |
| GET/POST | /billing/plans · /billing/subscribe | owner |

## 19. Security, privacy & compliance
| Area | Requirement |
|---|---|
| Tenant isolation | companyId injected server-side; cross-tenant tests |
| RBAC | owner / manager (branch scope) / employee (own data) / CA (read reports) |
| Anti-tamper | server time authoritative; device-time delta check; mock-location/root flags; device binding; audited overrides |
| Location privacy | capture only at punch; consent screen; retention policy (default 12 months) |
| Files | private bucket; short-lived signed URLs; selfie auto-purge (default 90 days) |
| API | rate limits, OTP throttling, Zod validation, helmet, webhook signatures, JWT rotation |
| Encryption | TLS; encryption at rest; field-level encryption for sensitive fields |
| Backups | daily + point-in-time; monthly restore drill |
| Deletion | export-before-delete; retention exceptions for payroll records |
| Law | India DPDP Act 2023 — notice, consent, purpose limitation; legal review before launch |
| Audit | append-only log for every write, any channel |

## 20. Pricing & monetisation (dynamic)
Prices live in DB config and can change any time. **Starting proposal (to validate with pilots):**

| Plan | Staff | Price | Includes |
|---|---|---|---|
| Free | ≤ 5 | ₹0 | Attendance, leave, daily digest |
| Starter | ≤ 15 | ₹499/mo | + payroll, advances, payslips, Mint (in-app) |
| Growth | ≤ 30 | ₹999/mo | + branches, reports, WhatsApp payslips |
| Pro | ≤ 50 | ₹1,799/mo | + priority support, CA access |
| 50+ | — | + ₹30/extra staff | — |

Annual = 10× monthly. Price-lock for 24 months. Free export always. Cost per company ≈ ₹170–250/month at 20 staff → ~75–80% gross margin.

## 21. Unit economics (estimates — assumptions: ARPA ₹800/mo, 20 staff avg, excludes CAC/salaries/GST)
| Paying companies | MRR | ARR | Gross margin |
|---|---|---|---|
| 100 | ₹80K | ₹9.6L | ~67% |
| 500 | ₹4.0L | ₹48L | ~75% |
| 1,000 | ₹8.0L | ₹96L | ~77% |
| 5,000 | ₹40L | ₹4.8Cr | ~79% |
| 10,000 | ₹80L | ₹9.6Cr | ~80% |

## 22. Go-to-market
| Stage | Tactics |
|---|---|
| First 10 | One vertical + one neighbourhood; walk-in demos on the owner's own staff list; free migration; charge from day one |
| First 100 | CA/accountant partners (recurring share); local IT/POS dealers (bounty); trade associations; referrals (1 month free); Hindi YouTube demos; long-tail Google search |
| First 1,000 | Scale CA programme; city-by-city commission reps; vertical landing pages; app-store review flywheel; annual-plan push |
| Switch campaign | "Kal se shift karo — data hum laayenge": free import, parallel-run month, price-lock certificate |

## 23. Build plan — milestones 1–8
| # | Milestone | Scope | Done when |
|---|---|---|---|
| 0 | Validation | Manual WhatsApp + spreadsheet service for pilot owners | 10 owners paying; 200 real phrases; 3–5 competitor export files |
| 1 | Backend core | Auth, company setup, staff + import, attendance + geofence, jobs, leave, advances, payroll + PDFs, billing | All tests pass; API usable |
| 2 | Flutter Employee mode | OTP login, check-in (selfie/GPS/offline), attendance, leave, salary | Works on low-end Android on 3G |
| 3 | Flutter Owner mode | Home, Staff, Attendance, Salary, More | Owner runs a full day from phone |
| 4 | Mint assistant | LLM adapter, intents, confirm-before-write, voice | ≥ 90% intent accuracy on test set |
| 5 | Notifications + WhatsApp | Push, WhatsApp templates, payslip delivery | Payslips delivered to all pilot staff |
| 6 | Real providers | Razorpay, OTP, storage in production mode | Real payment collected |
| 7 | Minimal web | Excel import, bulk edits, reports, CA access | Import of 30-row file with ≤ 3 fixes |
| 8 | Production | Hosting, backups, monitoring, security review, Play Store release | Live on Play Store; 5–10 pilots active |

## 24. Timeline & roadmap (part-time ~20 h/week)
| Period | Focus | Exit |
|---|---|---|
| Weeks 1–3 | Milestone 0 | 10 paying owners |
| Weeks 4–7 | Milestone 1 | Backend tests green |
| Weeks 8–11 | Milestones 2–5 | Pilot owner phone-only for a full day |
| Weeks 12–14 | Milestones 6–8 | 5–10 pilots live |
| Months 4–6 | Launch in one city; CA pilot; voice | 50 paying; churn < 5% |
| Months 7–9 | PF/ESI/PT, overtime, multi-shift, branches, bank CSV; 2nd vertical | 120 paying |
| Months 10–12 | QR/kiosk, face match, Tally export, regional languages, iOS | 250 paying (~₹24L ARR) |

## 25. Operating costs (estimates)
| Stage | Monthly |
|---|---|
| Pre-launch | ₹6–10K |
| Launch (≤ 100 customers) | ₹10–18K (VPS, Atlas, Redis, R2, OTP, WhatsApp, LLM, tools) |
| One-time | Play Console $25; Apple $99/yr (when iOS ships); trademark filing |

## 26. Risks & mitigations
| Risk | Mitigation |
|---|---|
| Incumbent copies AI assistant | Speed; own a vertical; trust + pricing positioning |
| Payroll errors | Pure engine, golden tests, preview, parallel run, immutable payslips |
| LLM misreads command | Confirm-before-write; buttons for ambiguity; phrase test set |
| WhatsApp cost/policy change | Push first; utility templates; adapter layer |
| GPS spoofing | Mock-location flag, accuracy threshold, selfie, device binding |
| Slow part-time sales | CA partners; referrals; one-city focus |
| Free-tier cost leakage | Free tier capped; no AI/WhatsApp on Free |
| Compliance creep (PF/ESI) | V2 only when pilots need it; CA partnership |
| Privacy / DPDP | Consent, minimisation, retention, legal review |
| Name/trademark conflict | Complete checks before public launch |

## 27. Launch checklist
- [ ] Domain + trademark + store name confirmed
- [ ] Privacy policy, terms, refund policy, consent screens
- [ ] DPDP review done
- [ ] Payroll golden tests verified against 3 real salary sheets
- [ ] Backups + restore drill done
- [ ] Sentry + uptime alerts live
- [ ] WhatsApp templates approved
- [ ] Razorpay live mode + webhook tested
- [ ] Play Store listing (Hindi + English screenshots)
- [ ] Support channel (WhatsApp/in-app) staffed
- [ ] 5–10 pilot customers onboarded

## 28. Open questions
1. First vertical: pharmacy, clinic, salon or restaurant?
2. Default salary divisor: days-in-month, 26 or 30?
3. Free plan: include Mint in-app or not?
4. WhatsApp BSP for launch?
5. When to bring PF/ESI into scope?
6. Confirm StaffMint domain + trademark.

## 29. Backlog
**V2:** photo/voice import · PF/ESI/PT · overtime · multi-shift & branches · QR/kiosk · face match/liveness · full & final · bank CSV · CA portal · regional languages · edit-salary via Mint · iOS app.
**V3:** Tally export · vertical templates · anomaly detection · HR documents · API · analytics dashboard.
**Avoid initially:** biometric hardware · live GPS tracking · performance/OKRs · recruitment · background verification · payouts/lending · multi-currency payroll · custom report builder.

## 30. Glossary
| Term | Meaning |
|---|---|
| Owner mode / Employee mode | Two experiences in the same app, chosen by role at login |
| Mint | StaffMint's AI assistant |
| Paise | ₹1 = 100 paise; all money stored as integers |
| Parallel run | First month: compare our salary with the old app's, line by line |
| Adapter | Small module wrapping one vendor behind a common interface |
| BSP | WhatsApp Business Solution Provider |
| Utility template | WhatsApp message type for transactional updates |
| Geofence | Allowed check-in radius around the business location |
| DPDP | India's Digital Personal Data Protection Act, 2023 |
