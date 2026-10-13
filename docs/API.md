# StaffMint API v1 — contract

Base URL: `{API_BASE}/api/v1` (local dev: `http://localhost:4000/api/v1`; Android emulator: `http://10.0.2.2:4000/api/v1`).

## Conventions
- JSON everywhere. Auth: `Authorization: Bearer <accessToken>`. `companyId` always comes from the token, never from the client.
- Success: `{ "data": ... }` (lists: `{ "data": [...], "meta": {...}? }`).
- Error: `{ "error": { "code": "VALIDATION_ERROR", "message": "human readable", "details"?: any } }` with proper HTTP status.
- Error codes: `VALIDATION_ERROR`(400) `UNAUTHORIZED`(401) `TOKEN_EXPIRED`(401) `FORBIDDEN`(403) `NOT_FOUND`(404) `CONFLICT`(409) `RATE_LIMITED`(429) `PLAN_LIMIT`(402) `FEATURE_NOT_IN_PLAN`(402) `DEVICE_NOT_BOUND`(403) `OUTSIDE_GEOFENCE`(422) `OTP_INVALID`(400) `COMPANY_SETUP_REQUIRED`(409) `INTERNAL`(500).
- **Money is always integer paise** (`ratePaise`, `amountPaise`, …). ₹1 = 100 paise. Clients format for display.
- Dates: `YYYY-MM-DD` (company-local calendar day). Months: `YYYY-MM`. Instants: ISO-8601 UTC. Times of day: `HH:mm` (24h, company timezone).
- Weekdays: `0`=Sunday … `6`=Saturday.
- Optional header `Accept-Language: hi|en` selects language for human-readable server strings (explanations, rules, assistant replies). Default: user's language.
- Roles: `owner`, `manager` (branch-scoped), `employee` (own data only), `ca` (read reports).

## Resource shapes
```ts
User      { id, phone, name, role, companyId: string|null, employeeId: string|null, language: 'en'|'hi' }
Plan      { code, name, priceMonthlyPaise, priceYearlyPaise, currency, staffLimit, extraStaffPricePaise, trialDays, features: string[] }
          // features: attendance, leave, digest, payroll, advances, payslips, assistant, branches, reports, whatsapp_payslips, ca_access, priority_support
Company   { id, name, businessType, country, currency, timezone, location:{lat,lng,address?},
            settings: { graceMinutes, halfDayHours, monthDivisor:'days_in_month'|'30'|'26', missingCheckoutPolicy:'half_day'|'present'|'flag',
                        weekOffsPaid, holidaysPaid, sickLeavePaid, outsideGeofencePolicy:'block'|'request_approval', phoneLockPolicy:'off'|'recommended'|'required', faceMatchPolicy:'off'|'review', language, digestTime:'09:30',
                        roundToRupee, selfieRequired, maxDeviceTimeDriftMin, selfieRetentionDays, whatsappAlerts },
            plan: Plan, subscription: { status:'trialing'|'active'|'past_due'|'cancelled'|'free', planCode, currentPeriodEnd|null },
            trial: Trial|null }
Trial     { planCode, planName, endsAt, daysLeft, active, ended, paidFeatures: string[] }
          // free trial countdown; after the end, ended:true for 30 days (owners see "trial ended"). null when no trial.
Branch    { id, name, location:{lat,lng,address?}, radiusM, shiftId }
Shift     { id, name, start:'09:00', end:'19:00', graceMinutes:number|null, weeklyOff:number[] }
Employee  { id, name, phone, branchId, shiftId, wageType:'monthly'|'daily', ratePaise, designation?, joiningDate?, status:'active'|'inactive', appRole:'employee'|'manager',
            consent:{ location:boolean, at?:string }, hasDevice:boolean, language }
Punch     { id, type:'in'|'out', clientTime /* effective time: server time online, device time for offline sync */, deviceTime, serverTime, geo:{lat,lng,accuracyM}|null, distanceM|null, insideGeofence|null, selfieUrl|null,
            mockLocation, lockCheck:'passed'|'failed'|'unavailable'|null, face:{result:'match'|'unsure'|'mismatch'|'no_face'|'many_faces'|'error', similarity}|null, deviceId, source:'app'|'offline_sync'|'owner'|'assistant'|'import', flags:string[], approval:'not_required'|'pending'|'approved'|'rejected' }
            // flags: late_sync, device_time_drift, mock_location, low_accuracy, outside_geofence, phone_lock_failed, no_phone_lock, face_mismatch, face_unsure, face_no_face, face_many_faces, face_check_failed
Attendance { id, employeeId, date, status:'present'|'absent'|'half_day'|'leave'|'holiday'|'week_off'|null, leaveType?:'paid'|'sick'|'unpaid',
             punches: Punch[], lateMinutes, earlyOutMinutes, workedMinutes, overridden, overrideReason|null, overriddenBy|null /* user id */, flags:string[] }
DayRow    { employee: {id,name,phone,designation,linked,invitedAt}, record: Attendance|null, holidayName|null, shift: {start,end}|null,
            displayStatus:'present'|'late'|'checked_in'|'absent'|'half_day'|'leave'|'holiday'|'week_off'|'not_marked' }
Leave     { id, employeeId, employeeName, type:'paid'|'sick'|'unpaid', from, to, days, halfDay, reason?, status:'pending'|'approved'|'rejected'|'cancelled', decidedAt?, note? }
LeaveBalance { employeeId, year, paid, sick, usedPaid, usedSick }
Advance   { id, employeeId, employeeName, amountPaise, date, mode:'installments'|'full_next', installments, installmentPaise, repaidPaise, balancePaise,
            status:'active'|'closed', skipMonths:string[], note? }
Adjustment { id, employeeId, employeeName, month, type:'bonus'|'deduction', amountPaise, note? }
PayslipLine { code:'basic'|'allowance'|'bonus'|'deduction'|'advance'|'pf'|'esi'|'pt', kind:'earning'|'deduction'|'employer', label, amountPaise, explanation }
Payslip   { id, runId, employeeId, employeeName, month, revision, wageType, ratePaise, payableDays, daysInMonth, divisor,
            summary:{ present, halfDay, absent, paidLeave, unpaidLeave, holidays, weekOffs, unmarked },
            lines: PayslipLine[], grossPaise, deductionsPaise, netPaise, status:'draft'|'final'|'sent', pdfUrl:string|null, sentAt?,
            employerContributions: PayslipLine[],   // employer PF / ESI on top of salary; [] when PF/ESI are off
            employeeInfo: { code, designation, joiningDate, uan, esicNumber, panMasked, bankLast4, upiId, language },
            paidOn: 'YYYY-MM-DD'|null, paymentMethod: 'cash'|'upi'|'bank'|'mixed'|null }
            // Shown to people as "Salary slip" / "सैलरी स्लिप". The PDF is a formal A4 slip: Earnings | Deductions, Gross, Net in words, paid date + method.
Statutory { pfEnabled, pfNumber, basicPercent, pfRatePercent, pfWageCeilingPaise, pfCapAtCeiling,
            esiEnabled, esiNumber, esiEmployeePercent, esiEmployerPercent, esiWageLimitPaise,
            ptEnabled, ptState, ptMonthlyPaise, ptMinGrossPaise }
            // All off by default (small shop slip: Basic + bonus/deductions/advance). With PF on, salary splits into Basic (basicPercent) + "HRA & allowances";
            // PF 12% of Basic (capped at ₹15,000 unless pfCapAtCeiling=false); ESI 0.75% / 3.25% employer, rounded up, only when ESI wages ≤ ₹21,000;
            // PT a fixed monthly amount (optionally only above ptMinGrossPaise). Statutory comes before advances; net never goes below zero.
EmployeeStatutory { employeeCode, uan, esicNumber, panMasked, pfExempt, esiExempt }
PayrollRun { id, month, revision, status:'draft'|'approved'|'paid'|'superseded', engineVersion,
             totals:{ grossPaise, deductionsPaise, netPaise, employees }, anomalies:{ employeeId, employeeName, code, message }[],
             approvedAt?, paidAt?, paidOn?, paymentMethod?, payslips?: Payslip[] }   // anomaly `message` is in the caller's Accept-Language (en | hi)
AssistantReply { sessionId, kind:'answer'|'confirm'|'choose'|'done'|'cancelled'|'error', text,
                 options?: {id,label}[], pendingActionId?, preview?: {title, rows:{label,value}[]}, data?: any, attachment?: {url, filename} }
AuditLog  { id, actorId, actorName, channel:'app'|'web'|'assistant'|'whatsapp'|'system'|'import', action, entity, entityId, before, after, at }
```

