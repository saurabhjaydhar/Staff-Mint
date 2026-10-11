# StaffMint Admin

The app the StaffMint team uses to run the product: businesses, free trials, plans and prices,
settings and feature flags, number recovery, messages, and admin accounts.
Separate from the owners' web app; mobile first (bottom tabs on phones, sidebar on desktop).

## Run locally

```bash
cd backend && npm run admin:create -- --email you@example.com --name "You" --password 'long-pass-123'
cd admin && npm install && npm run dev      # http://localhost:3200
```

Sign in with the email and password, then the 6-digit code. With `EMAIL_PROVIDER=mock` (local),
the code is filled in for you; in production it arrives by email (Resend).

- `NEXT_PUBLIC_API_BASE_URL` — the API, default `http://localhost:4000/api/v1` (build time).
- Add this app's URL to the API's `CORS_ORIGINS`.

## Access

- **Admin** can change things. **View only** can look at everything but not change it.
- Sessions last 12 hours. Changing your password, being disabled or "Sign out everywhere" ends every session.
- 5 wrong passwords lock the account for 15 minutes.
- Every change is in the **Activity log** (who, what, when).

## Checks

```bash
npm run lint && npm run typecheck && npm test && npm run build
```
