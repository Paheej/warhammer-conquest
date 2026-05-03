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

The schema is split into two SQL files because PostgreSQL forbids referencing a newly added enum value in the same transaction that adds it. Run them in order:

1. In your Supabase project, open **SQL Editor → New query**.
2. Open `supabase/migrations/0001_schema.sql` from this repo, paste the entire contents into the editor, and click **Run**. You should see "Success. No rows returned." This creates every table, view, trigger, RLS policy, storage bucket, the awards catalogue, the five seeded game systems, and seed factions/planets.
3. Open a fresh **New query**, paste the contents of `supabase/migrations/0002_features.sql`, and **Run**. This adds the loremaster reading-track features and Season Administration RPC.

Both files are idempotent (they use `if not exists` / `on conflict do update`), so you can safely re-run them.

### 3. Set up Cloudinary (image hosting)

1. Sign up free at [cloudinary.com](https://cloudinary.com/users/register/free).
2. From your dashboard, copy your **Cloud Name** (top of the page, e.g. `dxyz1234`).
3. Go to **Settings → Upload → Upload presets → Add upload preset**.
4. Name it (e.g. `campaign-chronicle`), set **Signing Mode** to **Unsigned**, and save. Copy the preset name.

### 4. Enable Discord OAuth (optional but recommended)

1. Go to [discord.com/developers/applications](https://discord.com/developers/applications) → **New Application**.
2. Name it (e.g. "Campaign Chronicle"). Open **OAuth2** in the sidebar.
3. Copy the **Client ID** and **Client Secret**.
4. In Supabase, go to **Authentication → Providers → Discord**, toggle it on, paste both values, and copy the **Callback URL** shown at the top.
5. Back in Discord, paste that Callback URL into **OAuth2 → Redirects** and save.

### 5. Get your Supabase credentials

In your Supabase project, go to **Settings → API** and copy:
- **Project URL** (looks like `https://xxxxx.supabase.co`)
- **anon public** key (long string starting with `eyJ...`)

### 6. Push to GitHub

```bash
git clone https://github.com/Paheej/warhammer-conquest.git campaign-chronicle
cd campaign-chronicle
# Create a new repo on github.com under your account, then:
git remote set-url origin https://github.com/YOUR_USERNAME/campaign-chronicle.git
git push -u origin main
```

### 7. Deploy on Vercel

1. Go to [vercel.com](https://vercel.com), sign in with GitHub.
2. **Add New → Project** → select your `campaign-chronicle` repo.
3. Before deploying, expand **Environment Variables** and add all five:

   | Name | Value |
   |---|---|
   | `NEXT_PUBLIC_SUPABASE_URL` | Your Project URL from step 5 |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Your anon public key from step 5 |
   | `NEXT_PUBLIC_ADMIN_EMAILS` | Comma-separated admin emails, no spaces (e.g. `you@example.com,friend@example.com`) |
   | `NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME` | Your Cloudinary cloud name from step 3 |
   | `NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET` | Your unsigned upload preset name from step 3 |

4. Click **Deploy**. Wait ~90 seconds. You'll get a URL like `campaign-chronicle-xxx.vercel.app`.

### 8. Configure auth redirects

Back in Supabase → **Authentication → URL Configuration**:
- **Site URL:** your Vercel URL (e.g. `https://campaign-chronicle-xxx.vercel.app`).
- **Redirect URLs:** add `https://campaign-chronicle-xxx.vercel.app/auth/callback`.

If you later add a custom domain, repeat this step with the new URL.

### 9. Become admin

- Sign up through the app using an email on your `NEXT_PUBLIC_ADMIN_EMAILS` list.
- The first sign-in auto-promotes you via `/auth/callback`. You'll see an **Admin** link in the nav.
- If it doesn't appear, sign out and back in, or flip `is_admin = true` for your row in `profiles` via the Supabase **Table Editor**.

---

## Local development

```bash
npm install
cp .env.example .env.local
# Fill in .env.local with the same five values from step 7
npm run dev
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

Vercel Hobby + Supabase Free + Cloudinary Free will cover a typical gaming group indefinitely. The image-hosting load lives on Cloudinary (25 GB / 25 GB monthly bandwidth free), so Supabase storage stays empty.

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
components/
  NavBar, ActivityFeed, AdversaryPicker, BattleSubmitForm,
  FactionMembership, AdminPlanetEditor, HonoursBadgeRow, KindBadge, ...
lib/
  types.ts                                # Shared TypeScript types
  admin.ts                                # Email-based admin check
  supabase/{client,server,middleware}.ts  # Supabase clients per context
supabase/migrations/
  0001_schema.sql                         # Tables, RLS, triggers, seed data, awards catalogue
  0002_features.sql                       # Loremaster reading-track + season admin RPC
middleware.ts                             # Session refresh on every request
```

---

In the grim darkness of the far future, there is only war.

✠
