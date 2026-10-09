# Face check: privacy design (for legal review)

StaffMint's optional face check compares a staff member's check-in selfie with a reference photo of their face, so nobody else can mark attendance for them. Unlike the phone-lock check, this **does** process biometric personal data. This note describes what the product does today, so a lawyer can review it against India's Digital Personal Data Protection Act, 2023 (DPDP Act) and the DPDP Rules before any customer turns it on.

## What is collected
- **One reference photo** of the staff member's face, taken in the app with a live-camera blink check.
- **Check-in selfies** (already collected for selfie attendance) are compared with it. The result is stored with the punch: `match`, `unsure`, `mismatch`, `no face`, `more than one face` or `error`, plus a similarity score (0–100).
- **No face templates or embeddings are stored by StaffMint.** The comparison runs on AWS Rekognition (Mumbai region by default) on each check-in, and StaffMint does not create a Rekognition face collection.
- **Set the AWS AI-services opt-out.** By default AWS may use content processed by Rekognition to improve its services. Turn this off with an AWS Organizations "AI services opt-out policy" before going live.

## Purpose
Attendance verification only. The data is not used for anything else and is not shared with anyone except the employer (the shop owner) and the processor (AWS).

## Consent and choice
- **Off by default.** The employer turns it on per company; it is available on paid plans only.
- **Separate, explicit consent from each staff member.** The consent screen is shown before the photo is taken, the box is unticked by default, and consent is recorded with a timestamp (`face.consentAt`) and in the audit log. Consent is asked again on every retake.
- **Refusal has no penalty.** If a staff member says no, they keep checking in with selfie + GPS as before. The consent text says so.
- **Withdrawal at any time** from the app (Profile → Face check → Remove my face photo). The photo is deleted immediately.

## Decisions and the human in the loop
- A non-match **never blocks a check-in and never cuts pay on its own.** The check-in is saved and waits for the owner. The owner sees the approved photo next to that day's selfie and decides.
- Engine errors are only flagged. They never hold a check-in.
- The employer also approves each reference photo before it is used.

## Retention and deletion
- The reference photo is deleted when the staff member withdraws consent, when the owner resets it, or when the staff member is deactivated (leaves the job).
- Check-in selfies follow the existing selfie retention (default 90 days; the owner can set 7–365).
- Photos are stored in private storage behind short-lived signed links.

## Points for the lawyer to confirm
1. The consent text (English and Hindi) in `mobile/lib/core/i18n/strings.dart` (`faceConsentText`) meets the DPDP Act's notice and consent requirements, including naming the processor and the region.
2. Whether employers need their own notice or policy for staff (StaffMint is the processor, the employer is the data fiduciary).
3. Whether consent given in an employment relationship counts as "free" under the Act, and whether we should rely on the "legitimate uses" ground (employment) as well. The design keeps refusal penalty-free to support free consent.
4. The retention periods above.
5. The DPA terms with AWS for Rekognition, data residency, and that the AI-services opt-out is in place.
