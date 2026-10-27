# GHQ Supabase setup

The Express/Prisma server is no longer required. Vercel serves the React app, and the app talks directly to Supabase using Row-Level Security.

## 1. Create the database

1. Open your Supabase project.
2. Open **SQL Editor** and choose **New query**.
3. Paste **all 345 lines** of `supabase/schema.sql` into one blank query and click **Run** once.

The script begins by deleting only GHQ's partially created public tables, views, functions, and trigger. It then performs a clean installation. Existing Supabase Auth accounts are preserved and receive rebuilt profile rows. Rerunning it later will erase GHQ tournament/profile data, so use it as a reset script only.

## 2. Authentication

Email/password authentication works immediately. In **Authentication -> URL Configuration**, set:

- Site URL: your final Vercel URL
- Redirect URL: `https://YOUR-VERCEL-DOMAIN.vercel.app/**`

This project intentionally uses only Supabase email/password authentication. No Google OAuth provider or Google Cloud project is required.

## 3. Create the first administrator

Register normally through the website. In SQL Editor, replace the email below and run:

```sql
update public.profiles
set role = 'ADMIN'
where email = 'YOUR_EMAIL@example.com';
```

Do not add an administrator password to SQL or source files.

## 4. Vercel

The supplied `.env.production` already contains this project's public URL and publishable key. These browser values are intentionally public; security is enforced by the SQL policies. Never add a Supabase secret/service-role key to Vercel frontend variables.

Build command: `npm run build`

Output directory: `dist`

## Demo safety

Deposits, withdrawals, paid-tournament registration, currency conversion, fake users, and room credentials are intentionally disabled. Do not enable money handling without server-side validation, audit logs, rate limiting, and a payment-provider review.
