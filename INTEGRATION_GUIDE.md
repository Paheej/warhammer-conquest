# Crusade Ledger — Expansion Pack Integration Guide

This bundle adds the seven features you asked for to the existing
`warhammer-conquest` repo. Everything is **additive** — no existing
columns are dropped or renamed, no existing pages are deleted. You can
drop these files into your repo, run the migration, and ship.

---

## What's in this bundle

```
supabase/migrations/
  0002_expansion.sql          # ALL database changes — run after 0001_init.sql

lib/
  types.additions.ts          # TypeScript types to APPEND to your lib/types.ts

components/
  NavBar.tsx                  # REPLACES your current NavBar (mobile hamburger)
  ActivityFeed.tsx            # NEW — server component, recent approved submissions
  AdversaryPicker.tsx         # NEW — typeahead search linking opponents to accounts
  BattleSubmitForm.tsx        # NEW — dynamic battle-report form
  FactionMembership.tsx       # NEW — multi-faction manager for dashboard
  AdminPlanetEditor.tsx       # NEW — per-planet image + system allowlist editor

app/
  page.tsx                    # REPLACES your home page (adds activity feed)
  submit/
    page.tsx                  # REPLACES your submit page (loads reference data)
    SubmitPageClient.tsx      # NEW — kind picker + battle/painted/lore forms
  map/
    page.tsx                  # REPLACES your map page
    OrbitalMap.tsx            # NEW — responsive client map using planet.image_url
  dashboard/
    page.tsx                  # REPLACES your dashboard (adds factions + ELO)
  player/[id]/page.tsx        # NEW — public player profile with ELO & chronicle
  admin/planets/page.tsx      # NEW — admin planet editor page
```

---

## Step-by-step install

### 1. Run the migration

Open Supabase → SQL Editor → New query → paste the contents of
`supabase/migrations/0002_expansion.sql` → **Run**.

The migration is idempotent (uses `if not exists` / `on conflict do
update`), so you can safely re-run it. It will:

- Seed `game_systems` with 3rd ed 40K, 10th/11th 40K, BFG, Epic, Video Games.
- Seed `point_schemes` with your exact values
  (1/3/5 losses, 3/5/7 draws, 4/8/16 wins for size-aware systems;
  5/7/16 for BFG/Epic; 1/3/4 for Video Games).
- Seed a starter list of 40K video games (editable in the table).
- Seed `elo_config` with K-factor 32 (main systems), 24 (BFG/Epic), 16 (video).
- Backfill `player_factions` from existing `profiles.faction_id`.
- Replace the `award_points_on_approval` trigger with a richer version
  that awards half-glory to linked adversaries and applies ELO.

### 2. Merge the TypeScript types

Open `lib/types.additions.ts`, copy everything **below the header
comment**, and append it to your existing `lib/types.ts`.

### 3. Drop in the files

Copy every other file in this bundle into the matching path in your
repo. Files marked `REPLACES` above overwrite an existing file.

### 4. Link the new admin page

In your existing `app/admin/page.tsx`, add a link:

```tsx
<Link href="/admin/planets" className="...">Manage Planets</Link>
```

### 5. Deploy

```
git checkout -b expansion
git add .
git commit -m "Expansion: mobile nav, activity feed, multi-system battles, ELO, profiles"
git push -u origin expansion
```

Open a PR, Vercel will preview it automatically.

---

## Feature-by-feature map to your requests

### ① Mobile-friendly layout
- `components/NavBar.tsx` now collapses to a hamburger menu below
  `md:` breakpoint.
- Every new page uses responsive padding (`px-4 sm:px-6`) and
  breakpoint-aware grids.
- The map canvas uses `aspect-ratio: 16/10` so it scales smoothly on
  phones; the side panel stacks below the map on small screens.

### ② Activity feed
- New SQL view `public.activity_feed` exposes approved submissions with
  all the join data the UI needs.
- `components/ActivityFeed.tsx` is a server component that renders the
  feed. Added to the home page under the hero.
- Shows battles, painted models, and lore uniformly — each entry has
  its own colored badge.

### ③ Per-planet game-system restrictions
- `game_systems` (5 rows) defines the editions.
- `point_schemes` holds the loss/draw/win values per (system, size).
  Modify them any time in Supabase and the submit form picks up the
  new values automatically.
- `planet_game_systems` is a join table. **Empty allowlist = all
  systems allowed** (so existing planets keep working with no migration
  needed). Admins pick allowed systems per planet in
  `/admin/planets`.
- The battle submit form hides size/video-game selectors as appropriate:
  - 3rd ed & 10/11th: size selector (small/std/large), 10/11th is default.
  - BFG & Epic: no size selector — uses fixed `n/a` scheme (5/7/16).
  - Video Games: no size selector, adds a "which title?" dropdown, scheme 1/3/4.

