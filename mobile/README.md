# StaffMint — mobile app (Flutter)

One Android app (iOS later) with two modes, chosen by the role returned at login:

| Role | Shell |
|---|---|
| `owner`, `manager`, `ca` | **Owner mode** — Home · Staff · Attendance · Salary · More + floating **Mint** assistant |
| `employee` | **Employee mode** — Home (big Check-in/out) · Attendance · Leave · Salary · Profile |

A new phone number logs in as an owner with `needsCompanySetup: true` and goes through the
≤5-screen setup (business → map pin → timings → weekly off → add staff).

The app is built strictly against [`../docs/API.md`](../docs/API.md).

## Requirements

- Flutter 3.44+ / Dart 3.12+ (`flutter --version`)
- Android SDK (API 24+ device/emulator) to run on Android. iOS needs Xcode + CocoaPods.

```bash
cd mobile
flutter pub get
flutter analyze      # must be clean
flutter test         # unit + widget tests
```

## Running against a backend

The API base URL is a compile-time define and **must include `/api/v1`**:

```bash
# Android emulator → backend on your laptop (default if you pass nothing)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000/api/v1

# Real phone on the same Wi-Fi as your laptop
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000/api/v1

# Staging / production (HTTPS)
flutter run --release --dart-define=API_BASE_URL=https://api.staffmint.app/api/v1
```

Optional: `--dart-define=MAP_TILE_URL=https://your-tiles/{z}/{x}/{y}.png` to use a tile server
other than the public OpenStreetMap one (recommended for production — see OSM tile usage policy).

Plain HTTP is allowed **only in debug/profile builds** (`android/app/src/debug|profile/AndroidManifest.xml`).
Release builds require HTTPS.

When the backend's OTP provider is `mock`, `/auth/otp/request` returns `devCode`; the OTP screen shows
it as a "Test mode" hint with a one-tap fill.

## Architecture

```
lib/
  main.dart / app.dart          bootstrap (Hive, prefs, Firebase), MaterialApp.router
  core/
    api/                        Dio client, AuthInterceptor (bearer + refresh on 401 TOKEN_EXPIRED),
                                ApiException, typed services per API area, providers
    models/                     hand-written models with defensive fromJson
    storage/                    secure token storage, session cache, device id
    i18n/                       typed English + Hindi strings (`context.s.xyz`), locale controller
    theme/                      mint brand (#2BB673), Material 3, large text
    router/                     go_router + pure `computeRedirect()` (auth state + role)
    push/                       Firebase Messaging (optional; failures are non-fatal)
    utils/, widgets/            money (paise → ₹12,000), dates, phone, location, map picker…
  features/
    auth/  setup/  assistant/
    owner/{home,staff,attendance,salary,more,shell,providers}
    employee/{home,punch,attendance,leave,salary,profile,consent,shell}
```

- **State**: Riverpod 3 (`Notifier`, `FutureProvider.autoDispose.family`). Automatic provider retries
  are disabled; screens show an error with a retry button and pull-to-refresh.
- **Auth**: tokens in `flutter_secure_storage`; the last `/me` payload is cached so the app (and
  employee check-in) works when started offline. Refresh tokens rotate, so concurrent 401s share one
  `/auth/refresh` call.
- **Device binding**: a UUID generated on first launch is persisted and sent as `deviceId`.
- **Offline punches** (`features/employee/punch/`): if check-in/out fails for network (or 5xx), the
  punch — with its original `clientTime` and `clientPunchId` — goes into a Hive box, survives restarts,
  and is sent through `POST /attendance/sync` on app start, on connectivity regain, on pull-to-refresh
  and before logout. Results are applied per `clientPunchId` (ok/CONFLICT → removed; permanent errors →
  removed + shown to the user; others → retried).
- **i18n**: every user-visible string lives in `lib/core/i18n/strings.dart` in English and Hindi. The
  toggle is on the login screen, More (owner) and Profile (employee); the choice is sent to the API as
  `Accept-Language` and saved with `PATCH /me`.

## Placeholders you must replace before release

| What | Where | Notes |
|---|---|---|
| **Firebase Android config** | `android/app/google-services.json` | Current file is a **fake placeholder** (`project_id: staffmint-placeholder`). Create the Firebase project, add Android app `com.staffmint.app`, download the real file (or run `flutterfire configure`). Until then push is disabled but the app works. |
| **Firebase iOS config** | `ios/Runner/GoogleService-Info.plist` | Not present. Add it via Xcode (target Runner) when iOS is enabled; also enable Push Notifications + Background Modes capabilities and upload an APNs key to Firebase. |
| **Release signing keystore** | `android/key.properties` + a `.jks` file | Not committed (gitignored). Create with `keytool -genkey -v -keystore ~/staffmint-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias staffmint`, then write `android/key.properties` with `storePassword=…`, `keyPassword=…`, `keyAlias=staffmint`, `storeFile=/absolute/path/staffmint-release.jks`. Without it release builds are signed with the debug key. Use Play App Signing. |
| **Production API URL** | `--dart-define=API_BASE_URL=…` | Bake into CI release builds. |
| **Map tiles** | `--dart-define=MAP_TILE_URL=…` | Public OSM tiles are fine for development only. |
| **App icon / splash** | `android/app/src/main/res/mipmap-*`, `ios/Runner/Assets.xcassets` | Still the Flutter defaults (e.g. use `flutter_launcher_icons`). |
| **iOS bundle id / team** | Xcode → Runner → Signing | Bundle id set to `com.staffmint.app`; set your Apple team. |
| google-services Gradle plugin version | `android/settings.gradle.kts` (`4.4.2`) | Bump if `flutterfire configure` / AGP asks for a newer one. |

Android identity: `applicationId = com.staffmint.app`, label **StaffMint**, minSdk ≥ 23 (Flutter's default 24).
Permissions: INTERNET, ACCESS_NETWORK_STATE, CAMERA, ACCESS_FINE/COARSE_LOCATION, RECORD_AUDIO,
READ_CONTACTS, POST_NOTIFICATIONS.

## API contract interpretations

Choices made where `docs/API.md` is not explicit (keep the backend in sync):

- `selfieBase64` is raw base64 of a JPEG (no `data:` prefix), ~640 px, quality 70.
- `/attendance/sync` items are the check-in body plus `type`; per-result `error` may be a string
  (code or message) or `{code, message}` — both are handled. `CONFLICT` is treated as "already stored".
- `GET /export` is called with `delivery=url` (same convention as reports). If the server returns
  `{data:{url}}` it is opened in the browser, otherwise the zip bytes are saved to the device.
- Voice notes are AAC in an MP4 container: `audioMime: "audio/mp4"`.
- `GET /me` for an employee is expected to include `company` (for the selfie setting & name).
- `GET /attendance/month` for an employee returns a single row (their own).
- The payslip PDF link is always re-fetched with `GET /payslips/:id` because `pdfUrl` is short-lived.
