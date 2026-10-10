# StaffMint — Product Requirements Document (A to Z)
**Version:** 1.0 · **Owner:** Saurabh / Scaleroot · **Date:** 9 Oct 2026 (updated 10 Oct 2026: F14 accounts) · **Status:** Approved for MVP build
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
9. MVP feature requirements (F1–F14)
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

## 9. MVP feature requirements (F1–F14)

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
**App model:** single app; role decided by the account opened at login (Owner / Manager / Employee). One number can hold several accounts — see F14. Mirrors SalaryBox's mobile-first approach so owners never need a computer.

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

### F14. Accounts — one number, many businesses (never stuck)
**Why:** In small-business India one phone often wears several hats: a pharmacist owns his shop, works evenings at his cousin's clinic, and his CA handles 40 shops. SalaryBox lets an owner manage several companies; StaffMint goes further and lets **any** role hold several businesses on one number. The second goal is just as important: **no one should ever hit a dead end** — a wrong tap, a lost phone, a removed job or an owner who changed numbers must always have a way forward that does not need our support team.

**Model**
- **Person = phone number** (one `user`). **Account = membership** in one business with a role: owner, manager, staff (employee) or accountant (CA).
- One person can hold many memberships; at most one per business. Owner/CA access is never downgraded to staff by an import or "add staff".
- Each **device** is open in exactly one business at a time; two devices of the same person can be in different businesses.
- Every business keeps its own data, plan, rules, staff phone binding and audit log. Switching never mixes data.
- Limits (dynamic config): up to **10 owned businesses** per person (decided 10 Oct 2026); no limit on staff/CA accounts.

