# Google Play: field staff location (foreground service + Data safety)

StaffMint shares a field staff member's location with their employer **only while that person is checked in**, from an Android foreground service with a fixed notification. Google Play needs a declaration for the foreground service type **location**, and the Data safety form must say location is collected and shared. This page has everything to paste and the video to record.

## 1. Play Console → App content → Foreground service permissions

**Type:** Location (`FOREGROUND_SERVICE_LOCATION`).

**What the feature does (paste):**

> Employers using StaffMint can mark some employees as "field staff" (for example delivery or sales staff who work outside the shop). After the employee agrees in the app, StaffMint shares their location with the employer while they are checked in for work, so the employer can see where they are, their route for the day and the distance travelled. Sharing starts when the employee checks in and stops when they check out, or 2 hours after their shift ends, whichever is first. A persistent notification ("StaffMint: sharing location · Until you check out") is shown the whole time. The employee can stop sharing at any time from their profile.

**Why it needs a foreground service (paste):**

> The employee starts sharing by checking in, and their location must keep being recorded while the phone is in their pocket and the app is not on screen, for the length of the work shift. A foreground service with a visible notification is the only way to do this that keeps the user informed; the service stops at check-out.

**Is it user-initiated?** Yes: it starts only when the employee checks in, after they agreed on the consent screen.

## 2. The video (30–60 seconds, screen recording on an Android phone)

Record in English with the demo business; no real staff data.

1. **Owner phone (5 s):** Staff → open a staff member → turn on **"Field staff: share location during shift"**. It shows "Waiting for … to agree".
2. **Staff phone (15 s):** the home screen card **"Share location during work?"** → **Read and agree** → the consent screen (scroll through all five lines) → **I agree**.
3. **Staff phone (10 s):** **Check in**. Pull down the notification shade: **"StaffMint: sharing location · Until you check out"**. The home screen shows "Sharing location until you check out".
4. **Owner phone (10 s):** Staff → **Field staff** → the person on the map → tap → their route for the day.
5. **Staff phone (10 s):** **Check out**. The notification disappears. Profile → **Location during work → Stop sharing** (show the confirm dialog, cancel it).

Upload it unlisted on YouTube and paste the link in the declaration.

## 3. Prominent disclosure

The consent screen *is* the prominent disclosure: it is shown before any location is shared, in the employee's language, says what is collected, when, who sees it and how to stop, and needs an explicit "I agree". Screenshot: [`docs/screenshots/tracking/staff-2-consent.jpg`](../screenshots/tracking/staff-2-consent.jpg).

## 4. Data safety form (location part)

| Question | Answer |
|---|---|
| Does the app collect or share location? | Yes: **precise location** and **approximate location** |
| Collected | Yes |
| Shared with third parties | Yes: shared with **the employer** (the business account the employee works for). Not sold, not used for ads |
| Processed ephemerally? | No |
| Required or optional? | **Optional**: only for employees their employer marks as field staff, and only after they agree. Check-in location (at the moment of check-in) is required for attendance |
| Why | **App functionality** (attendance at check-in; field staff location during the shift) |
| Encrypted in transit | Yes (HTTPS) |
| Can users ask for deletion? | Yes. Location points are deleted automatically after 90 days; staff can stop sharing at any time |

## 5. Store listing screenshots (optional but helps review)

- Consent: `docs/screenshots/tracking/staff-2-consent.jpg`
- Sharing while checked in: `docs/screenshots/tracking/staff-3-sharing.jpg`
- Owner live map and day: `docs/screenshots/tracking/owner-4-live-map.jpg`, `owner-5-day.jpg`

## 6. iOS (App Store review notes, when the iPhone app ships)

> Location is used in two ways: once at check-in/check-out to confirm attendance, and, only for employees their employer marks as field staff and who agree in the app, continuously while they are checked in for their work shift. Background location stops automatically at check-out (or 2 hours after the shift ends). The blue location indicator is shown while sharing. The app uses "While Using" permission; sharing starts from the app when the employee checks in.
