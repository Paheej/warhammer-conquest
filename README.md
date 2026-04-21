# Crusade Ledger

A Warhammer 40,000 campaign tracker for gaming groups. Players log games, painted models, and lore; admins review and approve; factions earn glory and claim planets on an interactive map.

**Stack:** Next.js 15 (App Router, TypeScript) · Tailwind CSS · Supabase (Auth + Postgres + Storage) · Deploys to Vercel.

---

## What's in the box

- **Real user accounts.** Email/password sign-up, plus Discord OAuth.
- **Admin approval queue.** Points don't post until an admin approves — no faking results.
- **Four submission types.** Game reports, painted models, lore, and admin-awarded bonuses.
- **Image uploads.** Stored in Supabase Storage, publicly viewable. Players can also paste image URLs.
- **Planet claim logic.** When a faction's points on a planet cross its threshold, the planet flips to their control automatically (enforced by a Postgres trigger, not client code).
- **Interactive orbital map.** Hover a planet to see which factions are contesting it and how close each is to the threshold.
- **Faction + player leaderboards.**
- **Admin panel** for managing planets, factions, and the approval queue.
- **Grimdark aesthetic.** Cinzel display type, parchment/brass palette, gothic trim.

---

## Deploy it — one-time setup (≈20 minutes)

### 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) and create a free account.
2. Click **New project**. Pick a name (e.g. `crusade-ledger`), a strong database password (save it somewhere), and the closest region.
3. Wait ~2 minutes for provisioning.

### 2. Run the database migration

1. In your Supabase project, open the **SQL Editor** (left sidebar).
2. Click **New query**.
3. Open `supabase/migrations/0001_init.sql` from this repo, copy the entire contents, and paste into the editor.
4. Click **Run**. You should see "Success. No rows returned."

This creates every table, view, trigger, RLS policy, storage bucket, and seeds 8 classic 40K factions and 4 starter planets.

### 3. Enable Discord OAuth (optional but recommended)

1. Go to [discord.com/developers/applications](https://discord.com/developers/applications) → **New Application**.
2. Name it (e.g. "Crusade Ledger"). Go to **OAuth2** in the left sidebar.
3. Copy the **Client ID** and **Client Secret**.
4. In Supabase, go to **Authentication → Providers → Discord**. Toggle it on, paste both values, and copy the **Callback URL** shown at the top.
5. Back in Discord, paste that Callback URL into **OAuth2 → Redirects** and save.

### 4. Get your Supabase credentials

In your Supabase project, go to **Settings → API** and copy:
- **Project URL** (looks like `https://xxxxx.supabase.co`)
- **anon public** key (a long string starting with `eyJ...`)

### 5. Push to GitHub

```bash
cd crusade-ledger
git init
git add .
git commit -m "Initial commit"
# Create a new repo on github.com, then:
git remote add origin https://github.com/YOUR_USERNAME/crusade-ledger.git
git branch -M main
git push -u origin main
```

### 6. Deploy on Vercel

1. Go to [vercel.com](https://vercel.com) and sign in with GitHub.
2. Click **Add New → Project**, select your `crusade-ledger` repo.
3. Before deploying, expand **Environment Variables** and add all three:

   | Name | Value |
   |---|---|
   | `NEXT_PUBLIC_SUPABASE_URL` | Your Project URL from step 4 |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Your anon public key from step 4 |
   | `NEXT_PUBLIC_ADMIN_EMAILS` | Comma-separated emails of admins, e.g. `you@example.com,friend@example.com` |

4. Click **Deploy**. Wait ~90 seconds. You'll get a URL like `crusade-ledger-xxx.vercel.app`.

### 7. Configure auth redirects

Back in Supabase, go to **Authentication → URL Configuration**:
- **Site URL:** your Vercel URL (e.g. `https://crusade-ledger-xxx.vercel.app`)
- **Redirect URLs:** add `https://crusade-ledger-xxx.vercel.app/auth/callback`

If you later add a custom domain, repeat this step with the new URL.

### 8. Become admin

- Sign up through the app using an email on your `NEXT_PUBLIC_ADMIN_EMAILS` list.
- The first sign-in auto-promotes you via `/auth/callback`. You'll see an **Admin** link in the nav.
- If it doesn't appear immediately, sign out and back in, or flip `is_admin = true` for your row in `profiles` via the Supabase **Table Editor**.

---

## Local development

```bash
npm install
cp .env.example .env.local
# Fill in .env.local with the same three values from step 6 above
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). For local Discord OAuth, add `http://localhost:3000/auth/callback` to Supabase's Redirect URLs list.

---

## How the trust model works

Players submit deeds with a claimed point value. Submissions land in the **admin queue** with `status = 'pending'` and **award zero points**. Only when an admin updates the row to `status = 'approved'` does the Postgres trigger `award_points_on_approval` fire, incrementing the faction's points on that planet and checking the threshold.

Admins can adjust points before approving — use the number input in the queue. The trigger uses the final stored `points` value.

Row Level Security ensures:
- Players can only insert submissions as themselves.
- Non-admins can only read their own submissions (plus anything `approved`).
- Only admins can write planets, factions, and approve/reject submissions.
- The points-awarding trigger runs as `security definer`, so even though clients can't write to `planet_points` directly, approvals still update it.

---

## Tweaking things

- **Change point values** shown in the submit dropdown: `lib/types.ts` → `POINT_PRESETS`.
- **Add more seed planets/factions**: edit the `insert into` statements at the bottom of `supabase/migrations/0001_init.sql`, or use the admin UI at `/admin`.
- **Change planet positions on the map**: each planet has `position_x` (0–1, left to right) and `position_y` (0–1, top to bottom). Edit via the admin panel.
- **Switch auth to magic links only**: remove the password fields from `app/auth/login/page.tsx` and `app/auth/signup/page.tsx`, and use `supabase.auth.signInWithOtp({ email })`.

---

## Cost

Vercel Hobby plan and Supabase Free tier will cover a typical gaming group indefinitely. You'd need ~50,000 monthly active users or ~500 MB of model photos before hitting a paid tier.

---

## File layout

```
app/
  layout.tsx, page.tsx, globals.css       # Root, home, styles
  auth/login, auth/signup                 # Auth pages
  auth/callback/route.ts                  # OAuth + email-confirm handler
  submit/                                 # Submission form
  admin/                                  # Approval queue, planet & faction mgmt
  dashboard/                              # Player's own stats & history
  map/                                    # Interactive orbital chart
  leaderboard/                            # Faction + player rankings
components/
  NavBar.tsx, SignOutButton.tsx
lib/
  types.ts                                # Shared TypeScript types
  admin.ts                                # Email-based admin check
  supabase/{client,server,middleware}.ts  # Supabase clients for each context
supabase/migrations/
  0001_init.sql                           # Entire database schema
middleware.ts                             # Session refresh on every request
```

In the grim darkness of the far future, there is only war.

✠