**F14a. Choosing and switching** — *Done (PR #10)*
- After OTP, a number with more than one account sees an **account chooser**: business name, type icon, role badge, "Open now" on the last used. One account → straight in.
- Switch any time: mobile **Profile → Your accounts**; web **sidebar → Switch business**. Web lists staff accounts as "use the mobile app".
- Before switching, unsent offline check-ins are sent; if any are left, switching is refused with a clear message (they must land in the right business).
- After a switch every screen reloads for the new business; Mint starts a fresh conversation.

**F14b. Own business from any account** — *Done (PR #10)*
- "Start my own business" (or "Add another business" for owners) from the chooser, Profile or web. Same 4-step setup; the device moves into the new business; other accounts are untouched.
- A number already used elsewhere can be added as staff or accountant; only this business's own owner/CA number is refused.

**F14c. Per-business control** — *Done (PR #10)*
- Staff phone binding, deactivation, reactivation, device reset, manager promotion, import rollback and staff phone change affect **only that business's** account.
- Owner alerts reach every owner/manager of the business; push messages carry the business so a tap can open it (F14e).

**F14d. "Never stuck" scenarios**
| # | Situation | What the person sees | Way forward | Status |
|---|---|---|---|---|
| 1 | Staff logs in before the owner added them | "Ask your employer to add you" with their number | "Check again"; app re-checks on open; **push/SMS "You've been added to Gupta Sweets"** when added | Done (Phase 2) |
| 2 | Staff tapped "I own a business" and created a business by mistake | Owner home of the accidental business | Switch to the staff account; **Close business** (owner) removes the mistake | Done (Phase 2) |
| 3 | Owner tapped "I'm staff" by mistake | Waiting screen | Back → "I own a business" | Done |
| 4 | Staff changed or lost phone | "Linked to another phone" | **"Request device change"** button → owner gets a one-tap approve in Needs-you + push/WhatsApp | Done (Phase 2) |
| 5 | Staff removed from their only business | Lands on "owner or staff?" with no context | **"Your access to Gupta Sweets ended on 3 Oct"** notice, then options: wait for another employer, start own business, log out | Done (Phase 2) |
| 6 | Access to the open business is removed while the app is in use | Logged out completely | **Soft landing:** move to the next account with a notice; log out only when none is left | Done (Phase 2) |
| 7 | Person wants to stop working with a business (staff/manager/CA) | No option | **Leave this business** in Profile → confirm → owner notified; staff record stays with the owner for payroll | Done (Phase 2) |
| 8 | Owner removes an accountant | No list exists | **Settings → Accountants**: list, add, remove | Done (Phase 2) |
| 9 | Owner sold the shop / family member takes over | No option | **Transfer ownership** to another number (OTP confirm by both); old owner can stay as manager or leave | Phase 3 |
| 10 | Two partners run one shop | Only one owner | **Co-owner**: invite a second owner by phone; same rights except Close business and Transfer. **Billing only if the main owner turns on "Can manage billing"** for that co-owner (off by default) | Phase 3 |
| 11 | Owner lost their number | Cannot log in; business locked | Co-owner changes it; else email OTP (if on profile); else support recovery — see *Owner recovery* below | Phase 3 |
| 12 | Old number recycled by the telecom to a new person | New person could see old businesses | **Recycled-number guard:** number unused > 6 months + new device → "Is this you, R*** S***?"; "No" detaches all accounts and alerts the owners | Phase 3 |
| 13 | Notification for business B arrives while the app is in A | Opens A | **Tap opens B** (asks if offline check-ins are pending) | Done (Phase 2) |
| 14 | Staff at two shops opens the app to check in | May be in the wrong shop | **Business chip** on every home header ("Gupta Sweets ▾") for a one-tap switch | Done (Phase 2) |
| 15 | CA with many clients | Long list | **Search + pin** in the chooser once there are more than 6 accounts | Phase 4 |
| 16 | WhatsApp command from a multi-business owner | Uses last opened business | **Mint asks "Which business?"** when unclear; "switch to Verma Traders" command | Phase 4 |
| 17 | Person wants to delete everything (DPDP right to erasure) | No option | **Delete my account**: export first; sole owners must transfer or close each business; payroll records kept as required by law | Phase 3 |
| 18 | Owner wants to stop using StaffMint for one business | No option | **Close business**: export, 30-day restore window, all accounts of that business end and members are told | Done (Phase 2) |
| 19 | Owner adds staff who never installed the app | Staff doesn't know | **Invite** by WhatsApp/SMS with app link and their number when staff is added (resend from staff profile) | Done (Phase 2) |
| 20 | Hit the owned-business limit | Error | Message with support contact; limit is server config | Done |
| 21 | Staff left the shop but needs old payslips (bank loan, ITR) | Cannot log in to that business | **Past payslips** (read-only, own payslips only) for 12 months after exit, if the owner allows it — see *Former staff* below | Phase 3 |

**Decisions (10 Oct 2026)**
- **Owned-business limit:** 10 per person. Decided.
- **Co-owner billing:** a co-owner can manage billing only when the main owner switches on "Can manage billing" for them. Off by default; the main owner can switch it off any time; every billing action is audited. Decided.
- **Former staff payslips** — *recommended, owner to confirm:* a business setting "Ex-staff can see their old payslips", **on by default**. When on, a removed staff member keeps a read-only "Past payslips" view for that business for 12 months after exit — their own payslips only, no attendance, no check-in, no other data. Owner can switch it off; existing payslip PDFs stay downloadable by the owner either way. Why default on: in India ex-staff often need payslips for loans, rent and tax returns, and today they call the owner for them; this saves the owner that work.
- **Owner recovery when the number is lost** — *recommended, owner to confirm before Phase 3*. In order:
  1. **Co-owner** changes the owner's number (instant, audited, old number notified by SMS).
  2. **Email OTP** if the owner added an email to their profile (the app nudges owners to add one).
  3. **Support recovery**, needs **2 of 3**: (a) the business's GSTIN / shop licence / Udyam certificate in the business name, (b) the transaction ID of a past StaffMint payment, (c) a selfie video saying the business name, matched to the owner's profile photo when one exists. Then a **7-day hold**: the old number, managers and the CA are told by SMS/WhatsApp and any of them can stop it. After 7 days the new number becomes owner. Every step is audited. No recovery by phone call alone.

**Build phases**
| Phase | Scope | Est. |
|---|---|---|
| 1 ✅ | Memberships, chooser, switching (app + web), own business from any account, per-business binding/removal (F14a–c) | Done |
| 2 ✅ | Never-stuck basics: rows 1, 2/18, 4, 5, 6, 7, 8, 13, 14, 19 | Done |
| 3 | Shared ownership & recovery: rows 9, 10, 11, 12, 17, 21 | ~2 weeks |
| 4 | Scale: rows 15, 16; one bill for several businesses (group billing); CA portal (V2 backlog) | V2 |

**Acceptance**
- A number with an owner, a staff and a CA account can open each in ≤ 2 taps from anywhere in the app, and data never leaks between them (cross-tenant tests).
- Every row in F14d has a visible way forward on screen; no situation requires calling support except row 11 without email or co-owner.
- Removing a person from one business never affects their other accounts or logs them out of those.
- Every account change (switch, leave, close, transfer, recovery, device change) is in the audit log of the business it touches.

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
5. Many businesses: OTP → account chooser → open one → switch from Profile/sidebar → "Start my own business" from any account (F14).


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
| users | phone (unique), name, language, email?, photoKey — the person; role/companyId mirror the last opened account for old clients |
| memberships | userId, companyId (unique together), role (owner/manager/employee/ca), employeeId, branchIds, deviceIds (staff phone binding per business), status, lastUsedAt — one per business a person can open |
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

## 18. API design (v1, JWT bearer, companyId from the token's account)
| Method | Path | Role |
|---|---|---|
| POST | /auth/otp/request · /auth/otp/verify · /auth/refresh | public/any |
| POST | /auth/switch (open another account on this device) · /company (first or another business) | any signed-in person |
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
| RBAC | owner / manager (branch scope) / employee (own data) / CA (read reports) — per account (membership); one person can hold different roles in different businesses |
| Accounts | access token names the account; removed access stops at the next request; recycled-number guard (F14 row 12); account changes audited per business |
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
7. Accounts (F14): ~~owned-business limit~~ → 10 · ~~co-owner billing~~ → only if the main owner allows · **still open:** confirm the recommended defaults for former-staff payslips (on, 12 months, owner can turn off) and owner recovery proof (2 of 3 + 7-day hold) — see F14 *Decisions*.

## 29. Backlog
**V2:** photo/voice import · PF/ESI/PT · overtime · multi-shift & branches · QR/kiosk · face match/liveness · full & final · bank CSV · CA portal · regional languages · edit-salary via Mint · iOS app.
**V3:** Tally export · vertical templates · anomaly detection · HR documents · API · analytics dashboard.
**Avoid initially:** biometric hardware · live GPS tracking · performance/OKRs · recruitment · background verification · payouts/lending · multi-currency payroll · custom report builder.

## 30. Glossary
| Term | Meaning |
|---|---|
| Owner mode / Employee mode | Two experiences in the same app, chosen by the role of the account opened |
| Account (membership) | One person's access to one business with one role; a number can hold several |
| Account chooser | Screen after login listing every business the number can open |
| Mint | StaffMint's AI assistant |
| Paise | ₹1 = 100 paise; all money stored as integers |
| Parallel run | First month: compare our salary with the old app's, line by line |
| Adapter | Small module wrapping one vendor behind a common interface |
| BSP | WhatsApp Business Solution Provider |
| Utility template | WhatsApp message type for transactional updates |
| Geofence | Allowed check-in radius around the business location |
| DPDP | India's Digital Personal Data Protection Act, 2023 |
