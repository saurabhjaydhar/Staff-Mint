# Plan: Owner marks attendance, Present by default, quick marking

Status (12 Oct 2026): **Round 1 built**: who marks attendance (business setting + per staff), check-in blocked for owner-marked staff, view-only staff home, and Present by default (an owner setting, off at first). Sections 3 and 5 (quick marking, evening reminder, Mint, manager limits) are still planned. Available on **every plan**, including free.

## Why

Some owners don't want staff to check in themselves. This is common in shops, factories, site work and for staff without smartphones. The owner or a manager wants to take the register, and staff should only *see* their attendance, leave and salary.

With 50 staff, marking everyone one by one every day is too slow. The owner should only have to mark the exceptions.

## What SalaryBox does (checked 12 Oct 2026)

| Topic | SalaryBox | StaffMint today |
|---|---|---|
| Turn off staff check-in | Per employee: My Team → staff → Attendance → Attendance Modes → **"Allow punch-in from the Staff App"**. When off, staff can't punch in, and the Selfie / QR / GPS toggles stop working. | Not possible. Every staff member with the app can always check in. |
| Change settings for many staff | Select all with the top checkbox → "Update Attendance Modes" / "Update Automation Rules" / "Update Work Timings". | One staff member at a time. |
| Staff without smartphones | Kiosk on a shared phone, **or** an Attendance Manager punches for them from the manager's phone. | Owner sets the day on the Today screen. Staff without the app show as "Hasn't installed the app", and everyone unmarked is auto-**Absent** at 11:59 PM. |
| Mark all present / present by default | Not documented in their help centre. Zoho People has "Present by default". | Not available. |
| Manager roles | **Attendance Manager**: today only, own branch, no salary or reports. **Advanced Attendance Manager**: also past days and leave. **Branch Admin**: past days, leave, payroll. | One Manager role, which can change **any** past day in its branches. |
| Editing your own attendance | "A Branch Admin cannot modify their own attendance or payroll details." | Not blocked. A manager can override their own day. |
| Staff seeing their attendance | Only if **"Staff can view own attendance"** is on in their profile. | Always visible. |
| After payroll is finalised | Changes don't flow into salary. You have to **Unfinalize Payroll** and finalise again. | Approved or paid salary runs are locked. Corrections go through **Revise**. Attendance edits after that are allowed silently. |