### ④ Adversary linking → adversary glory
- `AdversaryPicker` does a live `ilike` search against a
  `searchable_players` view (safe, read-only projection of
  `profiles`).
- When a user is linked, the picker asks which faction they fielded
  (important — opponent may be multi-faction).
- When the submission is approved, the trigger awards
  `ceil(points / 2)` glory to the opponent's faction on the same
  planet, in addition to the submitter's full glory.
- Rule: adversary must belong to a different faction than the submitter
  for this to fire (so you can't farm glory for a teammate playing
  the same faction).

### ⑤ Multi-faction players
- `player_factions` join table with `is_primary` flag.
- `FactionMembership` component on the dashboard lets players join,
  leave, and change their primary faction. `profiles.faction_id` is
  kept in sync with the primary so any code referring to it still
  works.
- Submit form now asks "Fighting as" and offers the dropdown of the
  user's faction memberships.

### ⑥ ELO per (player, system, faction)
- `elo_config` table holds starting rating + K-factor per system —
  **modular**, exactly as you asked. Edit these rows in Supabase to
  tune.
- `elo_ratings` is the per-player-per-system-per-faction scoreboard.
- `calc_elo_delta` is a plpgsql pure function implementing the
  standard ELO formula.
- `get_or_create_elo` (security definer) seeds a row at the config's
  starting value on first write.
- The approval trigger updates BOTH ratings when a battle has a linked
  adversary + result + system + factions on both sides. Submitter's
  `elo_delta` and `adversary_elo_delta` are stamped on the submission
  row for future display.
- `app/player/[id]/page.tsx` is the public profile — visible to any
  visitor, showing the ELO table sorted by rating descending and the
  chronicle of approved deeds.

### ⑦ Planet images
- New `planets.image_url text` column.
- `AdminPlanetEditor` has a URL input (external URL, as you chose).
- The map uses the image as a filled circle when present, falls back
  to the old colored circle otherwise. Broken URLs degrade gracefully
  (`onerror` hides the `<img>`).

---

## Import paths & assumptions

All new files assume your existing import aliases:

- `@/lib/supabase/client`  → `createBrowserClient()`
- `@/lib/supabase/server`  → `createServerClient()` (async)
- `@/lib/types`            → where you append `types.additions.ts`

If your existing files export these under different names, just update
the imports at the top of the new files — the rest will work.

A few assumptions to verify:

- `profiles` has: `id`, `display_name`, `avatar_url`, `is_admin`,
  `faction_id`, `created_at`.
- `submissions` has: `id`, `user_id`, `kind`, `status` (`pending`/
  `approved`/`rejected`), `title`, `description`, `image_url`,
  `planet_id`, `faction_id`, `points`, `created_at`.
- `planets` has: `id`, `name`, `position_x`, `position_y`,
  `claim_threshold`, `controlling_faction_id`.
- `planet_points` has: `(planet_id, faction_id, points)` unique.
- `factions` has: `id`, `name`, `color`.

If any of these column names differ in your schema, the migration will
fail loudly on the first reference — easy to patch.

---

## Testing checklist

1. Run migration → confirm 5 `game_systems` rows, ~15 `point_schemes`
   rows, 5 `elo_config` rows.
2. Sign in, visit `/dashboard`, join a second faction.
3. `/submit` → Battle Report. Verify the form:
   - Defaults to 10/11th edition.
   - Changes size options when switching to BFG or Epic (should vanish).
   - Shows video-game dropdown only on Video Games.
   - Displays correct point value based on size + result.
4. Type an adversary name that matches another registered player —
   suggestion dropdown should appear; clicking links them.
5. Submit → approve in admin queue → check:
   - Submitter gets full glory on the planet.
   - Linked adversary's faction gets half glory on the same planet.
   - Both players get ELO deltas in `elo_ratings`.
6. Visit `/player/<other-user-id>` — profile should render publicly.
7. Admin → `/admin/planets` → set image URL and allowlist BFG only
   on one world. Try to submit a 10/11th battle there — only BFG
   should appear in the dropdown.
8. Resize browser / open on phone — nav collapses, activity feed and
   map stack properly.

---

## Tuning knobs

- **ELO tuning**: edit `elo_config` rows in Supabase. K-factor of 16
  is conservative (slow movement), 32 is standard, 40+ is fast.
- **Point values**: edit `point_schemes`. Changes are picked up live
  by the submit form.
- **New video games**: `insert into public.video_game_titles`.
- **New game systems** (future editions): insert into `game_systems`,
  add matching `point_schemes` rows, add an `elo_config` row.

In the grim darkness of the far future, there is only… several
additional game systems. ✠
