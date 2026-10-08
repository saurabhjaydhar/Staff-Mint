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
                        weekOffsPaid, holidaysPaid, sickLeavePaid, outsideGeofencePolicy:'block'|'request_approval', language, digestTime:'09:30',
                        roundToRupee, selfieRequired, maxDeviceTimeDriftMin, selfieRetentionDays, whatsappAlerts },
            plan: Plan, subscription: { status:'trialing'|'active'|'past_due'|'cancelled'|'free', planCode, currentPeriodEnd|null } }
Branch    { id, name, location:{lat,lng,address?}, radiusM, shiftId }
Shift     { id, name, start:'09:00', end:'19:00', graceMinutes:number|null, weeklyOff:number[] }
Employee  { id, name, phone, branchId, shiftId, wageType:'monthly'|'daily', ratePaise, designation?, joiningDate?, status:'active'|'inactive',
            consent:{ location:boolean, at?:string }, hasDevice:boolean, language }
Punch     { id, type:'in'|'out', clientTime /* effective time: server time online, device time for offline sync */, deviceTime, serverTime, geo:{lat,lng,accuracyM}|null, distanceM|null, insideGeofence|null, selfieUrl|null,
            mockLocation, deviceId, source:'app'|'offline_sync'|'owner'|'assistant'|'import', flags:string[], approval:'not_required'|'pending'|'approved'|'rejected' }
            // flags: late_sync, device_time_drift, mock_location, low_accuracy, outside_geofence
Attendance { id, employeeId, date, status:'present'|'absent'|'half_day'|'leave'|'holiday'|'week_off'|null, leaveType?:'paid'|'sick'|'unpaid',
             punches: Punch[], lateMinutes, earlyOutMinutes, workedMinutes, overridden, overrideReason?, flags:string[] }
DayRow    { employee: {id,name,phone,designation}, record: Attendance|null,
            displayStatus:'present'|'late'|'checked_in'|'absent'|'half_day'|'leave'|'holiday'|'week_off'|'not_marked' }
Leave     { id, employeeId, employeeName, type:'paid'|'sick'|'unpaid', from, to, days, halfDay, reason?, status:'pending'|'approved'|'rejected'|'cancelled', decidedAt?, note? }
LeaveBalance { employeeId, year, paid, sick, usedPaid, usedSick }
Advance   { id, employeeId, employeeName, amountPaise, date, mode:'installments'|'full_next', installments, installmentPaise, repaidPaise, balancePaise,
            status:'active'|'closed', skipMonths:string[], note? }
Adjustment { id, employeeId, employeeName, month, type:'bonus'|'deduction', amountPaise, note? }
PayslipLine { code, kind:'earning'|'deduction', label, amountPaise, explanation }
Payslip   { id, runId, employeeId, employeeName, month, revision, wageType, ratePaise, payableDays, daysInMonth, divisor,
            summary:{ present, halfDay, absent, paidLeave, unpaidLeave, holidays, weekOffs, unmarked },
            lines: PayslipLine[], grossPaise, deductionsPaise, netPaise, status:'draft'|'final'|'sent', pdfUrl:string|null, sentAt? }
PayrollRun { id, month, revision, status:'draft'|'approved'|'paid'|'superseded', engineVersion,
             totals:{ grossPaise, deductionsPaise, netPaise, employees }, anomalies:{ employeeId, employeeName, code, message }[],
             approvedAt?, paidAt?, payslips?: Payslip[] }
AssistantReply { sessionId, kind:'answer'|'confirm'|'choose'|'done'|'cancelled'|'error', text,
                 options?: {id,label}[], pendingActionId?, preview?: {title, rows:{label,value}[]}, data?: any, attachment?: {url, filename} }