Sources:
- [Setting up Attendance Modes](https://salarybox.in/resources/help-center/setting-up-attendance-modes/)
- [Roles and access](https://salarybox.in/resources/help-center/roles-and-access-in-salarybox-app-web/)
- [Help centre FAQs](https://salarybox.in/resources/help-center/)
- [Zoho People – Present by Default](https://help.zoho.com/portal/en/kb/people/administrator-guide/attendance-management/settings/articles/mark-present-by-default)

## What we'll build

### 1. "Who marks attendance": business default plus per staff

- **Business setting** (Settings → Check-in safety): "Who marks attendance for new staff". The choices are *Staff check in themselves* (the default, same as today) or *Owner or manager marks*.
- **Per staff member** (staff profile → Attendance): the same choice, overriding the business default.
- **Change many at once**: on the Staff list, select staff → "Who marks attendance". This copies SalaryBox's "Update Attendance Modes".
- **Switching in the middle of a day**: punches already made today are kept. The new mode applies from the next action.

### 2. "Present by default": an owner setting, off at first

- **Business setting:** "Present by default". The help line reads: "Staff you mark are counted present unless you mark them absent." It only affects **owner-marked** staff.
- **Off (default):** at 11:59 PM, an owner-marked staff member who isn't marked becomes **Absent**, same as today.
- **On:** an unmarked owner-marked staff member becomes **Present** with `autoMarked: true`. The app shows a small "auto" tag on that day.
- **Days that are never overwritten:** leave, holiday, week off, days before the person joined, and days already marked.
- **Self check-in staff** keep today's rule: no check-in means Absent.

### 3. Quick marking for many staff (Today screen, app and website)

- **"Mark all present"** marks every owner-marked staff member who isn't marked yet for that day. A snackbar then says "48 marked present · Undo".
- **Register-style rows:** owner-marked staff show **P / A / ½** buttons on the row itself. One tap, no sheet. Long-press still opens the full sheet (Leave, Holiday, Week off, reason).
- **Select many → set status**, for example "Holiday" for 6 people.
- **Branch filter.** Managers see only their own branches.
- **Days that are skipped:** leave, holiday and week off are skipped unless they are picked explicitly. Staff who checked in themselves keep their punches.
- **Evening reminder** to owners and managers, at a time the owner sets (default 7:00 PM), and only when someone is still unmarked:
  - Present by default **off:** "12 staff not marked today. They'll be counted absent."
  - Present by default **on:** "48 staff will be counted present. Mark any absences."
- **Mint chat:** "mark everyone present except Ramesh and Suresh". This uses the same bulk endpoint.

### 4. What staff who are marked by the owner see

- **Home:** no check-in button. It shows "Your attendance is marked by your manager" and today's status.
- **No location consent screen and no face setup prompts,** because there's nothing to check in with.
- **Attendance calendar, leave, salary, payslips and "Ask for a fix"** stay as they are today.

### 5. Manager limits (recommended, like SalaryBox's two manager roles)

- Keep **one Manager role**, and add one owner switch per manager: **"Can change past days"**.
  - **Off:** today only. This is like SalaryBox's Attendance Manager.
  - **On:** any day. This is like Advanced Attendance Manager.
- **Starting values:** **new** managers start **off**. **Existing** managers are backfilled **on**, so nobody loses access they use today.
- **The owner** can always change any day.
- **No manager can change their own attendance.** The owner marks it. Today nothing blocks this.
- **Months with approved or paid salary:**
  - Managers can't change them.
  - The owner can, but sees "Salary for Oct is approved. Use Revise to pay the difference."
- **History:** every change is recorded, e.g. "Ravi changed Suresh's 3 Oct from Absent to Present".

## Code changes

### Backend (`backend/src`)

- **Models**
  - `models/staff.ts`: `attendanceMarking: 'self' | 'owner' | null`. `null` follows the business default.
  - `models/core.ts`, Company settings:
    - `defaultAttendanceMarking: 'self' | 'owner'` (default `'self'`)
    - `presentByDefault: boolean` (default `false`)
    - `markReminderTime: string` (default `'19:00'`)
  - `models/core.ts`, Membership: `canEditPastAttendance: boolean` (default `false`), next to `canManageBilling`. A backfill sets it to `true` for current manager memberships.
- **Settings and staff APIs**
  - `modules/company/routes.ts`: add the three settings to the PATCH whitelist (owner only).
  - `modules/employees/routes.ts`:
    - Set `attendanceMarking` on one staff member, and in bulk with `{ employeeIds, attendanceMarking }`.
    - Set the manager's `canEditPastAttendance` (owner only).
- **Attendance** (`modules/attendance/service.ts`)
  - `punch()` and `syncPunches()`: refuse owner-marked staff with `SELF_ATTENDANCE_OFF`.
  - New `bulkMark(ctx, { date, status, employeeIds | 'unmarked', leaveType? })`. It reuses `overrideDay` rules, respects branch scope, skips leave, holiday, week off and punched days, and writes one `attendance.bulk_mark` audit entry with the list of staff.
  - New `POST /attendance/bulk-mark` in `routes.ts` (owner and manager).
  - One permission check, used by `overrideDay`, `clearOverride`, `bulkMark` and the assistant `mark_attendance`:
    - Managers can't change their own record.
    - A manager can change past days only with `canEditPastAttendance`.
    - Approved or paid months are blocked for managers and warn the owner.
  - `closeDay()`: for owner-marked staff with no status and no implicit status, set `present` if `presentByDefault` is on, otherwise `absent`. Both keep `autoMarked: true`.
- **Scheduler** (`jobs/handlers.ts` `schedulerTick`): an evening reminder at `markReminderTime`, made idempotent with `jobState.lastMarkReminderDate`. It goes to owners and managers in scope, and only if someone is unmarked.
- **Mint chat** (`modules/assistant/tools.ts`): add `mark_all_present` with an optional `except` list, or extend `mark_attendance` to take many names.
- **API responses:**
  - The employee profile and `/me` include the effective `attendanceMarking`.
  - The Today/day view includes it per row, plus an unmarked count.
- **Tests** (`backend/test/api.attendance.test.ts`):
  - A punch is blocked for an owner-marked staff member.
  - Bulk mark covers the skip rules, scope and audit entry.
  - `closeDay` gives Present or Absent depending on the setting.
  - A manager can't change their own day.
  - A manager without `canEditPastAttendance` can't change a past day.
  - The reminder is sent once per day.

### Mobile (`mobile/lib`)

- `features/owner/more/rules_screens.dart` `CheckInSafetyScreen`: add "Who marks attendance for new staff", "Present by default" and the reminder time.
- **Staff profile:** a "Who marks attendance" row. For managers, also a "Can change past days" switch (owner only).
- **Staff list:** multi-select → "Who marks attendance".
- **Today screen** (`features/owner/today/today_screen.dart`, `ledger_sheet.dart`, `status_quick_sheet.dart`): add "Mark all present" with Undo, P / A / ½ row buttons, multi-select, and the "auto" tag.
- **Employee home** (`features/employee/home/employee_home_screen.dart`): add the marked-by-manager state.
- **Routing:** `core/router/redirect.dart` skips location consent for owner-marked staff.
- **Offline queue:** `features/employee/punch/punch_queue.dart` drops queued punches quietly when it gets `SELF_ATTENDANCE_OFF`.
- **Strings:** every new line in `core/i18n/strings.dart` in **English and Hindi**.
- **API client:** `core/api/services/attendance_api.dart` gets `bulkMark`.

### Website (`web/`)

- **Settings page:** the three business settings.
- **Staff page:** the per-staff "Who marks attendance" and the manager switch.
- **Attendance page:** "Mark all present" for a day, multi-select and the "auto" tag.

## Order of work

1. **Backend:** models, settings, punch blocking, `bulk-mark`, permission check, `closeDay`, tests.
2. **Mobile Today screen:** Mark all present, row buttons, multi-select, auto tag.
3. **Mobile settings, staff profile, staff list and the employee home screen.**
4. **Website.**
5. **Evening reminder and Mint chat.**

## Later (not in this round)

- **"Staff can view own attendance"** switch, like SalaryBox's.
- **Kiosk mode:** one shared shop phone where staff punch in, as SalaryBox offers for staff without smartphones.
- **Marking from a photo of the paper register** (already in the PRD as V2).
