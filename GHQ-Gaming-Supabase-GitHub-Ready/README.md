# GHQ — GamerHeadQuarter

GHQ is a competitive gaming tournament platform built with React and Supabase. The frontend is hosted on Vercel, while Supabase provides authentication, PostgreSQL storage, generated APIs, database functions, triggers, and row-level security.

## Live website

- Website: https://ghq-gaming-mu.vercel.app
- Admin dashboard: https://ghq-gaming-mu.vercel.app/admin

The admin route requires an authenticated account whose profile role is `ADMIN`.

## Technology stack

- React 18 and Vite
- Tailwind CSS
- React Router
- Zustand
- Framer Motion
- Supabase Auth and PostgreSQL
- Vercel hosting

## Implemented functionality

- Email/password registration, login, logout, and persistent sessions
- Automatic user-profile creation after registration
- User profiles and game profiles
- Tournament listings, details, brackets, and free registration
- Announcements and advertisements
- Coin balance, transaction history, achievements, and daily bonus
- Role-based admin dashboard
- Admin management for tournaments, announcements, players, coins, and configuration

Google OAuth is not used. Deposits, withdrawals, paid tournaments, currency conversion, fake users, and room credentials remain disabled in this classroom/demo release.

## Local setup

1. Install Node.js 18 or newer.
2. Install dependencies:

   ```bash
   npm install
   ```

3. Copy `.env.example` to `.env.local` and provide the Supabase project values:

   ```env
   VITE_SUPABASE_URL=https://your-project.supabase.co
   VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
   ```

4. Start the development server:

   ```bash
   npm run dev
   ```

5. Open the local URL displayed by Vite, normally `http://localhost:5173`.

## Supabase setup

For a new Supabase project, run `supabase/schema.sql` in the Supabase SQL Editor. Read `SUPABASE_SETUP.md` before installing the schema.

Only the Supabase publishable key may be used in the browser. Never add a service-role key, database password, or other private secret to this repository.

## Production build

```bash
npm run build
npm run preview
```

Vite generates the production site in `dist/`.

## Vercel deployment

Import the repository into Vercel with these settings:

- Framework preset: Vite
- Install command: `npm install`
- Build command: `npm run build`
- Output directory: `dist`

Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` in the Vercel project environment settings. The included `vercel.json` provides single-page application route fallback.

## Security notes

- Supabase Auth stores and verifies passwords.
- PostgreSQL row-level security controls database access.
- Admin privileges come from the authenticated profile role; there is no default admin password.
- The publishable browser key is not an administrator secret. Database security must still be enforced by RLS policies.
