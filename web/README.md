# StaffMint — web dashboard

The minimal web dashboard for StaffMint (PRD F11). It only covers jobs that are easier on a big screen:
Excel/CSV import, bulk staff edits, attendance corrections, month-end payroll and the parallel-run compare,
report downloads, settings, billing, audit log and full data export. Everyday work lives in the mobile app.

Stack: Next.js 16 (App Router, TypeScript), Tailwind CSS v4, Vitest. Every page is a client component that calls the
StaffMint API directly (see [`docs/API.md`](../docs/API.md)). The app has no server-side data fetching and no secrets.

## Quick start

```bash
cd web
cp .env.example .env.local      # point at your API if it isn't on http://localhost:4000/api/v1
npm install
npm run dev                     # http://localhost:3000
```

The API must allow the dashboard's origin through CORS. The backend's `CORS_ORIGINS` defaults to `http://localhost:3000`.
To read download filenames, the API must also expose the `Content-Disposition` header
(`Access-Control-Expose-Headers: Content-Disposition`). If it doesn't, downloads still work and use a fallback filename.

| Script | What it does |
|---|---|
| `npm run dev` | Dev server |
| `npm run build` / `npm start` | Production build / server (`node .next/standalone/server.js` also works) |
| `npm run lint` | ESLint (next/core-web-vitals + TypeScript) |
| `npm test` | Vitest unit tests (API client and token refresh, money, import helpers, roles, diff) |
| `npm run typecheck` | `tsc --noEmit` |

### Environment

| Variable | Default | Notes |
|---|---|---|
| `NEXT_PUBLIC_API_BASE_URL` | `http://localhost:4000/api/v1` | Inlined into the browser bundle **at build time**. |

## Docker

```bash
docker build -t staffmint-web --build-arg NEXT_PUBLIC_API_BASE_URL=https://api.staffmint.app/api/v1 .
docker run -p 3000:3000 staffmint-web
```

This is a multi-stage build (deps → build → a slim runner on the `standalone` output). It runs as a non-root user on port 3000.

## Pages

| Route | Roles | What it does |
|---|---|---|
| `/login` | public | Phone, then OTP (shows the `devCode` hint when the mock OTP provider is on), then company setup for new owners: name, type, lat/lng or "use my location", opening/closing time, weekly off. |
| `/` | owner, manager | Today's counts and the needs-action list. Leave and punch approvals work inline. |
| `/import` | owner | **F2.** Upload Excel/CSV or paste text, pick the kind (staff or attendance grid + month) and the source. The review step has a column-mapping table (each change PATCHes the session). Only flagged rows are shown, with inline-editable cells (batched into `fixes`) and a skip option. Commit has an overwrite checkbox. After commit you get a 30 s **Undo** countdown and a 24 h **Rollback**. You can download a sample template CSV (built in the browser). |
| `/staff` | owner, manager | Bulk edit of rate, wage type, designation and shift. Changed rows are saved with one PATCH each, with optional `effectiveFrom`. Also add employee (handles `PLAN_LIMIT`), deactivate and reset device. |
| `/attendance` | owner, manager | Month grid with colour-coded P/A/HD/L/WO/H/– cells. Day view shows punches, flags and approval of pending punches. Override needs a reason. |
| `/payroll` | owner, ca (read-only) | Month and revision picker, create/recompute draft, totals, anomalies, and payslip table with expandable lines plus "explain". Approve, send payslips, mark paid, revise. **Parallel-run compare** shows a diff table with reasons. |
| `/leaves` | owner, manager | List with approve/reject (optional note) and add leave on behalf of an employee. |
| `/advances` | owner | Advances (give, skip a month) and monthly bonus/deduction adjustments. |
| `/reports` | owner, ca | Attendance, salary, advances and late reports as PDF or XLSX. Files are fetched with the auth header and downloaded as a blob. |
| `/settings` | owner | Business profile, rules and settings (`PATCH /company/settings`), plain-language rules, holidays, shifts, branches (lat/lng/radius). |
| `/billing` | owner | Plans from `/billing/plans` (prices come from the API), current subscription, subscribe (redirects to `checkoutUrl`), cancel. |
| `/audit` | owner | Audit log with a before/after field diff (or raw JSON). |

The **Export all data** button (`GET /export`, zip) sits in the sidebar for owner and CA, and also on Reports, Billing and Audit.
Users with the `employee` role see "Please use the StaffMint mobile app".

## Code layout

```
app/login/page.tsx          login + company setup
app/(app)/layout.tsx        authenticated shell (sidebar filtered by role, role guard)
app/(app)/**/page.tsx       pages
components/ui.tsx           Button, Input, Select, Card, Table, Modal, Badge, Alert, ...
components/providers.tsx    i18n (en/hi), toast, auth (tokens + /me)
hooks/useAsync.ts           tiny data-loading / mutation hooks
lib/api.ts                  typed API client: {data} unwrap, ApiError parsing, 401 TOKEN_EXPIRED → /auth/refresh (single-flight, rotation) → retry once
lib/types.ts                types mirroring docs/API.md
lib/money.ts                paise → ₹ with Indian grouping; rupee parsing ("12k", "₹12,000/-", "1.2 lakh")
lib/importHelpers.ts        import review helpers (flagged rows, columns, fixes, skips, undo window, sample CSV)
lib/i18n.ts                 typed English/Hindi dictionary for the main labels
lib/roles.ts                navigation + access per role
```

## Notes and assumptions

- Tokens live in `localStorage` (`staffmint.tokens`). A per-browser `deviceId` (`web-<uuid>`) is sent on OTP verify, with `deviceName: "StaffMint Web"`.
- Fix values for money fields in the import review are sent as the rupee text the owner typed (for example `"12k"` or `"15000"`). The server's import cleaner parses rupee formats. Leave balances are sent as numbers.
- `PATCH /imports/:id` with `skipRows` sends the full list of skipped row indexes each time. Row indexes are 0-based and shown as `#index+1`.
- The Undo countdown uses `undoUntil` but falls back to 30 s from the local commit time if the client and server clocks disagree.
- Audit "Load older entries" passes `before=<at of the oldest loaded entry>`.
- Language: the toggle switches UI labels and sends `Accept-Language` so server strings (rules, explanations) match.
