# StaffMint screenshots

Captured from the real apps running against the demo backend (`npm run seed:demo`, plus sample data for today).
The mobile screens are the Flutter app compiled for the browser at a phone-sized viewport (390×844); there is no Android emulator in the build environment, but it is the same code and widgets.

## Mobile app (Owner + Employee): Direction E "Bahi-Khata Modern"

The redesign follows [docs/design](../design/README.md): a warm paper ledger, Hindi first with English hints, four tabs plus a centre mic for Mint, slide-to-confirm for money actions, and a success screen after each one.

| | | |
|---|---|---|
| <img src="mobile/01-login.jpg" width="240"><br>Login: Hindi first, English one tap away | <img src="mobile/02-otp.jpg" width="240"><br>OTP (test code shown in dev mode) | <img src="mobile/03-owner-today.jpg" width="240"><br>Owner Today: the day as a ledger page |
| <img src="mobile/04-owner-needs-you.jpg" width="240"><br>"Needs you" expands into approve / reject cards | <img src="mobile/05-owner-quick-status-sheet.jpg" width="240"><br>Tap any row → 2-tap status sheet with reason chips | <img src="mobile/05b-owner-saved-with-undo.jpg" width="240"><br>Saved at once, with Undo |
| <img src="mobile/06-owner-month-grid.jpg" width="240"><br>Month grid (हा / ले / ग़ / आ codes) | <img src="mobile/07-owner-staff.jpg" width="240"><br>Staff list | <img src="mobile/08-owner-staff-profile.jpg" width="240"><br>Staff profile |
| <img src="mobile/09-owner-salary-day.jpg" width="240"><br>Salary day, step 1 "Check": cash needed + only the flags | <img src="mobile/09c-owner-salary-flag-ok.jpg" width="240"><br>Flag resolved: all staff look fine | <img src="mobile/10-owner-payslip-receipt.jpg" width="240"><br>Payslip as a receipt with the "why" |
| <img src="mobile/11-owner-salary-approved-success.jpg" width="240"><br>Slide to approve → success screen | <img src="mobile/11b-owner-salary-mark-paid.jpg" width="240"><br>Step 3: slide to mark as paid | <img src="mobile/12-owner-more.jpg" width="240"><br>More |
| <img src="mobile/13-mint-sheet.jpg" width="240"><br>Mint: WhatsApp-style chat behind the centre mic | <img src="mobile/13b-mint-answer.jpg" width="240"><br>Mint answers in Devanagari; write actions show a receipt | <img src="mobile/14-mint-confirm-receipt.jpg" width="240"><br>Nothing is saved until "हाँ, कर दो" |
| <img src="mobile/15-mint-which-ramesh.jpg" width="240"><br>"कौन सा Ramesh?" with one-tap choices | <img src="mobile/16-owner-today-english.jpg" width="240"><br>English mode | <img src="mobile/16b-owner-salary-english.jpg" width="240"><br>Salary day in English |
| <img src="mobile/20-employee-home.jpg" width="240"><br>Staff home: one big check-in button | <img src="mobile/21-employee-checkin-success.jpg" width="240"><br>Check-in success (time, selfie, location) | <img src="mobile/22-employee-home-checked-in.jpg" width="240"><br>Checked in → Check out |
| <img src="mobile/23-employee-attendance.jpg" width="240"><br>My attendance calendar + totals | <img src="mobile/24-employee-leave.jpg" width="240"><br>Leave balance | <img src="mobile/24b-employee-apply-leave.jpg" width="240"><br>Apply for leave sheet |
| <img src="mobile/25-employee-salary.jpg" width="240"><br>My salary: running estimate with the maths | <img src="mobile/26-employee-payslip-receipt.jpg" width="240"><br>Payslip receipt with PAID stamp, WhatsApp / PDF | <img src="mobile/27-employee-profile.jpg" width="240"><br>Profile and language |
| <img src="mobile/30-setup-1-business.jpg" width="240"><br>Setup 1/5: business type tiles | <img src="mobile/30b-setup-1-filled.jpg" width="240"><br>Setup 1/5 filled | <img src="mobile/31-setup-2-location.jpg" width="240"><br>Setup 2/5: shop location (map tiles blocked in the screenshot sandbox) |
| <img src="mobile/31b-setup-2-pin.jpg" width="240"><br>Setup 2/5: pin and geofence | <img src="mobile/32-setup-3.jpg" width="240"><br>Setup 3/5: shop hours, prefilled per business type | <img src="mobile/33-setup-4.jpg" width="240"><br>Setup 4/5: weekly off |
| <img src="mobile/34-setup-5-add-staff.jpg" width="240"><br>Setup 5/5: add staff from contacts or by hand |  |  |

### Phone lock at check-in

