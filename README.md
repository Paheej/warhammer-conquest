# Campaign Chronicle

A Warhammer 40,000 narrative-campaign tracker for gaming groups. Players log battles, painted units, lore, and reading; admins approve; factions earn glory and conquer planets on an interactive orbital map. Awards transfer between players as rankings shift.

**Live demo:** [campaign-chronicle.app](https://campaign-chronicle.app) — the running instance for my play group.

**Stack:** Next.js 15 (App Router, TypeScript) · Tailwind CSS · Supabase (Auth + Postgres + RLS) · Cloudinary (image hosting) · deploys to Vercel.

**License:** [GPL-3.0](LICENSE).

---

## Features

### Submissions & approval
- **Four user-facing deed types**: Battle Reports, Painted Units, Scribe (lore writing), Loremaster (reading/listening). Plus an admin-only Bonus type.
- **Admin approval queue** — every deed lands as `pending`; nothing posts to leaderboards or planet control until an admin approves it. Trust is enforced by RLS + a Postgres trigger, not client code.
- **Image uploads** to Cloudinary (file or URL paste) for both deed images and player avatars — keeps Supabase storage usage minimal.

### Battles & ELO
- **Five game systems** out of the box: 40K 3rd Edition, 40K 10th/11th Edition, Battlefleet Gothic, Epic 40K, and Video Games. New systems / editions are insertable via the `game_systems` table.
- **Modular point schemes** per (system, size, result) in the `point_schemes` table — change the loss/draw/win values for any system without redeploying.
- **Per-planet game-system allowlists** so admins can restrict, e.g., one world to BFG only. Empty allowlist = all systems allowed.
- **Adversary linking** — typeahead-pick your opponent from the registered player list. Linked battles auto-create a mirror submission for the opponent (opposite result, correct point value, faction glory split correctly).
- **Per-(player, system, faction) ELO ratings** with configurable starting rating and K-factor per system (`elo_config`). Unlinked battles still update the submitter's rating against the system's starting ELO.

### Planets & territorial control
- **Interactive orbital map** — hover a planet to see contesting factions and how close each is to the threshold; click to pin.
- **Automatic control flip** — when a faction crosses a planet's threshold, the planet flips to their control via a Postgres trigger.
- **Planet flip log** records every control change with the deciding submission and top contributor — used by competitive awards (e.g. World Eater).
- **Planet images** rendered on the map; planet flavour text shown in the side panel.

### Awards system
- **33 catalogued honours** across five tiers (Common → Adamantium) and five categories (Combat, Painting, Lore & Narrative, Conquest, Cross-cutting).
- **Auto-evaluated on every approval** — badges like First Blood, Brush Initiate, Seeker of Truth fire as soon as the submission posts.
- **Competitive transfer awards** — Warmaster, Painting Daemon, Keeper of Secrets, Standard Bearer (per-faction), First Among Equals — change hands as rankings shift.
- **Pinnable badges (max 3 per player)** — pinned honours appear on the dashboard, leaderboard, and public profile. The cap is enforced by a DB trigger.
- **Toast notifications** on next page load when a player earns a new badge.

### Leaderboards & profiles
- **Faction leaderboard** with glory totals, wins, units painted, lore counts, planets controlled. Click a faction to filter the commander list to that faction.
- **Commander leaderboard** with pinned-honours strip beside each name (capped at 5, sorted pinned-first then by rarity descending).
- **Public player profiles** at `/player/<id>` — pinned honours, summary stats, per-system ELO ratings, categorized honours grid, and a chronicle of every approved deed.

### Activity feed
- **Home-page feed** of recent approved deeds with thumbnails, kind badges, faction colours, and links into player profiles, planets, and adversaries.
- **Per-deed detail page** at `/submission/<id>` showing the full image and metadata.

### Admin notifications
- Admins get emailed when a submission lands in the queue — capped to at most one email per day no matter how many submissions arrive.
- A weekly digest emails admins every Sunday at noon (UTC) if anything is still outstanding.

### Admin panel (`/admin`)
- Approval queue with point adjustment.
- Inline editing of planets (name, image, description, position, game-system allowlist, controlling faction).
- Inline editing of factions (name, banner colour).
- **Season Administration**: snapshot export (CSV) of every table and view, and a one-click campaign clear that wipes submissions/ELO/awards/planet control while preserving users, factions, planets, and the award catalogue.

### Mobile & UX
- Hamburger nav below `md:` breakpoint; responsive grids and padding on every page.
- Map uses 16:10 aspect-ratio container; side panel stacks below on small screens.

---

## Deploy your own — one-time setup (~25 minutes)

You'll need free accounts on **Supabase**, **Vercel**, and **Cloudinary**, plus a GitHub account.

### 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) and sign in.
2. **New project** → pick a name (e.g. `campaign-chronicle`), a strong database password (save it), and the closest region.
3. Wait ~2 minutes for provisioning.

### 2. Run the database setup

The schema is split into SQL files because PostgreSQL forbids referencing a newly added enum value in the same transaction that adds it. Run them in order:

1. In your Supabase project, open **SQL Editor → New query**.
2. Open `supabase/migrations/0001_schema.sql` from this repo, paste the entire contents into the editor, and click **Run**. You should see "Success. No rows returned." This creates every table, view, trigger, RLS policy, storage bucket, the awards catalogue, the five seeded game systems, and seed factions/planets.
3. Open a fresh **New query**, paste the contents of `supabase/migrations/0002_features.sql`, and **Run**. This adds the loremaster reading-track features and Season Administration RPC.
4. Open a fresh **New query**, paste the contents of `supabase/migrations/0003_fix_award_evaluation_timing.sql`, and **Run**. This fixes an off-by-one in award evaluation so threshold-based badges (First Blood, Brush Initiate, etc.) fire on the first qualifying approval rather than the second.
5. Open a fresh **New query**, paste the contents of `supabase/migrations/0004_vlw_on_profile_insert.sql`, and **Run**. This grants Veteran of the Long War at account-creation time (instead of waiting for a first approval) and backfills the badge for the first 10 existing profiles.
6. Open a fresh **New query**, paste the contents of `supabase/migrations/0015_video_game_per_title_elo.sql`, and **Run**. This splits video-game ELO ratings out by individual title (Dawn of War, Battlesector, etc.) instead of pooling every video game into one rating; the migration wipes existing `video` ELO rows and replays approved video matches in time order to rebuild per-title ratings.
7. Open a fresh **New query**, paste the contents of `supabase/migrations/0018_notification_log.sql`, and **Run**. This adds the table admin-notification emails use to cap themselves to one send per day.

All files are idempotent (they use `if not exists` / `on conflict do update` / `create or replace`), so you can safely re-run them.

### 3. Set up Cloudinary (image hosting)

1. Sign up free at [cloudinary.com](https://cloudinary.com/users/register/free).
2. From your dashboard, copy your **Cloud Name** (top of the page, e.g. `dxyz1234`).
3. Go to **Settings → Upload → Upload presets → Add upload preset**.
4. Name it (e.g. `campaign-chronicle`), set **Signing Mode** to **Unsigned**, and save. Copy the preset name.

### 4. Set up Resend (admin email notifications)

1. Sign up free at [resend.com](https://resend.com).
2. Go to **Domains → Add Domain**, enter your domain, and add the DNS records it gives you (with your registrar/DNS host). Wait for it to verify.
3. Go to **API Keys → Create API Key** and copy it — you'll only see it once.
4. Decide on a sender address on your verified domain (e.g. `notifications@yourdomain.com`).

### 5. Enable Discord OAuth (optional but recommended)

1. Go to [discord.com/developers/applications](https://discord.com/developers/applications) → **New Application**.
2. Name it (e.g. "Campaign Chronicle"). Open **OAuth2** in the sidebar.
3. Copy the **Client ID** and **Client Secret**.
4. In Supabase, go to **Authentication → Providers → Discord**, toggle it on, paste both values, and copy the **Callback URL** shown at the top.
5. Back in Discord, paste that Callback URL into **OAuth2 → Redirects** and save.

### 6. Get your Supabase credentials

In your Supabase project, go to **Settings → API** and copy:
- **Project URL** (looks like `https://xxxxx.supabase.co`)
- **anon public** key (long string starting with `eyJ...`)
- **service_role** key (also long, starts with `eyJ...`) — keep this one secret, it bypasses RLS

### 7. Push to GitHub

```bash
git clone https://github.com/Paheej/warhammer-conquest.git campaign-chronicle
cd campaign-chronicle
# Create a new repo on github.com under your account, then:
git remote set-url origin https://github.com/YOUR_USERNAME/campaign-chronicle.git
git push -u origin main
```

### 8. Deploy on Vercel

1. Go to [vercel.com](https://vercel.com), sign in with GitHub.
2. **Add New → Project** → select your `campaign-chronicle` repo.
3. Generate two random secrets for the next steps (e.g. run `openssl rand -hex 32` twice) — one for `SUPABASE_WEBHOOK_SECRET`, one for `CRON_SECRET`.
4. Before deploying, expand **Environment Variables** and add:

   | Name | Value |
   |---|---|
   | `NEXT_PUBLIC_SUPABASE_URL` | Your Project URL from step 6 |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Your anon public key from step 6 |
   | `SUPABASE_SERVICE_ROLE_KEY` | Your service_role key from step 6 |
   | `NEXT_PUBLIC_ADMIN_EMAILS` | Comma-separated admin emails, no spaces (e.g. `you@example.com,friend@example.com`) |
   | `NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME` | Your Cloudinary cloud name from step 3 |
   | `NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET` | Your unsigned upload preset name from step 3 |
   | `RESEND_API_KEY` | Your Resend API key from step 4 |
   | `RESEND_FROM_EMAIL` | Your sender address from step 4 (e.g. `notifications@yourdomain.com`) |
   | `SUPABASE_WEBHOOK_SECRET` | The first random secret you generated above |
   | `CRON_SECRET` | The second random secret you generated above |
   | `NEXT_PUBLIC_SITE_URL` | Leave blank for now — you'll add it after deploying and getting your URL |

5. Click **Deploy**. Wait ~90 seconds. You'll get a URL like `campaign-chronicle-xxx.vercel.app`.
6. Go back to **Settings → Environment Variables**, set `NEXT_PUBLIC_SITE_URL` to that URL, and redeploy (**Deployments** tab → **⋯** on the latest → **Redeploy**).

### 9. Configure auth redirects

Back in Supabase → **Authentication → URL Configuration**:
- **Site URL:** your Vercel URL (e.g. `https://campaign-chronicle-xxx.vercel.app`).
- **Redirect URLs:** add `https://campaign-chronicle-xxx.vercel.app/auth/callback`.

If you later add a custom domain, repeat this step with the new URL.

### 10. Wire up the new-submission notification webhook

1. In Supabase, go to **Database → Webhooks → Create a new hook**.
2. Name it (e.g. `notify-admins-on-submission`), set **Table** to `submissions`, and check only the **Insert** event.
3. Set **Type** to `HTTP Request`, **Method** to `POST`, and **URL** to `https://<your-vercel-url>/api/webhooks/new-submission`.
4. Under **HTTP Headers**, add `x-webhook-secret` with the same value you set for `SUPABASE_WEBHOOK_SECRET` in Vercel.
5. Save. The weekly digest needs no equivalent setup — it runs on its own via the Vercel Cron Job defined in `vercel.json`.

### 11. Become admin

- Sign up through the app using an email on your `NEXT_PUBLIC_ADMIN_EMAILS` list.
- The first sign-in auto-promotes you via `/auth/callback`. You'll see an **Admin** link in the nav.
- If it doesn't appear, sign out and back in, or flip `is_admin = true` for your row in `profiles` via the Supabase **Table Editor**.

---

## Local development

```bash
npm install
cp .env.example .env.local
# Fill in .env.local with the same values from step 8
npm run dev
```

Admin notification emails only fire from a deployed Supabase Database Webhook and Vercel Cron Job — they won't trigger from `npm run dev`. You can still exercise the routes locally with `curl`:

```bash
curl -X POST http://localhost:3000/api/webhooks/new-submission -H "x-webhook-secret: your-secret"
curl http://localhost:3000/api/cron/weekly-digest -H "authorization: Bearer your-secret"
```

Open [http://localhost:3000](http://localhost:3000). For local Discord OAuth, add `http://localhost:3000/auth/callback` to Supabase's Redirect URLs list.

---

## Trust model

Players submit deeds with a claimed point value. Submissions land in the **admin queue** with `status = 'pending'` and **award zero points**. Only when an admin updates the row to `status = 'approved'` does the Postgres trigger `award_points_on_approval` fire — incrementing faction glory on the planet, splitting glory with a linked adversary, updating ELO ratings, auto-creating the mirror submission, checking the planet threshold, and re-evaluating awards.

Admins can adjust the points value before approving (number input on the queue). The trigger uses the final stored value.

Row Level Security ensures:
- Players can only insert submissions as themselves.
- Non-admins only read their own submissions plus anything `approved`.
- Only admins can write planets, factions, and approve/reject submissions.
- The points-awarding trigger runs as `security definer`, so even though clients can't write to `planet_points`, `elo_ratings`, or `player_awards` directly, approvals still update them.

---

## Tweaking things

- **Point values** per (system, size, result): `point_schemes` table.
- **Add game systems / editions**: insert into `game_systems` + matching `point_schemes` rows + an `elo_config` row.
- **Add video games**: insert into `video_game_titles`.
- **ELO tuning**: edit `elo_config` (K-factor 16 = conservative, 32 = standard, 40+ = fast movement).
- **Seed planets / factions**: insert into `planets` / `factions`, or use the admin UI at `/admin`. Each planet has `position_x` and `position_y` (both 0–1) for its placement on the orbital map.
- **Season reset**: `/admin` → Season Administration → Export snapshot, then Clear campaign. Backs up everything to CSV before wiping submissions, ELO, awards, and planet control.

---

## Cost

Vercel Hobby + Supabase Free + Cloudinary Free + Resend Free will cover a typical gaming group indefinitely. The image-hosting load lives on Cloudinary (25 GB / 25 GB monthly bandwidth free), so Supabase storage stays empty. Resend's free tier (3,000 emails/month, 100/day) comfortably covers one email a day plus a weekly digest.

---

## File layout

```
app/
  layout.tsx, page.tsx, globals.css       # Root, home, styles
  auth/{login,signup,callback}/           # Auth pages + OAuth handler
  submit/                                 # Submission forms (battle, painted, scribe, loremaster)
  admin/                                  # Approval queue, planets, factions, season admin
  dashboard/                              # Player's own stats, factions, honours, history
  map/                                    # Interactive orbital chart
  leaderboard/                            # Faction + commander rankings
  player/[id]/                            # Public player profile
  submission/[id]/                        # Per-deed detail page
  api/webhooks/new-submission/            # Supabase DB webhook target — emails admins (rate-limited)
  api/cron/weekly-digest/                 # Vercel Cron target — Sunday-noon outstanding-queue digest
components/
  NavBar, ActivityFeed, AdversaryPicker, BattleSubmitForm,
  FactionMembership, AdminPlanetEditor, HonoursBadgeRow, KindBadge, ...
lib/
  types.ts                                # Shared TypeScript types
  admin.ts                                # Email-based admin check
  email.ts                                # Resend wrapper — sends to profiles.is_admin recipients
  supabase/{client,server,middleware}.ts  # Supabase clients per context
  supabase/admin.ts                       # Service-role client for server-only routes
supabase/migrations/
  0001_schema.sql                         # Tables, RLS, triggers, seed data, awards catalogue
  0002_features.sql                       # Loremaster reading-track + season admin RPC
  0003_fix_award_evaluation_timing.sql    # AFTER-trigger pass so first-approval badges fire
middleware.ts                             # Session refresh on every request
```

---

In the grim darkness of the far future, there is only war.

✠