## Endpoints

### Auth (public)
| Method | Path | Body | Returns |
|---|---|---|---|
| POST | /auth/otp/request | `{phone, channel?:'sms'\|'whatsapp'}` | `{requestId, expiresInSec, devCode?}` (devCode only when OTP provider is `mock`) |
| POST | /auth/otp/verify | `{phone, code, deviceId, deviceName?}` | `Session {accessToken, refreshToken, user:User, needsCompanySetup:boolean, activeMembershipId:string\|null, memberships:Membership[], needsAccountChoice:boolean}` |
| POST | /auth/refresh | `{refreshToken}` | `{accessToken, refreshToken}` (rotation; old refresh token invalid; stays in the same business) |
| POST | /auth/switch | `{membershipId, deviceId, refreshToken?}` (Bearer) | `Session` opened in that business; the passed refresh token is retired. `DEVICE_NOT_BOUND` for a staff account bound to another phone |
| POST | /auth/logout | `{refreshToken}` | `{ok:true}` |

Phone: E.164 (`+919876543210`) or 10-digit Indian (`9876543210`, normalised server-side). Unknown phone with no staff record → `needsCompanySetup:true`.

`Membership {id, companyId, companyName, businessType, role:'owner'|'manager'|'employee'|'ca', lastUsedAt}`: one phone can own a business, work at another and be the accountant of a third. Login opens the most recently used account this device may use; `needsAccountChoice` is true when there is more than one, and the app offers a chooser. Each device stays in its own business (the access token's `mid` claim and the refresh token both carry the membership), so an owner's tablet and phone can be in different shops.

### Me
| GET | /me | — | `{user, company:Company\|null, employee:Employee\|null, activeMembershipId, memberships:Membership[]}` (user.role/companyId/employeeId are this session's) |
| PATCH | /me | `{name?, language?}` | `User` |
| POST | /me/consent | `{location:true}` | `Employee` |
| GET | /me/profile | — | `Profile {user:{id,name,phone,email,role,language,photoUrl,memberSince,lastLoginAt}, company:{id,name,businessType,planName}\|null, work:{employeeId,designation,joiningDate,wageType,ratePaise,branchName,shift}\|null, bank:BankMasked\|null, emergencyContact:{name,phone,relation}\|null, completeness:{percent, missing:string[]}}` |
| PATCH | /me/profile | `{name?, email?\|null, language?, emergencyContact?\|null}` (emergency contact: staff only; name syncs to the staff record) | `Profile` |
| PUT / DELETE | /me/photo | `{photoBase64}` / — | `Profile` |
| PUT / DELETE | /me/bank | `{holderName, accountNumber?, ifsc?, upiId?}` (staff; account 9–18 digits + IFSC, or UPI) / — | `BankMasked {holderName, accountLast4, ifsc, upiId, updatedAt}`. The owner is notified of every self-change |
| POST | /me/phone/request | `{phone}` (new number) | `{requestId, expiresInSec, devCode?}`; 409 if the number is taken |
| POST | /me/phone/verify | `{phone, code}` | `Profile` (login moves to the new number) |
| POST | /me/logout-all | — | `{ok}`; every refresh token is revoked |
| GET | /me/face | — | `FaceInfo {status:'none'\|'pending'\|'approved', photoUrl, enrolledAt, approvedAt}` |
| POST | /me/face | `{consent:true, photoBase64}` (explicit consent on every enrolment) | 201 `FaceInfo` (status `pending`); 422 `FACE_NOT_CLEAR` `{reason:'no_face'\|'many_faces'}` |
| DELETE | /me/face | — (withdraw consent; photo deleted) | `FaceInfo` |
| POST | /me/push-token | `{token, platform:'android'\|'ios'\|'web'}` | `{ok:true}` |
| GET | /me/salary | `?month` | `{estimate: Payslip-like (status 'draft', not persisted), advanceBalancePaise, payslips: Payslip[]}` (employee) |
| GET | /me/notifications | — | `{id,title,body,data,readAt,createdAt}[]` |
| POST | /me/notifications/read | `{ids}` | `{ok:true}` |

### Company setup & settings (owner)
| POST | /company | `{name, businessType, location:{lat,lng,address?}, openingTime:'09:00', closingTime?:'19:00', weeklyOff:number[], country?:'IN', timezone?:'Asia/Kolkata', currency?:'INR', deviceId?, refreshToken?}` | `{company, accessToken, refreshToken, activeMembershipId, memberships}`. Any signed-in person can create a business (first or another, up to 10 owned); this device moves into it and the passed refresh token is retired |
| GET | /company | — | `Company` |
| PATCH | /company | `{name?, businessType?, location?}` | `Company` |
| PATCH | /company/settings | partial `settings` | `Company` |
| GET | /company/statutory | — (owner, ca) | `Statutory` |
| PATCH | /company/statutory | `{pfEnabled?, pfNumber?, basicPercent? (30–100), pfCapAtCeiling?, esiEnabled?, esiNumber?, ptEnabled?, ptState?, ptMonthlyPaise? (≤ ₹2,500), ptMinGrossPaise?}` (owner; rates are fixed) | `Statutory`; applies from the next salary calculated |
| GET | /company/rules | — | `{rules: {key, text}[]}` plain-language (hi/en by Accept-Language) |
| POST | /company/accountants | `{phone, name}` (Pro plan) | CA access to reports/payroll/export. An existing StaffMint user gets one more account (`ca` membership) |
| GET/POST | /branches | `{name, location, radiusM?}` | `Branch[]` / `Branch` |
| PATCH | /branches/:id | partial | `Branch` |
| GET/POST | /shifts | `{name, start, end, graceMinutes?, weeklyOff, weeklyOffWeeks?, minStaff?}` | `minStaff`: fewest people the shop needs on the shift (roster warning; 0 = none). `weeklyOffWeeks`: alternating offs, weekday → weeks of the month it is off (`{"6": [1, 3]}` = 1st and 3rd Saturday; days 1–7 are week 1). A weekly-off day not listed is off every week. Used by attendance, salary, leave counting and the roster |
| PATCH | /shifts/:id | partial | |
| GET | /holidays | `?year` | `{id,date,name}[]` |
| POST | /holidays | `{date, name}` | |
| DELETE | /holidays/:id | | |
| GET | /geo/search | `?q (2–100 chars)&lat?&lng?&lang?=en\|hi` (any signed-in user; 30/min) | `{name, address, lat, lng}[]` — shops, markets and areas for the location picker, nearest to `lat,lng` first |
| GET | /geo/reverse | `?lat&lng&lang?` (any signed-in user; 30/min) | `{address: string\|null}` — address of the spot under the pin |

### Dashboard (owner/manager)
| GET | /dashboard/today | — | `{date, counts:{total,present,late,absent,onLeave,notMarked,checkedIn}, needsAction:{leaveRequests:(Leave & {balance:{left,after}|null})[], punchApprovals:{attendanceId,employeeName,punch,facePhotoUrl}[], faceEnrollments:{employeeId,employeeName,status,photoUrl,enrolledAt}[], flags:{employeeName,date,flags}[]}, plan:{staffCount, staffLimit}, setup: {steps:{business,staffAdded,staffJoined,salarySet,teamAdded}, done, total:5, staff, joined, notJoined}|null}` (setup: owners only — the Home checklist; `balance`: paid/sick leaves left before and after approving) |

### Employees (owner/manager)
| GET | /employees | `?search&status=active\|inactive\|all&branchId` | `Employee[]` |
| POST | /employees | `{name, phone, wageType?, ratePaise?, branchId?, shiftId?, designation?, joiningDate?}` | `Employee` (402 `PLAN_LIMIT` when over plan staff limit) |
| POST | /employees/bulk | `{employees: [...same as above]}` (contacts picker) | `{created: Employee[], skipped: {phone, reason}[]}` |
| GET | /employees/:id | — | `Employee & {leaveBalance, advanceBalancePaise, bank: BankMasked\|null, emergencyContact, statutory: EmployeeStatutory}` (bank and emergency contact hidden from CA) |
| PATCH | /employees/:id/statutory | `{employeeCode?, uan? (12 digits), esicNumber? (10 or 17 digits), pan?, pfExempt?, esiExempt?}` (owner; `null` clears; PAN stored encrypted, returned masked) | `EmployeeStatutory` |
| PATCH | /employees/:id | partial + `effectiveFrom?` (for rate change → new salary structure version) | `Employee` |
| POST | /employees/:id/deactivate | `{reason?}` | `Employee` |
| POST | /employees/:id/reset-device | — | `Employee` |
| GET | /employees/:id/face | — | `FaceInfo` |
| PUT / DELETE | /employees/:id/bank | `{holderName, accountNumber?, ifsc?, upiId?}` / — (owner) | `BankMasked` |
| POST | /employees/:id/face/approve | — | `FaceInfo`; 409 if nothing is pending |
| DELETE | /employees/:id/face | — (reject / reset; photo deleted, staff asked to enrol again) | `FaceInfo` |
| POST | /employees/:id/reactivate | — | `Employee` |
| POST | /employees/:id/role | `{role:'employee'\|'manager', allBranches?}` (owner) | `Employee`; a manager sees their own branch unless `allBranches`. The person gets a message (`role_manager` / `role_employee`) and their open sessions refresh into the new role |

### Import / switching (owner)
| POST | /imports | multipart `file` (xlsx/csv) **or** JSON `{text}` (pasted) ; optional `kind:'staff'\|'attendance'`, `month` (for attendance grid), `source?:'auto'\|'salarybox'\|'pagarbook'\|'generic'` | `ImportSession` |
| GET | /imports/:id | | `ImportSession` |
| PATCH | /imports/:id | `{mapping?: {[header]: field\|null}, fixes?: {row, field, value}[], skipRows?: number[]}` | `ImportSession` |
| POST | /imports/:id/commit | `{overwriteExisting?: boolean}` | `{created, updated, skipped, undoUntil, rollbackUntil}` |
| POST | /imports/:id/rollback | | `{removed}` (undo ≤30s or rollback ≤24h) |

`ImportSession { id, kind, source, status:'review'|'committed'|'rolled_back', headers:string[], mapping:{[header]:field|null}, rows:{index, values:{name,phone,ratePaise,...}, issues:{field,message}[]}[], flaggedCount, totalRows, undoUntil?, rollbackUntil? }`
Fields: `name, phone, ratePaise, wageType, designation, joiningDate, branch, advanceBalancePaise, paidLeaveBalance, sickLeaveBalance, lastSalaryPaise`. Review UI shows only rows with `issues.length > 0`.

### Attendance
| POST | /attendance/check-in | `{clientTime, geo:{lat,lng,accuracyM}, mockLocation:boolean, lockCheck?:'passed'\|'failed'\|'unavailable', deviceId, selfieBase64?, clientPunchId}` (employee) | `{record: Attendance, punch: Punch}` ; 422 `OUTSIDE_GEOFENCE` if blocked. `lockCheck` is the phone screen-lock result (the app never sees the biometric). It never blocks: with `phoneLockPolicy:'recommended'` a non-pass is only flagged; with `'required'` anything but `passed` (including a missing value) makes the punch `pending` for owner approval |
| POST | /attendance/check-out | same | same |
| POST | /attendance/sync | `{punches: [{type:'in'\|'out', ...same as above}]}` (offline queue) | `{results: {clientPunchId, ok, error?, punch?}[]}` — idempotent by `clientPunchId` |
| GET | /attendance/today | (employee) | `{date, record: Attendance\|null, shift: Shift, branch: Branch}`. `shift` is today's roster shift when one was sent |
| GET | /attendance | `?date=YYYY-MM-DD` (owner/manager day view) | `DayRow[]` |
| GET | /attendance/month | `?month=YYYY-MM&employeeId?` (employee: own only) | `{month, days:string[], rows: {employee, days: {[date]: displayStatus}, totals}[]}` |
| POST | /attendance/fix-request | `{date, note?}` (staff) | `{sent}`: "I was there — ask owner to fix"; tells owners and managers (`attendance_fix_request`), once per day per date; future dates refused |
| POST | /attendance/override | `{employeeId, date, status, leaveType?, reason?}` (owner/manager; reason optional) | `Attendance` (audited) |
| POST | /attendance/:id/punches/:punchId/decision | `{approve:boolean}` | `Attendance` |
| POST | /attendance/clear-override | `{employeeId, date, reason}` (owner/manager) | `Attendance` with status recomputed from punches/leave/holiday (may be `null`), or `null` if no record. Used for Undo |

### Roster (owner/manager; feature `roster`: Starter and up)
| Method | Path | Body / Query | Returns |
|---|---|---|---|
| GET | /roster | `?week=YYYY-MM-DD` (any day of the week; default today) `&branchId` | `{weekStart, days: {date, holiday}[7], shifts: Shift[], staff: {id, name, designation, cells: {date, kind:'shift'\|'off', shiftId, usual, changed, leave, employed}[7]}[], notSent, problems: Problem[], repeat: {mode, startWeek, autoSend, staff}\|null, repeatAllowed}`. Opening a future week (up to 8 ahead) first fills it from "Repeat every week". A cell is the owner's plan: a roster day, or the usual shift and weekly off (`usual: true`). `changed` = not sent to staff yet |
| | | | `Problem`: `{type:'leave_working'\|'no_day_off', employeeId, name, date}` (one-tap fixes) or a warning that never blocks sending: `{type:'short_rest', employeeId, name, date, hours}` (rest before [date] under config `roster.minRestHours`, default 8; overnight shifts end next morning), `{type:'long_week', employeeId, name, date, hours}` (over config `roster.maxWeeklyHours`, default 48), `{type:'short_staff', date, shiftId, shiftName, count, min}` (fewer than the shift's `minStaff` on a day the shop is open). Rest and hours are checked only for people with roster days that week |
| PUT | /roster/cells | `{cells: {employeeId, date, kind:'shift'\|'off'\|'usual', shiftId?}[]}` (max 500) | `{saved}`. Saved as not sent; `usual` puts the day back to the usual shift |
| POST | /roster/copy-last-week | `{week?, branchId?}` | `{copied}`: last week's roster days onto the same weekdays, not sent |
| POST | /roster/send | `{week?, branchId?}` | `{sentTo, days}`. Sent days are what attendance (late/half day/auto-absent), leave counting and salary use. People whose days changed get a push, or WhatsApp if they haven't joined the app: `roster_published` the first time they get that week, `roster_changed` (just the changed days) after that. Days already worked are re-checked against the new shift |
| POST | /roster/repeat | `{week?, mode:'same'\|'rotate', autoSend?, branchId?}` (feature `roster_repeat`: Growth and up) | `{staff, mode, nextWeek, filled}`. Repeats [week]'s plan for everyone in view: `same` = every week alike; `rotate` = each person moves to the next shift every week (start-time order of the shifts used that week; needs 2+). Days off stay on the same days, and days on the usual shift keep following it. Each future week is filled once, as not sent; days the owner already planned are kept. Every Thursday from 10 AM the next week is filled, then sent (`autoSend`) or owners get a `roster_ready` push to check and send |
| DELETE | /roster/repeat | `?branchId` (any plan) | `{staff}`. Turns repeat off; future days it filled and nobody sent are removed |
| GET | /roster/swaps | (owner/manager: swaps between staff in scope; employee: their own) | `Swap[]` from the last 14 days on: `{id, date, from: {employeeId, name, kind, shiftId}, to: {…}, status:'asked'\|'accepted'\|'declined'\|'approved'\|'rejected'\|'cancelled'\|'expired', note}`. `from` is the asker; each side shows the day they had when asking |
| GET | /roster/swap-options | `?date` (employee; feature `roster_swaps`: Growth and up) | `{date, mine: {kind, shiftId, label}, colleagues: {employeeId, name, kind, shiftId, label}[]}`: active colleagues in the same branch, not on leave, with a different day |
| POST | /roster/swaps | `{date, withEmployeeId, note?}` (employee; `roster_swaps`) | `Swap` (asked). Today to 8 weeks ahead; one open swap per person per day. The colleague gets a push |
| POST | /roster/swaps/:id/accept \| decline \| cancel | (employee: the colleague accepts or declines; the asker cancels while open) | `Swap`. Accepting pushes owners and managers to approve |
| POST | /roster/swaps/:id/approve \| reject | (owner/manager) | `Swap`. Approving checks both still have the day they asked about (else `CONFLICT`), then swaps it as sent (attendance and salary follow it, today's late marks are re-checked), tells both and audits `roster.swap_approved` |
| GET | /roster/mine | `?week` (employee, every plan) | `{weekStart, rostered, swapsAllowed, shifts, days: {date, kind, shiftId, holiday, leave, changed}[7]}`: their week as sent (`changed` = sent in the last 3 days and different from their usual day; `rostered` = a roster was sent for this week) |

### Documents check (background verification)
Owner only for results (they include names on records and date of birth). Feature `verification` (Growth and up) to ask; config `verification.monthly` = `{growth: 3, pro: 10}` checks a month, `verification.extraPricePaise` for more (paid checks come in a later round). Nothing is checked until the staff member agrees. Full Aadhaar and bank numbers are never stored, only the last 4 digits. Results are deleted `verification.retentionDays` (180) after the person leaves.

| Method | Path | Body / query | Response |
|---|---|---|---|
| GET | /verification/employees/:id | (owner) | `{badge, request: {id, kinds, status:'asked'\|'in_progress'\|'done', consented, consentBy:'staff'\|'owner_on_behalf'\|null, hasSlip, …}\|null, checks: Check[], quota: {used, limit, extraPricePaise}, hasApp}`. `Check`: `{id, kind:'aadhaar'\|'pan'\|'bank'\|'face', status:'waiting'\|'otp_sent'\|'verified'\|'mismatch'\|'not_found'\|'failed', last4, nameOnRecord, matchScore, override: {reason, at}\|null, details (owner only, e.g. dob), attempts}` |
| POST | /verification/employees/:id | `{kinds}` (owner; `verification`) | View. One open request per person; `PLAN_LIMIT` (402, with `used`, `limit`, `extraPricePaise`) when the month's checks are used. Staff get a push, or WhatsApp `verification_request` if they haven't joined the app |
| DELETE | /verification/employees/:id | (owner) | View. Cancels an open request; it no longer counts for the month |
| POST | /verification/checks/:id/accept | `{reason}` (owner) | View. Accepts a name mismatch ("Rajesh" vs "Rajesh Kumar") |
| POST | /verification/checks/:id/ask-again | (owner) | View. Sends one check back to the staff member |
| GET | /verification/mine | (staff) | `{businessName, request, checks, consentText: {en: string[], hi: string[]}, savedBank: {last4, ifsc}\|null, idPhoto}` (`idPhoto`: a photo ID is uploaded, needed for the selfie) |
| POST | /verification/mine/consent | (staff) | Mine. Records the consent version and time |
| POST | /verification/mine/aadhaar/otp | `{aadhaar}` (staff) | Mine. OTP to the Aadhaar-linked mobile |
| POST | /verification/mine/aadhaar/verify | `{otp}` (staff) | Mine. Wrong OTP → `OTP_INVALID` |
| POST | /verification/mine/pan | `{pan}` (staff) | Mine. A verified PAN fills the profile's PAN if it was empty |
| POST | /verification/mine/bank | `{accountNumber?, ifsc?}` (staff) | Mine. ₹1 test; no account given = the salary account on file. A verified new account becomes their salary account (owners are told, as with any bank change) |
| POST | /verification/mine/face | `{selfie}` (base64 JPEG, staff) | Mine. Matched with the photo on their newest photo ID document (Aadhaar, PAN, licence, voter ID, passport) using the face provider. No photo ID → `CONFLICT` with `details.reason: 'no_id_photo'`; no clear face in the selfie → `FACE_NOT_CLEAR` (not counted as a try). `verified` at `verification.faceMatchMin` (80) or above, else `mismatch` for the owner; no face on the ID photo → `not_found`. `matchScore` is the similarity; `details.idKind` says which ID (owner only). The selfie is not stored |
| GET | /verification/employees/:id/on-behalf | (owner) | Mine-shaped view of that person's steps, for doing them together (staff without a smartphone) |
| POST | /verification/employees/:id/on-behalf/consent | `{staffAgreed: true, slip: {data, mime}}` (owner) | Mine. They agreed on paper: records `consentBy: 'owner_on_behalf'` and keeps the photo of the signed slip (encrypted, like documents) |
| POST | /verification/employees/:id/on-behalf/aadhaar/otp \| aadhaar/verify \| pan \| bank \| face | same bodies as the `mine` steps (owner) | Mine. The same steps done by the owner; the Aadhaar OTP still goes to the person's Aadhaar mobile |
| POST | /verification/employees/:id/slip/open | (owner) | `{url, mime}`: 5-minute link to the signed slip. Audited (`document.view`) |

Names are compared ignoring case, order, titles and initials; below `verification.nameMatchMin` (80) a check is `mismatch` for the owner to accept or ask again. Staff can retry "not found" or a mismatch up to 5 times; provider errors are `failed` (try again). When every check has a result, owners get a push (`verification_done`).

### Staff documents
Photos (JPG, PNG) and PDFs, up to 3 files per document, 4 MB each and 7 MB together. Feature `documents` (Starter and up) to add; anyone can still see and remove what's there. Files are encrypted with `FIELD_ENCRYPTION_KEY` before they reach storage and are opened only through 5-minute signed links; each opening is audited (`document.view`, shown in History as "Ramesh Kumar: PAN opened"). Only the last 4 characters of a document number are kept (digits only for Aadhaar). Owners see everyone's documents; managers and accountants don't. Staff see and add their own. Deleted with their files `verification.retentionDays` (180) after the person leaves.

| Method | Path | Body / query | Response |
|---|---|---|---|
| GET | /verification/employees/:id/documents | (owner) | `{documents: Doc[], agreementOnFile}`. `Doc`: `{id, kind:'aadhaar'\|'pan'\|'dl'\|'voter'\|'passport'\|'bank_proof'\|'address'\|'police'\|'experience'\|'other', label, numberLast4, files: {mime, size}[], expiresOn, expiry:'ok'\|'soon'\|'expired'\|null, addedBy:'staff'\|'owner', hasSlip, createdAt}`. `agreementOnFile`: they added a document themselves, agreed to a documents check, or a signed slip is on file |
| POST | /verification/employees/:id/documents | `{kind, label?, number?, expiresOn?, files: {data (base64), mime}[], staffAgreed, slip?: {data, mime}}` (owner; `documents`) | `Doc`. For staff without the app: `staffAgreed` must be true (`CONSENT_REQUIRED`), and a photo of the signed consent slip is needed the first time (no agreement on file) |
| PATCH | /verification/documents/:id | `{expiresOn?, label?}` (owner) | `Doc`. A new expiry date reminds again |
| DELETE | /verification/documents/:id | (owner: any; staff: only ones they added) | `{ok}`. Files are deleted too |
| POST | /verification/documents/:id/open | (owner; staff for their own) | `{files: {url, mime}[], slip: {url, mime}\|null (owner only), expiresInSec: 300}`. Audited |
| GET | /doc-files/:token | (no login; the signed link) | The decrypted file. `403` when the link is changed or expired |
| GET | /verification/mine/documents | (staff) | `{documents: Doc[]}` |
| POST | /verification/mine/documents | `{kind, label?, number?, expiresOn?, files}` (staff; `documents`) | `Doc`. Owners get a push (`document_added`) |

Driving licences, passports and police certificates ask for a "valid till" date. From 10 AM each day, documents that run out within 30 days (or already have) push the owner and the staff member once per date (`document_expiring`).

### Leave
| GET | /leaves | `?status&employeeId` (employee → own) | `Leave[]` |
| POST | /leaves | `{type, from, to, halfDay?, reason?, employeeId?}` (employeeId only for owner applying on behalf) | `Leave` |
| POST | /leaves/:id/decision | `{decision:'approved'\|'rejected', note?, asUnpaid?:boolean}` (owner/manager). `asUnpaid` approves the days as unpaid leave (no paid balance used) | `Leave` |
| POST | /leaves/:id/cancel | | `Leave` |
| GET | /leave-balances | `?employeeId&year` | `LeaveBalance[]` |
| PUT | /leave-balances/:employeeId | `{year, paid, sick}` | `LeaveBalance` |

### Advances & adjustments (owner)
| GET | /advances | `?employeeId&status` | `Advance[]` |
| POST | /advances | `{employeeId, amountPaise, date, mode, installments?, note?}` | `Advance` |
| POST | /advances/:id/skip | `{month}` | `Advance` |
| GET | /adjustments | `?month&employeeId` | `Adjustment[]` |
| POST | /adjustments | `{employeeId, month, type, amountPaise, note?}` | `Adjustment` |
| DELETE | /adjustments/:id | | `{ok:true}` |

### Payroll & payslips
| GET | /payroll/runs | `?month` | `PayrollRun[]` |
| POST | /payroll/runs | `{month}` → creates or recomputes the draft | `PayrollRun` (with payslips) |
| GET | /payroll/runs/:id | | `PayrollRun` (with payslips) |
| POST | /payroll/runs/:id/recompute | | `PayrollRun` |
| POST | /payroll/runs/:id/approve | | `PayrollRun` (payslip PDFs generated) |
| POST | /payroll/runs/:id/mark-paid | `{paidOn?: 'YYYY-MM-DD', method?: 'cash'\|'upi'\|'bank'\|'mixed'}` | `PayrollRun`; slips show "Paid on … by …" (PDFs regenerated), staff get a `salary_paid` message |
| POST | /payroll/runs/:id/revise | | `PayrollRun` (new draft, revision+1) |
| POST | /payroll/runs/:id/compare | multipart `file` (old app's salary report xlsx/csv) | `{rows: {employeeName, ours, theirs, diffPaise, reasons:string[]}[], matched, unmatched}` |
| GET | /payslips | `?month&employeeId` (employee → own, final/sent only) | `Payslip[]` |
| GET | /payslips/:id | | `Payslip` (pdfUrl is a short-lived signed URL) |
| GET | /payslips/:id/explain | | `{text, lines:string[]}` plain language |
| POST | /payslips/send | `{runId, payslipIds?}` → WhatsApp + push | `{queued}` |

### Reports (owner/ca) — returns the file (`Content-Disposition: attachment`), or `{url}` with `&delivery=url`
`GET /reports/attendance?month&format=pdf|xlsx` · `/reports/salary` · `/reports/advances` · `/reports/late`

### Mint assistant (owner/manager; employee gets employee intents)
| POST | /assistant/message | `{text?, audioBase64?, audioMime?, sessionId?}` | `AssistantReply` |
| POST | /assistant/confirm | `{pendingActionId, action:'confirm'\|'cancel'\|'choose', optionId?}` | `AssistantReply` |

### Trust
| GET | /audit-logs | `?entity&entityId&category?=attendance\|leave\|salary\|staff\|settings\|team\|billing&limit&before` (owner) | `AuditLog[]`, each also with `text` (one plain sentence in the caller's language, e.g. "Raju: 1 Oct set to Absent"), `category` and `changes: {label, from?, to}[]`. StaffMint support sign-ins are not listed |
| GET | /export | `?delivery=url` optional | zip (xlsx + payslip PDFs), or `{url, filename}`; available even after cancellation (30 days) |

### Billing
| GET | /billing/plans | (public) | `Plan[]` |
| GET | /billing/subscription | | `{subscription, plan, staffCount, billStaffCount, trial: Trial\|null, usage, recommendation, priceLockMonths, billedTo}`. `usage`: paid features used since the trial started (at most 30 days back), e.g. `{face_match: 85, whatsapp_payslips: 12, branches: 0, ca_access: 0, payroll, payslips, advances, assistant, whatsapp_assistant}`. `recommendation`: `{planCode, reasons: ({kind:'staff', staff, limit} \| {kind:'feature', feature, count})[], cheaper: {planCode, loses: {feature, count}[]}\|null}`, the cheapest plan that holds the staff on the bill and covers every paid feature in use |
| GET | /billing/receipts | | `{id, planCode, planName, interval, amountPaise, currency, paidAt, periodEnd, hasInvoice}[]`, newest first: one per gateway payment |
| GET | /billing/receipts/:id/link | | `{url}` of the gateway's invoice (GST invoice on Razorpay); 404 when there is none |
| POST | /billing/subscribe | `{planCode, interval:'monthly'\|'yearly'}` | `{provider, subscriptionId, checkoutUrl, keyId?}` |
| POST | /billing/cancel | | `{subscription}` |

### Config / health
`GET /config/public` → `{minAppVersion, features, supportWhatsApp, otpProvider, environment}` · `GET /health` (no `/api/v1` prefix).

### Webhooks (signature verified)
`POST /webhooks/payments/:provider` · `GET|POST /webhooks/messaging/:provider`

### Admin (admin app session `Authorization: Bearer <admin token>`, or header `x-admin-key: $ADMIN_API_KEY` for scripts)
**Sign-in (admin app):** `POST /admin-auth/login {email, password}` → `{ticket, sentTo, devCode?}` (6-digit code emailed; `devCode` only with the mock email provider outside production) ·
`POST /admin-auth/verify {ticket, code}` → `{accessToken, expiresInSec: 43200, admin}`. Admin tokens use their own audience; owner/staff tokens are refused.
5 wrong passwords lock the account for 15 minutes; a code allows 5 tries and lasts 10 minutes. Rate limit: 20 sign-in calls per 15 minutes per IP.

Roles: `admin` (everything) and `viewer` (all GETs; changes return 403). Every change is written to the activity log (`AdminAction`).

| Method | Path | Notes |
|---|---|---|
| GET | /admin/me · POST /admin/logout · POST /admin/me/password `{current, next}` | logout and password change end every session of that admin |
| GET | /admin/stats | businesses by status, owners, active staff, signups (7/30 days + per day), monthly revenue (paise), paid plans, trials ending in 3 days, pending recoveries, failed messages (7 days) |
| GET | /admin/companies?search=&status=&page=&limit= | search by name, id or owner phone; status `trial`\|`paid`\|`past_due`\|`free`\|`closed`\|`billed_with` |
| GET | /admin/companies/:id | plan, trial, people, staff, subscriptions, failed messages, admin changes |
| POST | /admin/companies/:id/plan `{planCode, months=1, note?}` | put on a plan by hand (no charge, `pricePaise: 0`); `free` ends it. Refused (409 `provider_subscription`) while a Razorpay subscription is live |
| GET/PUT | /admin/plans · /admin/plans/:code | GET lists the built-in plans until the first edit |
| GET/PUT | /admin/flags | |
| GET | /admin/configs | every setting: value, default, changed, businesses with their own value |
| GET/PUT | /admin/configs/:key `{value, companyId?}` | a known setting keeps its type (number, text, on/off, list) |
| GET | /admin/messages?status=&channel=&companyId= | WhatsApp/push/SMS/email across businesses |
| GET | /admin/actions?companyId= | activity log |
| GET/POST/PATCH | /admin/admins · /admin/admins/:id `{role?, active?, name?}` | at least one active admin is kept; you can't remove your own access |

First admin: `npm run admin:create -- --email you@example.com --password '<10+ chars>'` (production image: `node dist/scripts/createAdmin.js …`). Running it again for the same email resets the password.

`POST /admin/trials` `{companyId? | phone?, days=14, planCode='pro'}` → `[{companyId, name, planCode, trialEndsAt} | {companyId, name, skipped:'paid_plan'}]`.
A fresh free trial for one business, or every business a phone owns (testing, support). `days: 0` ends the trial now. Businesses on a paid plan are skipped.

**Free trial rules:** a new owner's first business gets `signup.trialPlan` (default `pro`) for that plan's `trialDays` (14). One trial per owner: later businesses share its end date while it runs and start on Free after. The scheduler sends `trial_reminder` 3 and 1 days before the end (`trial.reminderDays`) and `trial_ended` once (push + WhatsApp to the main owner, 10 AM–8 PM local). At the end the business is on Free, and face check is set to `off` if Free doesn't include it.

## Implementation notes
- `deviceId` values starting with `web-` never bind or block an employee's phone binding.
- Days with no attendance record are classified as holiday, week off or approved leave when that applies, otherwise `not_marked`. Payroll treats `not_marked` days as unpaid and flags them as an anomaly.
- Draft payslip IDs change on every recompute; approved payslips are stable and become immutable once sent.

### Face check
- Off by default (`faceMatchPolicy:'off'`). Turning it on needs a plan with the `face_match` feature (Growth, Pro); otherwise 402 `FEATURE_NOT_IN_PLAN`.
- Only selfies of staff whose photo the owner **approved** are compared. Results: `match` (≥ `FACE_MATCH_THRESHOLD`, default 90), `unsure` (≥ `FACE_UNSURE_THRESHOLD`, default 75), `mismatch`, `no_face`, `many_faces`. Anything but `match` makes the punch `pending` for owner approval; the dashboard then sends `facePhotoUrl` so both photos can be compared.
- `error` (engine down, photo missing) only adds the `face_check_failed` flag. It never blocks or holds a check-in.
- The reference photo is deleted when the staff member withdraws consent, when the owner resets it, and when the staff member is deactivated.
- `FACE_PROVIDER=mock` refuses to decide in production, so a missing key cannot approve anyone.

### Accounts at scale (F14 Phase 4)
| Method | Path | Body | Returns |
|---|---|---|---|
| PATCH | /me/accounts/:membershipId | `{pinned}` | pins an account to the top of the chooser; memberships carry `pinned` |
| GET | /me/clients | — | accountant's clients: `[{membershipId, companyId, companyName, staffCount, month, payrollStatus:'not_started'\|'draft'\|'approved'\|'paid', netPaise, pinned}]` (last month, pinned first) |
| GET | /billing/group | — | `{payer, isPayer, members, candidates, totalStaff, extraBusinessPricePaise, plan}` |
| POST · DELETE | /billing/group/members · /billing/group/members/:companyId | `{companyId}` (main owner of both) | put another of your businesses on this bill / take it off |

- **One bill for several businesses:** a business on another's bill (`company.billedTo`) uses the payer's plan; `/billing/subscribe` there returns 409 `billed_elsewhere`. Staff limits and extra-staff pricing count staff across the whole bill, plus `billing.extraBusinessPricePaise` (₹199/month default, yearly ×10) per extra business. A business with its own paid plan must cancel it before joining. Price changes apply to the next subscription/renewal.
- **WhatsApp with several businesses:** the first message asks "Which business is this for?" (buttons, plus a numbered list past 3) and keeps the message until answered; the choice is remembered (`user.whatsappCompanyId`). "switch", "switch to <name>" or "business badlo" changes it. Replies start with `*Business name* ·`. Leave buttons from alerts always act on the business that sent them.

### Accounts: shared ownership & recovery (F14 Phase 3)
| Method | Path | Body | Returns |
|---|---|---|---|
| GET | /company/owners | — | `[{id, userId, name, phone, isMain, canManageBilling, isYou}]` (owners) |
| POST | /company/owners | `{phone, name, canManageBilling?}` (main owner) | owners list; the number gets an owner account (co-owner) |
| PATCH · DELETE | /company/owners/:membershipId | `{canManageBilling}` · — (main owner) | owners list |
| POST | /company/transfer | `{phone, keepAs:'co_owner'\|'leave', code}` — `code` is an OTP to the main owner's own number | pending offer (7 days) |
| GET · DELETE | /company/transfer | — | the pending offer · cancel it |
| POST | /company/owner-recovery | `{newPhone}` (co-owner) | offer of kind `recovery`; the old number is told by text |
| POST | /me/transfers/:id/accept · /decline | `{deviceId, refreshToken?}` | accept → `Session` as main owner |
| POST | /auth/identity/confirm · /reject | `{token}` from `identityCheck` | `Session` (reject: the number starts fresh; the previous person's staff records wait for their owners to update the number) |
| POST | /me/recovery/email | `{email}` | `{sent:true, devCode?}` (same answer for unknown emails) |
| POST | /me/recovery/email/verify | `{email, code, deviceId, refreshToken?}` | `Session` of the recovered account, now on this number |
| POST · GET | /me/recovery-requests | `{oldPhone, businessName, gstin?, paymentTxnId?, selfieVideoBase64?}` (2 of 3 proofs) | request / my requests |
| POST | /me/recovery-holds/:id/stop | — | the old number or the business's owners, managers and CA can stop a hold |
| GET | /admin/recovery-requests?status= · POST /admin/recovery-requests/:id/approve · /reject | admin key | approve starts the 7-day hold (`accounts.recoveryHoldDays`); the scheduler completes it |
| GET | /me/export | — | profile, all accounts, own payslips |
| POST | /me/delete | `{code}` (OTP to own number) | 409 `owns_business` while main owner of an open business |
| GET | /me/past-payslips | — | `[{companyId, companyName, endedAt, payslips}]` for 12 months after leaving, unless `settings.exStaffPayslips` is false |

- Billing (`/billing/subscription`, `/subscribe`, `/cancel`): main owner, or a co-owner with `canManageBilling`. Closing, transferring and managing owners: main owner only. Co-owners can leave; the main owner cannot.
- `POST /auth/otp/verify` may return `{identityCheck:{token, maskedName}}` instead of a session when the number was idle for `accounts.recycleDays` (180) and the phone is new: the app asks "Is this you, R*** K***?".
- `GET /me` adds `pendingTransfers` and `recoveryHolds`.

### Accounts: never stuck (F14 Phase 2)
| Method | Path | Body | Returns |
|---|---|---|---|
| POST | /me/accounts/:membershipId/leave | `{deviceId, refreshToken?}` | `Session` on the next account (or none). Staff/manager/CA only; owners get 409 `owner_cannot_leave` |
| POST | /me/notices/:membershipId/dismiss | — | `{ok}` hides an "access ended" notice |
| POST | /me/device-requests | `{membershipId, deviceId, deviceName?}` | 201 `{status:'pending', request}` (or `{status:'not_needed'}`); owner/managers are notified |
| GET | /device-requests | — | pending requests in scope (owner/manager) |
| POST | /device-requests/:id/approve · /reject | — | approve binds the new phone and ends the old phone's session in that account |
| POST | /company/close | `{confirmName, deviceId, refreshToken?}` (main owner) | `Session` on the owner's next account. Everyone's access ends (reason `closed`), paid plan cancelled, restorable for `accounts.restoreDays` (30) |
| POST | /me/businesses/:companyId/restore | `{deviceId, refreshToken?}` | `Session` in the restored business; everyone who had access gets it back |
| GET | /company/accountants · DELETE /company/accountants/:membershipId | — | list / remove accountants (owner) |
| POST | /employees/remind-invites | — (owner/manager) | `{sent, skipped}`: re-sends the app invite to every active staff member who hasn't joined; skips anyone invited in the last 10 min |
| POST | /employees/:id/invite | — | `{invitedAt}`; WhatsApp `staff_invite` with the app link; at most once per 10 min. `POST /employees` sends it automatically unless `invite:false` |

- **Soft landing:** when an account ends or its role changes, the next request with that token gets `401 TOKEN_EXPIRED` with `details.reason:'account_changed'`. Apps refresh as usual; `POST /auth/refresh` then returns `accountChange: {kind:'ended'|'role_changed', reason, companyName, role, activeMembershipId}` and the new tokens open the next account (or none). Nobody is logged out of their other businesses.
- `GET /me` adds `blockedAccounts` (staff accounts locked to another phone), `endedNotices` (`{id, companyName, endedAt, endedReason}`, last 30 days) and `closedBusinesses` (restorable). Login with only phone-locked staff accounts succeeds with no business open and `blockedAccounts` filled, instead of `DEVICE_NOT_BOUND`.
- `GET /dashboard/today` → `needsAction.deviceRequests`. Employee views add `linked` and `invitedAt`.
- Someone who left stays out until the owner re-invites or reactivates them. Staff of a closed business are not re-attached at login.

### Staff logins and accounts
- Each person (phone) is one user; each business they can open is a membership. Every active staff record with their number becomes a staff membership: at OTP login, on `POST /auth/refresh` (the app's "Check again" when they had no business), and as soon as the owner adds the staff or edits the staff phone.
- `POST /employees` and a phone change in `PATCH /employees/:id` return 409 with `details.reason` only for this business's own people:
  - `owner_number`: the number is this business owner's own login.
  - `accountant_number`: the number is this business's accountant.
  Owners and staff of other businesses can be added; they get one more account.
- Phone binding is per staff membership: the first phone that opens a staff account is the only one allowed for it (check-in included) until the owner resets the device. Owner and CA accounts are not bound, and web sessions never bind.
- Deactivating staff, a staff phone change and an import rollback end that business's membership and its sessions only; the person keeps their other accounts. A role change (employee ↔ manager) updates the membership and ends its sessions so the new access applies on next login.
- WhatsApp commands use the business last opened in the app (else the most senior access). Push data includes `companyId` so the app can open the right account.
- Accounts made before memberships get one automatically on their next login or refresh.
