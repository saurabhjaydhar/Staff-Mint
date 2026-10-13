# Plan: Roster, live tracking for field staff, background verification

Status (13 Oct 2026): **The roster is built (rounds 1, 2a and 2b)** (owner day view, change-shift sheet, send with one-tap fixes, staff "My week"; attendance and salary follow the sent roster). Round 2a added "Repeat every week", the whole-week view, alternating weekly offs and the web roster grid; round 2b adds shift swaps, minimum staff per shift, rest and 48-hour checks, the "roster changed" message and Mint roster commands. Background verification round V1a is built: owner "Check now", staff consent as step 0, Aadhaar OTP, PAN and bank ₹1 test, results with accept / ask again, badges, monthly allowance. Round V1b-1 adds staff documents: upload from the app or the website (the owner can upload for staff without the app, with a signed consent slip), encrypted files opened through short-lived links, every opening in History, and expiry reminders 30 days ahead; the website now shows documents check results. Round V1b-2 adds the selfie check (a selfie matched with the photo on their ID; the selfie isn't kept) and "Do it with them": the owner does the steps with staff who have no smartphone, after they agree on paper with a signed slip. Next: V2 (DigiLocker, DL, Voter ID, UAN, report PDF, paid checks). Screenshots: [roster](../screenshots/roster/README.md), [documents check](../screenshots/verification/README.md), [staff documents](../screenshots/documents/README.md), [selfie check and "Do it with them"](../screenshots/selfie-and-with-them/README.md), [field staff location](../screenshots/tracking/README.md). Live tracking round T1a is built: the owner marks field staff (Pro), staff agree once, the app shares location while they are checked in (Android foreground service, iOS background updates), points wait on the phone without signal, and owners are told when someone stops updating or turns location off. Round T1b adds the owner's live map (Staff tab → Field staff) and each person's day (route, stops with place names and minutes, km), "My route today" for staff, and check-in from anywhere for field staff. Next: T2 (web map, export, evening summary line, travel allowance). Round 0 mock-ups (step-by-step guides): [docs/mockups/roster-tracking-verification.html](../mockups/roster-tracking-verification.html).

**Mock-up changes the owner approved (13 Oct):**
- **Verification:** the staff consent screen is now **step 0 of the staff steps** (one flow: agree → Aadhaar → PAN → bank), not a separate screen.
- **Tracking:** "a person's day" (route, km, stops) opens as a **pop-up over the live map**, not a separate screen.

**Keep it simple (owner feedback, 13 Oct):** each screen does one thing, and plain words replace jargon: "Send to staff" instead of Publish, "Not sent to staff yet" instead of Draft, "Repeat every week" instead of Rotation. Roster opens on **one day at a time** (tap a person to change their shift), with "Whole week" as a second view. Problems before sending come with **one-tap fixes**.

This document covers three features that SalaryBox has and StaffMint doesn't. Each one is built in rounds, one PR per round.

**Decisions (13 Oct 2026, owner approved the recommendations):**
- **Order:** Roster, then Background verification, then Live tracking.
- **Live tracking:** included in **Pro**; **₹49 per field staff per month** add-on on **Growth**.
- **Verification:** **3 full checks a month on Growth, 10 on Pro**, then **₹149 per staff**.
- **Verification provider:** **Cashfree Secure ID**, with fake keys until the business KYC is done.

| | Roster | Live tracking (field staff) | Background verification |
|---|---|---|---|
| Who it's for | Shops with shifts: pharmacies, restaurants, security, factories, clinics | Sales reps, delivery, service engineers, collection agents | Every owner hiring new staff |
| Needs from you | Approve 2 WhatsApp templates | Play Store declaration, approve 1 WhatsApp template | Verification provider account (KYC), approve 1 WhatsApp template |
| Size | 2 rounds | 2 rounds | 2 rounds |
| Suggested order | **1st** (no outside dependency) | **3rd** (Play Store review takes time, start the paperwork early) | **2nd** (start the provider sign-up now, in parallel) |

---

## Part A: Roster (who works which shift on which day)

### Why
Today each staff member has **one fixed shift** with fixed weekly offs. Real shops rotate morning/evening, give different people different offs, and change the plan week to week ("Raju covers Sunday this week"). Owners do this on paper or in WhatsApp groups. Attendance then marks people late or absent against the wrong shift.

### What SalaryBox does
These details come from SalaryBox's own help centre and marketing pages, as found in search results. We haven't tested them in SalaryBox itself.

| Topic | SalaryBox | StaffMint today |
|---|---|---|
| Shift templates | Shifts set up in Settings and reused | Same (Settings → Shifts: start, end, grace, weekly offs) |
| Assign shifts | Per day, from My Team | One shift per person, every day the same |
| Week offs | Sat + Sun by default; tick days; alternating offs, e.g. 1st and 3rd Saturday | Weekly off days per shift; no alternating offs |
| Rotation | Weekly or monthly rotation, next cycle auto-assigned (advanced plans only) | None |
| Publish | Published roster shows in each employee's app | None |
| Rule checks | Flags max weekly hours, min rest between shifts, missing weekly off | None |
| Swaps | Not found | None |

Sources: [Create and assign shifts](https://salarybox.in/resources/help-center/create-and-assign-employee-shifts/) · [Shift management and roster planning](https://salarybox.in/shift-management-and-roster-planning-for-indian-businesses-in-2026/) · [Shift workers](https://salarybox.in/use-cases-shift-workers/) · [Help centre](https://salarybox.in/resources/help-center/)

### What we'll build

**1. The day's shift decides everything.** There will be one server function, `shiftForDay(employee, date)`, which picks the first of these that applies:
1. A **published roster entry** for that day (a shift, or Off).
2. The person's **rotation pattern**, if they have one.
3. Their **own shift**, then their branch's shift, then the default shift. This is today's behaviour, so nothing changes for owners who never open the roster.

Attendance (late, early, half day, overtime, auto-absent at 11:59 PM), the Today screen, staff home and payroll (week offs) all use this one function. A batch version for a whole month keeps payroll fast. Overnight shifts already work (`rules.ts`), and roster days keep that behaviour.

**2. Alternating week offs** on a shift, e.g. "Saturday off on the 1st and 3rd week". Stored as `weeklyOffWeeks: { 6: [1, 3] }` next to `weeklyOff`.

**3. Owner: weekly roster grid** (Staff tab → Roster, and on the web).
- Rows are staff (filter by branch); columns are Mon–Sun. Each cell shows the shift's short name and colour ("M", "E", "N") or "Off".
- Tap a cell to pick a shift, Off or "Use usual shift". Long-press, then tap other cells to fill the same value.
- Toolbar: **Copy last week**, **Apply rotation**, **Clear week**, and **Publish (7 changes)**.
- Changes stay as a **draft** until published, with a banner: "Draft: staff can't see these yet".
- Under the grid, a count per day and shift ("Sat evening: 2 people") is shown in red when below a minimum the owner sets for that shift.

**4. Rotation patterns.** "Morning → Evening, change every week" or a custom cycle of 1–4 weeks with offs per week. Assign to several staff, each with a different starting week, so the shop stays covered. Each week, the server fills the next week as a draft (the owner reviews and publishes), or publishes it automatically if the owner turns that on.

**5. Checks before publishing.** These are warnings, not blocks; the owner can publish anyway:
- Rostered on a day with approved **leave** or a **holiday**.
- **No weekly off** in 7 days.
- **Less than 8 hours rest** between two shifts (config `roster.minRestHours`).
- **More than 48 hours** in the week (config `roster.maxWeeklyHours`; 48 is the usual Shops & Establishments limit).
- A shift below its **minimum staff**.

**6. Staff: "My week".**
- A home card shows "This week: Mon–Fri Morning 9–6 · Sat Evening 2–10 · Sun Off", with changed days highlighted.
- A full screen shows this week and next.
- When the roster is published or changed, staff get a push notification, plus a WhatsApp message if they don't have the app. Only people whose days changed are told about a change.

**7. Shift swaps (round 2).**
1. A staff member asks to swap a day with a colleague.
2. The colleague accepts.
3. The owner or manager approves.
4. Both rosters update and both people are told.

**8. Mint:** "Raju ko is hafte evening shift do", "Sunday ko kaun aa raha hai?" (round 2).

### Server changes
- `RosterEntry { companyId, employeeId, date 'YYYY-MM-DD', kind: 'shift'|'off', shiftId?, note?, status: 'draft'|'published', publishedAt?, updatedBy }`, unique on `(employeeId, date, status)`. Publishing copies draft rows over published ones.
- `RotationPattern { companyId, name, cycle: [{ days: (shiftId|'off'|null)[7] }], assignments: [{ employeeId, startWeek }], autoPublish }`.
- `Shift`: add `weeklyOffWeeks`, `shortName`, `color`, `minStaff`.
- APIs:
  - `GET /roster?week=2026-10-19&branchId` returns grid and warnings.
  - `PUT /roster/cells` saves draft cells in bulk.
  - `POST /roster/copy-week`, `POST /roster/publish`.
  - `/roster/patterns` CRUD and `POST /roster/patterns/:id/apply`.
  - `GET /me/roster` for staff.
  - Round 2: `/roster/swaps`.
- Job: each Thursday, fill next week from patterns. Publishing sends notices (WhatsApp templates `roster_published`, `roster_changed`).
- Audit: "Roster for 19–25 Oct published (7 changes)", "Raju: Sat changed Morning → Off".
- Owner and managers can edit (managers only for their branches); staff can only read.

### Plans
- **Free:** fixed shifts only, as today.
- **Starter and up:** weekly roster grid, publish, My week, checks.
- **Growth and up:** rotation patterns, swaps, auto-publish. This mirrors SalaryBox putting rotation on advanced plans.

### Rounds
- **R1 (built, 13 Oct):**
  - Server: `RosterEntry` (what the owner is planning, plus a `sent` copy that attendance and salary use). The day's shift and day off come from the sent roster everywhere: late marks, auto-absent, payroll inputs, leave day counts, the month grid, check-in rules and the staff home.
  - Re-checks past days that already have check-ins when a changed roster is sent (for example, late is cleared if the shift moved later).
  - APIs: `GET /roster`, `PUT /roster/cells`, `POST /roster/copy-last-week`, `POST /roster/send`, `GET /roster/mine`. Starter and up; staff can read their own week on every plan.
  - Sending tells only the staff whose days changed: push on the app, WhatsApp (`roster_published`) only for staff without the app.
  - Checks before sending, each with a one-tap fix: "on leave on a working day" → Make it Off; "no day off this week" → Give a day off.
  - App: Roster card at the top of the Staff tab; one day at a time; tap a person → big shift tiles, Day off, Usual shift, "Same shift all week"; Copy last week; Send to staff. Staff home shows "My week" (only when the shop uses the roster) with today highlighted and changed days tagged.
  - Existing plans in the database get `roster` added once by a seed migration (`features.added`); an admin can still remove it afterwards.
- **R2a (built, 13 Oct):**
  - **Repeat every week** (Growth and up): from the week on screen, "Yes, same every week" or "Yes, swap every week" (each person moves to the next shift used that week, in start-time order: Morning → Evening → Morning). Days off stay on the same days; days on the usual shift keep following it.
  - Future weeks fill themselves once each, as not sent, when the owner opens them (up to 8 weeks ahead) and every Thursday from 10 AM for the next week. Thursday then sends it on its own if the owner chose that, or pushes "Next week's roster is ready" to owners. Days the owner already planned are never overwritten. Turning it off removes the unsent days it filled.
  - **Whole-week view** in the app (Day | Week): one letter per shift, "–" for off, leave marked, unsent changes outlined; tap a box to change it, tap a day to open it.
  - **Alternating weekly offs** on a shift ("1st & 3rd Saturday off"), in the app and web shift editors; attendance, salary, leave counting and the roster all follow it.
  - **Web roster grid** (Roster in the sidebar): pick a shift in any box, Copy last week, Send to staff with one-tap fixes, Repeat every week.
  - Also fixed: days with no punches now use the branch's shift when a person has none of their own (as check-in already did).
- **R2b (built, 13 Oct):**
  - **Shift swaps** (Growth and up): staff tap "Swap a day" under My week, pick the day and a colleague with a different shift, and see what each would get. The colleague answers on their home screen; then the owner or a manager approves in Roster (app and web). Approval checks nobody's day changed since they asked, swaps it as sent (attendance and salary follow it) and tells both. Swaps stay inside one branch.
  - **Checks before sending**, as warnings that never block: less than 8 hours' rest between two shifts, more than 48 hours in a week (both only for people with roster days that week, so a shop's usual long hours aren't flagged every week), and a shift below its **minimum staff** (new field on shifts, app and web; the day view shows "Morning 1/2" in red).
  - **"Roster changed" message**: staff who already had that week's roster are told just the changed days (WhatsApp `roster_changed` for staff without the app).
  - **Mint**: "Raju ko is hafte evening shift do" (sets and sends it; a range keeps their days off), "Sunday ko kaun aa raha hai?" (who works which shift that day).

---

## Part B: Live GPS tracking for field staff

### Why
Owners of field teams can't see where staff are during the day, whether client visits happened, or how many km to reimburse. Today we check location **only at punch-in and punch-out** (inside the shop area or not).

### What SalaryBox does
As with roster, these details come from SalaryBox's own pages found in search results, not from testing.
- Live location on a map for the admin (web, Android, iOS).
- **Auto Live Track** starts when the employee punches in, with a pop-up telling them their location is shared. The admin can also send a tracking request, which the employee must allow.
- Alerts when staff turn location off during the shift. Daily travel path to confirm visits.
- History downloadable as CSV.
- A separate Field Force CRM adds trips, distance and a meetings timeline.
- Priced as a **₹100 per user per month add-on**.

Sources: [Monitor employee live location](https://salarybox.in/resources/help-center/monitor-employee-live-location/) · [How to live-track your employees](https://support.salarybox.in/support/solutions/articles/84000372902-how-to-live-track-your-employees-in-salarybox-) · [Field Force CRM](https://salarybox.in/resources/help-center/track-field-staff-with-sb-crm-lite/) · [Operations](https://salarybox.in/operations/) · [Pricing](https://salarybox.in/pricing/)

### What we'll build

**1. Only field staff, only during the shift.**
- The owner turns on **"Field staff: share location during shift"** in the staff profile, or for many staff at once.
- The staff member sees a one-time consent screen in plain words, in Hindi or English: what is shared, when, who sees it, and how long it is kept. They tap "I agree"; the consent is stored with the text version and time.
- Without consent, tracking doesn't start, and the owner sees "Waiting for Raju's consent".
- Tracking **starts at punch-in and stops at punch-out**. It also stops at shift end + 2 hours or 11:59 PM, whichever comes first, so it never runs off-shift.

**2. On the phone.**
- Tracking starts at punch-in **while the app is open**. On Android it then runs as a foreground service with a fixed notification ("StaffMint: sharing location until you check out"); on iPhone, iOS shows its usual location indicator.
- **Correction to what I said earlier:** because tracking starts from the open app, "allow while using the app" location permission is enough on both platforms. We don't need "allow all the time".
- One point **every 2 minutes or every 100 m**, at balanced accuracy, to save battery. Interval and distance are business settings.
- Points are saved on the phone without signal and uploaded in batches (every 5 minutes or 20 points), using the same approach as the offline punch queue.
- The phone also reports location turned off, GPS off, permission removed, fake-location apps and low battery as events.
- If the phone restarts or the app is force-closed, tracking stops. Staff get a reminder ("Open StaffMint to keep sharing location") and the owner sees the gap.

**3. Owner: live map** (Staff tab → Field staff, and on the web).
- A map with each field person's initials at their last point. The colour shows last seen: green under 5 minutes, amber under 15, grey older.
- A list below: "Raju · 3 min ago · near Karol Bagh · 18 km today". Tap someone to open their day.

**4. Owner: a person's day.**
- Map route, punch-in and punch-out pins, and **stops** (stayed more than 10 minutes within 100 m) with the place name and how long.
- The **distance for the day** in km, with GPS jumps and bad-accuracy points ignored.
- A date picker; download as Excel or CSV for one day or a month.
- A daily line in the owner's evening summary: "Raju travelled 42 km, 6 stops".

**5. Alerts** (checked every 5 minutes, sent to the owner's alerts and optionally WhatsApp):
- "Raju's location hasn't updated for 20 minutes": phone off, no signal, or location turned off.
- "Raju turned off location sharing", "Fake location app on Raju's phone".
- These follow the same quiet rules as other alerts: no repeats, daytime only.

**6. Staff see their own route.** Staff can see their own route for today. This is part of being transparent with them.

**7. Later:** km × rate = travel allowance added to salary; client visits with check-in at a client location; a geofence alert when someone leaves an area.

### Server changes
- `TrackingSession { companyId, employeeId, date, startedAt, endedAt?, endReason, lastPingAt, distanceM, stops[], gaps[], consentVersion }`.
- `LocationPing { companyId, employeeId, sessionId, at, lat, lng, accuracyM, speed?, battery?, mock, source }`, with a **TTL index** that deletes points after `tracking.keepDays` (default 90).
- APIs:
  - `POST /tracking/pings` (batch, from staff)
  - `POST /tracking/events`
  - `GET /tracking/live` (owner; latest point for each field staff member)
  - `GET /tracking/day?employeeId&date` (simplified route, stops, distance)
  - `GET /tracking/export?month`
  - `PUT /employees/:id/tracking` (field staff on/off)
  - `POST /me/tracking/consent`
- Distance uses point-to-point distance, skipping points with accuracy worse than 100 m or impossible speeds. Stops are clustered on the server. Place names for stops come from the geo provider (Google), cached so each stop is looked up once.
- Rate-limited, and only the staff member's own phone (device-bound session) can send points.
- Audit: who turned tracking on or off, consent given or withdrawn, and owner exports.

### Phone setup and store review
- Android: `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_LOCATION` permissions, with `foregroundServiceType="location"`, using geolocator's Android foreground notification settings.
- iOS: `UIBackgroundModes: location`, background location updates on, and the location indicator shown.
- **Google Play:** declare the foreground service type "location" with a short video of the flow, plus a prominent disclosure screen. This is the consent screen above. Review can take 1–2 weeks, so start early.
- Maps on Android and iOS cost nothing per view. Only the place-name lookups for stops cost money, a few per person per day. The web map uses OpenStreetMap tiles to avoid Google web map charges.

### Privacy (India's DPDP Act 2023)
- **Consent and purpose:** consent is given once, for one purpose (work during the shift).
- **No tracking off-shift:** tracking never runs outside the shift.
- **Visibility:** staff can see their own data.
- **Withdrawal:** staff can withdraw consent from their profile. Tracking then stops, and the owner is told.
- **Deletion:** points are deleted automatically after 90 days (configurable). Managers see only their own branches.

### Plans
Two options; **you decide**:
- **(a)** Included in **Pro**, and a **₹49 per field staff per month add-on** on Growth. That's half SalaryBox's ₹100.
- **(b)** A ₹49–99 per field staff per month add-on on any paid plan.

### Rounds
- **T1a (built, 13 Oct):** field staff switch on the staff profile (Pro), consent screen (also the Play Store disclosure), sharing only while checked in (stops at check-out, shift end + 2 h, or midnight), Android foreground service and iOS background updates with "while using" permission, offline batches (20 points or 5 minutes), "sharing until you check out · 3.2 km today" on the staff home, stop sharing from the profile, server distance/stops, "not updating" and "location off" alerts, 90-day automatic deletion.
- **T1b (built, 13 Oct):** Staff tab → "Field staff" card → live map with initials (green < 5 min, amber < 15, grey older) and a list ("3 min ago · near Karol Bagh · 18 km"), refreshed every minute; tap → their day with the route, numbered stops (place, from–to, minutes), check-in/out, km and a date switcher; staff get "My route today" in their profile; field staff can check in from anywhere (no shop-area approval; fake location still flagged); points before check-in are ignored.
- **T1 (original scope):** field staff setting, consent, tracking during the shift (Android foreground service, iOS background updates), offline batch upload, live map, day route with distance and stops, the "not updating" and "location off" alerts, tests.
- **T2:** export, web map, evening summary line, fake-location and battery events, Play Store declaration assets (video script and screenshots), travel allowance (km × rate) as an optional salary line.

---

## Part C: Background verification of staff

### Why
Shops hand cash, stock and keys to new people they barely know. Owners collect photocopies of Aadhaar and PAN that sit in a drawer, and nobody checks them. A quick check against government records before day one prevents fake identities and wrong bank accounts.

### What SalaryBox does
As with the other two, these details come from SalaryBox's pages found in search results, not from testing.
- **My Team → Background Verification**: checks PAN, Aadhaar, UAN/PF and other IDs. One page lists **₹350 one-time per staff member**, which may be outdated.
- **ID Verify**: PAN, Voter ID, Driving Licence and UAN against government databases.
- An integration with **Compose1 Verify** starts checks from the onboarding flow.

Sources: [Background verification on SalaryBox](https://salarybox.in/resources/help-center/background-verification-on-salarybox/) · [BGV in BFSI](https://salarybox.in/blog/background-verification-in-bfsi-what-banks-nbfcs-and-insurance-companies-must-check-before-every-hire/) · [BGV companies for SMBs](https://salarybox.in/blog/best-background-verification-companies-in-india-for-startups-smbs-2026/)

### What we already have
Staff profiles already store PAN (encrypted), UAN, ESIC number, bank details (encrypted), emergency contact, and an approved face photo (face check). There are **no document uploads and no verification**.

### What we'll build

**1. Documents for each staff member** (staff profile → Documents).
- Kinds: Aadhaar, PAN, driving licence, voter ID, passport, bank proof (passbook or cancelled cheque), address proof, police verification certificate, experience letter, and other.
- Staff upload from their phone (camera with edge crop, or gallery/PDF). The owner can also upload for staff without smartphones, ticking "Staff agreed" with a photo of the signed consent slip.
- Files are stored **private and encrypted**, opened through short-lived signed links.
- Only the owner and co-owners with permission can see documents; managers and accountants can't. Every view and download is audit-logged ("Rakesh viewed Raju's PAN").
- Expiry dates (driving licence, police certificate) trigger reminders 30 days before.

**2. Checks against government records** (through a verification provider):

| Check | What it confirms | Approx. cost |
|---|---|---|
| **PAN** | Valid PAN, name on record, name match % | ₹1–3 |
| **Aadhaar via DigiLocker** | Staff log in with Aadhaar OTP and share; we get name, date of birth, address and photo. **We keep only the last 4 digits** (UIDAI rule) | ₹10–20 |
| **Bank account (₹1 test transfer)** | Account exists, holder name matches, before the first salary | ₹2–5 |
| **Driving licence / Voter ID** | Valid, name and date of birth match | ₹2–5 each |
| **UAN (EPFO)** | Valid UAN and past employers, so job history can be checked | ₹5–10 |
| **Face match** | Selfie vs ID photo, using our existing face provider | (already paid) |

Costs are rough market figures and depend on the provider.

**3. Plain results and a badge.**
- Each check reads "Verified ✓", "Name doesn't match (Rajesh vs Rajesh Kumar)" with a "This is fine" override and reason, "Not found", or "Couldn't check, try again".
- Staff list and profile show **Verified**, **2 of 4 done** or **Needs attention**.
- A one-page **verification report PDF** can be downloaded or shared.

**4. Two ways to start.**
- **Owner asks:** on the staff profile → "Verify Raju". Raju gets a push notification, or WhatsApp if he has no app, with a link to the steps: consent → DigiLocker → PAN → bank → selfie.
- **During add-staff:** a "Verify documents" step at the end, which can be skipped.

**5. Consent and keeping data (DPDP).**
- Staff see exactly what will be checked and why, and agree. This is required before any check runs.
- Documents and results are deleted **180 days after the person leaves** (config). Staff can see their own documents and results.
- Full Aadhaar numbers are never stored. For uploaded Aadhaar images we ask for the **masked Aadhaar** (UIDAI's download), and the image stays encrypted. Auto-masking can come later.

**6. Police verification.** Instant APIs don't cover it. We track the certificate upload with reminders, and later can order it, along with court-record and address checks, through a BGV company.

### Provider
- A new provider type `verification` with the same pattern as payments and face: a **mock** (for development and tests) plus one real provider.
- Recommended: **Cashfree Secure ID**. It has PAN, bank (₹1 test), DigiLocker, DL, Voter ID and UAN in one account, and the same company can later handle salary payouts.
- Alternatives: **Surepass, Signzy, IDfy, Gridlines**. The interface lets us switch without app changes.
- Env (fake values first, listed in `docs/ENV_AND_CREDENTIALS.md`): `VERIFICATION_PROVIDER=mock|cashfree`, `CASHFREE_VERIFY_CLIENT_ID`, `CASHFREE_VERIFY_CLIENT_SECRET`, `CASHFREE_VERIFY_ENV=sandbox|production`, and the DigiLocker redirect URL.

### Server changes
- `StaffDocument { companyId, employeeId, kind, numberEnc?, numberLast4?, files[{ key, mime, pages }], expiresAt?, status, uploadedBy, createdAt }`.
- `VerificationCheck { companyId, employeeId, kind, status: 'pending'|'verified'|'mismatch'|'not_found'|'failed', nameOnRecord?, matchScore?, details (encrypted), provider, providerRef, costPaise, override?{ by, reason }, at }`.
- `VerificationConsent { employeeId, textVersion, acceptedAt, by: 'staff'|'owner_on_behalf', slipFileKey? }`.
- APIs:
  - `/employees/:id/documents` CRUD and signed upload/download.
  - `POST /employees/:id/verification/request`
  - `GET /employees/:id/verification`
  - `POST /verification/checks/:id/override`
  - `GET /employees/:id/verification/report.pdf`
  - Staff side: `/me/documents`, `/me/verification/consent`, `/me/verification/digilocker/start`, plus the callback.
- Provider calls run as background jobs with retries. Results arrive by webhook or polling.

### Plans and charging
**You decide.** Options:
- **(a)** Growth includes **3 full verifications a month** and Pro **10**. Extra ones cost **₹149 per staff** (a one-time Razorpay payment; this needs Razorpay Orders added to the payments provider).
- **(b)** **₹149 per staff** on every paid plan, with nothing included. That's cheaper than SalaryBox's ₹350.

Document storage itself (upload and view) is on all paid plans. Only the government checks cost money.

### Rounds
- **V1a (built, 13 Oct):** the flow from the approved mock-ups.
  - Owner: staff profile → Documents check → "Check now" → Aadhaar, PAN and bank ticked, with "Included in your plan: 2 of 3 left this month" → "Send to Raju". Results show each check; a name mismatch has "This is fine" (with a reason) or "Ask again"; "not found" has "Ask again". Badges on the staff list (app and web).
  - Staff: a home card → consent in plain words (step 0, nothing runs before it) → Aadhaar with an OTP → PAN → bank ₹1 test (their salary account on file, or another one, which then becomes their salary account) → "All done".
  - Only the last 4 digits of Aadhaar and account numbers are kept; Aadhaar extras (date of birth) are encrypted; owner only. Results are deleted 180 days after someone leaves.
  - Monthly allowance enforced (Growth 3, Pro 10); more checks show the ₹149 price as "coming soon" until paid checks land.
  - Providers: mock and Cashfree (`VERIFICATION_PROVIDER`), Cashfree built from its API reference and to be tried with sandbox keys.
- **V1b-1 (built, 13 Oct):** staff documents.
  - Owner: staff profile → Documents → list with "ending 234F · 2 pages · Added by staff" and the expiry ("Expires 2 Nov 2026" in amber, expired in red). "Add document" for staff without the app needs "they agreed" ticked and, the first time, a photo of the signed consent slip.
  - Staff: Profile → My documents: add (camera or gallery, up to 3 photos), see, and remove what they added.
  - Files are encrypted before storage and open through 5-minute signed links; each opening is in History. Only the last 4 characters of a number are kept. Owners only (not managers or accountants).
  - Driving licence, passport and police certificate: "valid till" date, reminders to owner and staff 30 days before (and when expired), once per date.
  - Deleted 180 days after the person leaves. Feature `documents` on Starter, Growth and Pro.
  - Website: staff list → "Documents" opens the documents check (results, accept, ask again, check now) and the documents (upload incl. PDF, preview, remove).
- **V1b-2 (built, 13 Oct):**
  - Selfie check (`face`): the staff member (or the owner with them) takes a selfie, matched with the photo on their newest photo ID document. No photo ID yet → "Add ID photo" right in the step. Match ≥ `verification.faceMatchMin` (80) is verified; below it the owner sees "Doesn't look like the ID photo" with "This is fine" / "Ask again". The selfie is never stored; the result keeps the score and which ID was used.
  - "Do it with them" on the owner's documents check card for staff without the app: read the consent aloud, tick "they agreed and signed a slip", photograph the slip, then the same steps (the OTP comes to their Aadhaar mobile). The card then shows "Agreed on paper · See slip"; opening the slip is in History. Slips are deleted with the rest 180 days after they leave.
  - Website: the selfie result, "agreed on paper" with the slip, and a note to use the app for "Do it with them".
- **V2:** DigiLocker Aadhaar, DL, Voter ID, UAN history, PDF report, paid checks (Razorpay one-time payment), police certificate reminders, the verification step in add-staff.

---

## Round 0: mock-ups (before any code)

This follows the same approach as the billing mock-up: one HTML page with phone screens in English and Hindi, plus a composite PNG.
- **Roster:** owner grid (draft + warnings), shift picker sheet, rotation setup, staff home card, My week, WhatsApp roster message.
- **Tracking:** consent screen, staff home while sharing, owner live map, person's day (route, stops, km), alerts.
- **Verification:** documents list, upload, owner "Verify Raju", staff steps (consent → DigiLocker → PAN → bank → selfie), results with a mismatch, Verified badge on the staff list, report PDF.

---

## What I need from you

1. **Approve this plan and the order** (Roster → Verification → Tracking), or change it.
2. **Prices:** tracking option (a) or (b); verification option (a) or (b).
3. **Verification provider:** Cashfree (recommended) or another. You'll need to sign up and complete their business KYC; I'll use fake keys until then.
4. **WhatsApp templates** to submit for approval when we reach them: `roster_published`, `roster_changed`, `tracking_alert`, `verification_request`. I'll write the exact text.
5. **Google Play:** when tracking reaches T2, fill in the foreground-service declaration with the video I'll script.

## How each round is checked
- Server: unit and API tests per round. That includes `shiftForDay` with roster, rotation, leave and overnight shifts; payroll with roster days; distance and stop maths on recorded routes; and verification checks with the mock provider (match, mismatch, not found, retry).
- App: widget tests for each new screen in English and Hindi, plus real screenshots of the web build.
- Each round is its own PR, merged when CI is green and there are no conflicts.

## Risks and how we handle them
- **Wrong salary from roster mistakes:** the payroll preview shows "Roster: 3 days changed this month". Approved salary runs stay locked as today, with corrections through Revise.
- **Battery complaints from tracking:** a 2-minute / 100 m default, balanced accuracy, and no tracking off-shift. The owner can lower the frequency.
- **Play Store rejection:** start the declaration early. The consent screen doubles as the required disclosure, and tracking stays foreground-only.
- **Aadhaar rules:** Aadhaar only through DigiLocker, the last 4 digits only, masked images only.
- **Provider cost overruns:** each check is billed to the owner's quota or paid per check, with a per-business monthly cap (config).
