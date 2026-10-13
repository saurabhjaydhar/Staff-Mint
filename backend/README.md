# StaffMint backend

Node 22 + Express 5 + TypeScript (ESM) modular monolith. See `../docs/API.md` for the HTTP contract.

```bash
npm install
npm run dev          # API on :4000 (JOBS_DRIVER=inline runs the scheduler in-process)
npm run seed:demo    # demo company: owner 9999900001 / OTP 123456
npm test             # Vitest (uses mongodb-memory-server; set MONGOMS_SYSTEM_BINARY to use a local mongod)
npm run build && npm start     # production
npm run worker                 # BullMQ worker (JOBS_DRIVER=bullmq)
```

## Layout
```
src/
  config/env.ts        all config (Zod-validated, safe dev defaults, prod guard)
  models/              Mongoose schemas (+ tenant guard plugin, append-only audit log, immutable payslips)
  providers/           adapters: otp, messaging, push, llm, speech, storage, pdf, payments, email, geo, analytics
  modules/
    auth company employees imports attendance leave advances payroll payslips
    reports export audit billing assistant messaging notifications dashboard admin config files me
  jobs/                scheduler tick (auto-absent 11:59 PM, 9:30 digest, payroll draft on the 1st, retention purge), BullMQ queue
  scripts/             seed
test/                  golden payroll files, unit + API tests
```

## Background jobs
`scheduler.tick` runs every 5 minutes and checks each company in its own timezone. It is idempotent: progress is tracked in `company.jobState`, and it catches up on missed days.
- Closes yesterday, and closes today at 23:59: anyone with no punch is marked Absent, unless they are on leave, a holiday or a week off. The missing-checkout policy is applied.
- Sends the owner digest at `settings.digestTime` (default 09:30).
- From the 1st, drafts last month's payroll and notifies the owner that salary is ready.
- Around 3 AM, purges selfies older than 90 days and precise locations older than 12 months. Both limits are configurable.

## Dynamic config (no release needed)
- `PUT /api/v1/admin/plans/:code`: prices, limits, features, trial days, optional Razorpay plan IDs (made automatically when missing).
- `PUT /api/v1/admin/flags`: feature flags per plan or company.
- `PUT /api/v1/admin/configs/:key`: e.g. `signup.trialPlan`, `billing.priceLockMonths`, `assistant.pendingTtlMinutes`.

All admin routes need the header `x-admin-key: $ADMIN_API_KEY`.