AuditLog  { id, actorId, actorName, channel:'app'|'web'|'assistant'|'whatsapp'|'system'|'import', action, entity, entityId, before, after, at }
```

## Endpoints

### Auth (public)
| Method | Path | Body | Returns |
|---|---|---|---|
| POST | /auth/otp/request | `{phone, channel?:'sms'\|'whatsapp'}` | `{requestId, expiresInSec, devCode?}` (devCode only when OTP provider is `mock`) |
| POST | /auth/otp/verify | `{phone, code, deviceId, deviceName?}` | `{accessToken, refreshToken, user:User, needsCompanySetup:boolean}` |
| POST | /auth/refresh | `{refreshToken}` | `{accessToken, refreshToken}` (rotation; old refresh token invalid) |
| POST | /auth/logout | `{refreshToken}` | `{ok:true}` |

Phone: E.164 (`+919876543210`) or 10-digit Indian (`9876543210`, normalised server-side). A phone that belongs to an employee logs in as `employee` (device is bound on first login; another device → `DEVICE_NOT_BOUND` until owner resets). Unknown phone → new `owner` with `needsCompanySetup:true`.

### Me
| GET | /me | — | `{user, company:Company\|null, employee:Employee\|null}` |
| PATCH | /me | `{name?, language?}` | `User` |
| POST | /me/consent | `{location:true}` | `Employee` |
| POST | /me/push-token | `{token, platform:'android'\|'ios'\|'web'}` | `{ok:true}` |
| GET | /me/salary | `?month` | `{estimate: Payslip-like (status 'draft', not persisted), advanceBalancePaise, payslips: Payslip[]}` (employee) |
| GET | /me/notifications | — | `{id,title,body,data,readAt,createdAt}[]` |
| POST | /me/notifications/read | `{ids}` | `{ok:true}` |

### Company setup & settings (owner)
| POST | /company | `{name, businessType, location:{lat,lng,address?}, openingTime:'09:00', closingTime?:'19:00', weeklyOff:number[], country?:'IN', timezone?:'Asia/Kolkata', currency?:'INR'}` | `{company, accessToken, refreshToken}` (new tokens carry companyId) |
| GET | /company | — | `Company` |
| PATCH | /company | `{name?, businessType?, location?}` | `Company` |
| PATCH | /company/settings | partial `settings` | `Company` |
| GET | /company/rules | — | `{rules: {key, text}[]}` plain-language (hi/en by Accept-Language) |
| POST | /company/accountants | `{phone, name}` (Pro plan) | CA user with read access to reports/payroll/export |
| GET/POST | /branches | `{name, location, radiusM?}` | `Branch[]` / `Branch` |
| PATCH | /branches/:id | partial | `Branch` |
| GET/POST | /shifts | `{name, start, end, graceMinutes?, weeklyOff}` | |
| PATCH | /shifts/:id | partial | |
| GET | /holidays | `?year` | `{id,date,name}[]` |
| POST | /holidays | `{date, name}` | |
| DELETE | /holidays/:id | | |

### Dashboard (owner/manager)
| GET | /dashboard/today | — | `{date, counts:{total,present,late,absent,onLeave,notMarked,checkedIn}, needsAction:{leaveRequests:Leave[], punchApprovals:{attendanceId,employeeName,punch}[], flags:{employeeName,date,flags}[]}, plan:{staffCount, staffLimit}}` |

### Employees (owner/manager)
| GET | /employees | `?search&status=active\|inactive\|all&branchId` | `Employee[]` |
| POST | /employees | `{name, phone, wageType?, ratePaise?, branchId?, shiftId?, designation?, joiningDate?}` | `Employee` (402 `PLAN_LIMIT` when over plan staff limit) |
| POST | /employees/bulk | `{employees: [...same as above]}` (contacts picker) | `{created: Employee[], skipped: {phone, reason}[]}` |
| GET | /employees/:id | — | `Employee & {leaveBalance, advanceBalancePaise}` |
| PATCH | /employees/:id | partial + `effectiveFrom?` (for rate change → new salary structure version) | `Employee` |
| POST | /employees/:id/deactivate | `{reason?}` | `Employee` |
| POST | /employees/:id/reset-device | — | `Employee` |
| POST | /employees/:id/reactivate | — | `Employee` |
| POST | /employees/:id/role | `{role:'employee'\|'manager'}` (owner) | `Employee` |

### Import / switching (owner)
| POST | /imports | multipart `file` (xlsx/csv) **or** JSON `{text}` (pasted) ; optional `kind:'staff'\|'attendance'`, `month` (for attendance grid), `source?:'auto'\|'salarybox'\|'pagarbook'\|'generic'` | `ImportSession` |
| GET | /imports/:id | | `ImportSession` |
| PATCH | /imports/:id | `{mapping?: {[header]: field\|null}, fixes?: {row, field, value}[], skipRows?: number[]}` | `ImportSession` |
| POST | /imports/:id/commit | `{overwriteExisting?: boolean}` | `{created, updated, skipped, undoUntil, rollbackUntil}` |
| POST | /imports/:id/rollback | | `{removed}` (undo ≤30s or rollback ≤24h) |

`ImportSession { id, kind, source, status:'review'|'committed'|'rolled_back', headers:string[], mapping:{[header]:field|null}, rows:{index, values:{name,phone,ratePaise,...}, issues:{field,message}[]}[], flaggedCount, totalRows, undoUntil?, rollbackUntil? }`
Fields: `name, phone, ratePaise, wageType, designation, joiningDate, branch, advanceBalancePaise, paidLeaveBalance, sickLeaveBalance, lastSalaryPaise`. Review UI shows only rows with `issues.length > 0`.

### Attendance
| POST | /attendance/check-in | `{clientTime, geo:{lat,lng,accuracyM}, mockLocation:boolean, deviceId, selfieBase64?, clientPunchId}` (employee) | `{record: Attendance, punch: Punch}` ; 422 `OUTSIDE_GEOFENCE` if blocked |
| POST | /attendance/check-out | same | same |
| POST | /attendance/sync | `{punches: [{type:'in'\|'out', ...same as above}]}` (offline queue) | `{results: {clientPunchId, ok, error?, punch?}[]}` — idempotent by `clientPunchId` |
| GET | /attendance/today | (employee) | `{date, record: Attendance\|null, shift: Shift, branch: Branch}` |
| GET | /attendance | `?date=YYYY-MM-DD` (owner/manager day view) | `DayRow[]` |
| GET | /attendance/month | `?month=YYYY-MM&employeeId?` (employee: own only) | `{month, days:string[], rows: {employee, days: {[date]: displayStatus}, totals}[]}` |
| POST | /attendance/override | `{employeeId, date, status, leaveType?, reason}` (owner/manager) | `Attendance` (audited) |
| POST | /attendance/:id/punches/:punchId/decision | `{approve:boolean}` | `Attendance` |

### Leave
| GET | /leaves | `?status&employeeId` (employee → own) | `Leave[]` |
| POST | /leaves | `{type, from, to, halfDay?, reason?, employeeId?}` (employeeId only for owner applying on behalf) | `Leave` |
| POST | /leaves/:id/decision | `{decision:'approved'\|'rejected', note?}` (owner/manager) | `Leave` |
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
| POST | /payroll/runs/:id/mark-paid | | `PayrollRun` |
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
| GET | /audit-logs | `?entity&entityId&limit&before` | `AuditLog[]` |
| GET | /export | `?delivery=url` optional | zip (xlsx + payslip PDFs), or `{url, filename}`; available even after cancellation (30 days) |

### Billing
| GET | /billing/plans | (public) | `Plan[]` |
| GET | /billing/subscription | | `{subscription, plan, staffCount}` |
| POST | /billing/subscribe | `{planCode, interval:'monthly'\|'yearly'}` | `{provider, subscriptionId, checkoutUrl, keyId?}` |
| POST | /billing/cancel | | `{subscription}` |

### Config / health
`GET /config/public` → `{minAppVersion, features, supportWhatsApp, otpProvider, environment}` · `GET /health` (no `/api/v1` prefix).

### Webhooks (signature verified)
`POST /webhooks/payments/:provider` · `GET|POST /webhooks/messaging/:provider`

### Admin (header `x-admin-key: $ADMIN_API_KEY`)
`GET/PUT /admin/plans/:code` · `GET/PUT /admin/flags` · `GET/PUT /admin/configs/:key`

## Implementation notes
- `deviceId` values starting with `web-` never bind or block an employee's phone binding.
- Days with no attendance record are classified as holiday, week off or approved leave when that applies, otherwise `not_marked`. Payroll treats `not_marked` days as unpaid and flags them as an anomaly.
- Draft payslip IDs change on every recompute; approved payslips are stable and become immutable once sent.