| | | |
|---|---|---|
| <img src="mobile/40-employee-checkout-phone-lock.jpg" width="240"><br>Check-in result shows the phone-lock outcome (web build has no screen lock, so "No lock on phone") | <img src="mobile/41-owner-today-lock-tag.jpg" width="240"><br>Owner ledger tags a check-in made without the phone lock ("बिना लॉक") | <img src="mobile/43-owner-settings-phone-lock.jpg" width="240"><br>Setting: don't ask / tag me / I approve |

### Face check (optional, off by default)

| | | |
|---|---|---|
| <img src="mobile/50-employee-face-banner.jpg" width="240"><br>Staff home asks to set up face check once the owner turns it on | <img src="mobile/51-employee-face-consent.jpg" width="240"><br>Explicit consent (unticked by default) before any photo is taken | <img src="mobile/52-employee-face-pending.jpg" width="240"><br>Photo waits for the owner; retake or remove any time |
| <img src="mobile/53-owner-face-approve.jpg" width="240"><br>Owner approves the photo or asks for a new one | <img src="mobile/56-owner-face-compare.jpg" width="240"><br>A selfie that doesn't match waits for the owner, shown next to the approved photo (mismatch simulated: the dev face engine is a mock) | <img src="mobile/57-owner-settings-face.jpg" width="240"><br>Setting: off / on (Growth plan and above) |

### Profile

| | | |
|---|---|---|
| <img src="mobile/m1-owner-more-card.jpg" width="240"><br>Owner opens the profile from the More card | <img src="mobile/m2-owner-profile.jpg" width="240"><br>Owner profile: photo, role, business | <img src="mobile/m2b-owner-profile-more.jpg" width="240"><br>Personal details, business, account & security |
| <img src="mobile/m3-staff-profile.jpg" width="240"><br>Staff profile with completeness ring and one-tap chips | <img src="mobile/m3b-staff-profile-work.jpg" width="240"><br>Work details are read-only (set by the owner) | <img src="mobile/m4-staff-bank-sheet.jpg" width="240"><br>Salary account: number typed twice, IFSC or UPI |
| <img src="mobile/m5-staff-bank-card.jpg" width="240"><br>Saved salary account, masked; the owner is notified | | |

### New number: owner or staff?

| | | |
|---|---|---|
| <img src="mobile/n1-who-are-you.jpg" width="240"><br>A number StaffMint doesn't know is asked first | <img src="mobile/n2-ask-employer.jpg" width="240"><br>Staff not added yet: ask the employer, then "Check again" | <img src="mobile/n4-linked-staff.jpg" width="240"><br>After the owner adds the number, "Check again" goes straight to the staff app |

### Roster

| | | |
|---|---|---|
| <img src="roster/en-2-day.jpg" width="240"><br>Roster: one day at a time ([all roster screens](roster/README.md)) | <img src="roster/en-5-send.jpg" width="240"><br>Send to staff, with one-tap fixes | <img src="roster/en-7-my-week.jpg" width="240"><br>Staff home: My week |

### Documents check

| | | |
|---|---|---|
| <img src="verification/en-o2-check-sheet.jpg" width="240"><br>Owner: "Check now" ([all screens](verification/README.md)) | <img src="verification/en-s2-consent.jpg" width="240"><br>Staff agree first | <img src="verification/en-o5-results.jpg" width="240"><br>Results: accept a name or ask again |

## Web dashboard

### My profile
<img src="web/w1-profile.jpg" width="900">

### Profile complete (photo + email saved)
<img src="web/w2-profile-complete.jpg" width="900">

### Change mobile number (code to the new number)
<img src="web/w3-change-mobile.jpg" width="900">

### Profile in Hindi
<img src="web/w4-profile-hindi.jpg" width="900">

### Login
<img src="web/01-login.jpg" width="900">

### OTP
<img src="web/02-otp.jpg" width="900">

### Dashboard
<img src="web/03-dashboard.jpg" width="900">

### Staff (bulk edit)
<img src="web/04-staff.jpg" width="900">

### Attendance month grid
<img src="web/05-attendance.jpg" width="900">

### Payroll + parallel-run compare
<img src="web/06-payroll.jpg" width="900">

### Payslip expanded
<img src="web/07-payroll-payslip-expanded.jpg" width="900">

### Leaves
<img src="web/08-leaves.jpg" width="900">

### Advances & adjustments
<img src="web/09-advances.jpg" width="900">

### Reports
<img src="web/10-reports.jpg" width="900">

### Settings
<img src="web/11-settings.jpg" width="900">

### Billing (dynamic plans)
<img src="web/12-billing.jpg" width="900">

### Audit log
<img src="web/13-audit-log.jpg" width="900">

### Import: upload
<img src="web/14-import.jpg" width="900">

### Import: review flagged rows
<img src="web/15-import-review.jpg" width="900">

### Dashboard in Hindi
<img src="web/16-dashboard-hindi.jpg" width="900">

