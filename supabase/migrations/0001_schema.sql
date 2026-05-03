-- ============================================================================
-- Campaign Chronicle — Database Setup, Part 1 of 2: Schema & Foundations
-- ============================================================================
--
-- Run this entire file in the Supabase SQL Editor first, then run setup_02.sql.
--
-- This is split into two files because PostgreSQL forbids referencing newly
-- added enum values in the same transaction that adds them. Part 1 ends with
-- the 'loremaster' enum value being added; Part 2 then uses it freely.
--
-- This file is a concatenation of historical migrations 0001-0009. The schema
-- evolved over many PRs; later sections refine triggers/views from earlier
-- ones. Running top-to-bottom on a fresh database produces the final state.
-- ============================================================================



-- ############################################################################
-- # 0001_init.sql
-- ############################################################################

-- ============================================================================
-- CRUSADE LEDGER: Warhammer 40K Campaign Tracker
-- Run this entire file in the Supabase SQL editor to set up the database.
-- ============================================================================

-- ---------- FACTIONS ----------
create table public.factions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  color text not null default '#b8892d',
  emblem_url text,
  created_at timestamptz not null default now()
);

-- ---------- PLAYER PROFILES ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  faction_id uuid references public.factions(id) on delete set null,
  email text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------- PLANETS ----------
create table public.planets (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  threshold int not null default 100,
  position_x float not null default 0,
  position_y float not null default 0,
  controlling_faction_id uuid references public.factions(id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------- SUBMISSIONS ----------
create type submission_type as enum ('game', 'model', 'lore', 'bonus');
create type submission_status as enum ('pending', 'approved', 'rejected');

create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles(id) on delete cascade,
  faction_id uuid references public.factions(id) on delete set null,
  target_planet_id uuid references public.planets(id) on delete set null,
  type submission_type not null,
  title text not null,
  body text,
  image_url text,
  opponent_name text,
  result text, -- 'win' | 'loss' | 'draw' for games
  points int not null default 0,
  status submission_status not null default 'pending',
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now()
);

create index on public.submissions (status, created_at desc);
create index on public.submissions (player_id);
create index on public.submissions (faction_id) where status = 'approved';

-- ---------- PLANET POINTS (tracks faction progress toward each planet's threshold) ----------
create table public.planet_points (
  planet_id uuid not null references public.planets(id) on delete cascade,
  faction_id uuid not null references public.factions(id) on delete cascade,
  points int not null default 0,
  primary key (planet_id, faction_id)
);

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- When a submission is approved, award points to the faction on the target planet.
-- If no target planet, the points still count toward the faction total (via a view).
-- If a faction crosses a planet's threshold, that planet becomes theirs.
create or replace function public.award_points_on_approval()
returns trigger
language plpgsql
security definer
as $$
declare
  current_points int;
  planet_threshold int;
  current_controller uuid;
begin
  -- Only act on transitions into 'approved'
  if new.status = 'approved' and (old.status is distinct from 'approved') then
    if new.faction_id is not null and new.target_planet_id is not null and new.points > 0 then
      insert into public.planet_points (planet_id, faction_id, points)
      values (new.target_planet_id, new.faction_id, new.points)
      on conflict (planet_id, faction_id)
      do update set points = planet_points.points + excluded.points;

      select p.threshold, p.controlling_faction_id
        into planet_threshold, current_controller
      from public.planets p where p.id = new.target_planet_id;

      select pp.points into current_points
      from public.planet_points pp
      where pp.planet_id = new.target_planet_id
        and pp.faction_id = new.faction_id;

      if current_points >= planet_threshold and current_controller is distinct from new.faction_id then
        update public.planets
        set controlling_faction_id = new.faction_id,
            claimed_at = now()
        where id = new.target_planet_id;
      end if;
    end if;

    new.reviewed_at := coalesce(new.reviewed_at, now());
  end if;

  return new;
end;
$$;

create trigger trg_award_points
before update on public.submissions
for each row execute function public.award_points_on_approval();

-- Auto-create profile row when a new auth user signs up.
-- Admin flag is set if their email matches the NEXT_PUBLIC_ADMIN_EMAILS list
-- (enforced in app code; also settable directly here for extra safety).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
    new.email
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================================
-- VIEWS for leaderboards
-- ============================================================================

create or replace view public.faction_totals as
  select
    f.id as faction_id,
    f.name as faction_name,
    f.color,
    coalesce(sum(s.points), 0)::int as total_points,
    count(s.id) filter (where s.type = 'game' and s.result = 'win') as wins,
    count(s.id) filter (where s.type = 'model') as models_painted,
    count(s.id) filter (where s.type = 'lore') as lore_submitted,
    count(distinct p.id) as planets_controlled
  from public.factions f
  left join public.submissions s
    on s.faction_id = f.id and s.status = 'approved'
  left join public.planets p
    on p.controlling_faction_id = f.id
  group by f.id, f.name, f.color;

create or replace view public.player_totals as
  select
    pr.id as player_id,
    pr.display_name,
    pr.faction_id,
    f.name as faction_name,
    f.color as faction_color,
    coalesce(sum(s.points), 0)::int as total_points,
    count(s.id) filter (where s.status = 'approved') as approved_count
  from public.profiles pr
  left join public.factions f on f.id = pr.faction_id
  left join public.submissions s
    on s.player_id = pr.id and s.status = 'approved'
  group by pr.id, pr.display_name, pr.faction_id, f.name, f.color;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

alter table public.factions enable row level security;
alter table public.profiles enable row level security;
alter table public.planets enable row level security;
alter table public.submissions enable row level security;
alter table public.planet_points enable row level security;

-- Factions: readable by all authenticated users; writable by admins
create policy "factions readable" on public.factions
  for select using (auth.role() = 'authenticated');
create policy "factions admin write" on public.factions
  for all using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true))
  with check (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

-- Profiles: each user can read all profiles (for leaderboards), update only their own.
create policy "profiles readable" on public.profiles
  for select using (auth.role() = 'authenticated');
create policy "profiles self update" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "profiles admin update" on public.profiles
  for update using (exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.is_admin = true));

-- Planets: readable by all authenticated; writable by admins
create policy "planets readable" on public.planets
  for select using (auth.role() = 'authenticated');
create policy "planets admin write" on public.planets
  for all using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true))
  with check (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

-- Submissions: players can insert their own; read their own or any approved one; admins can read/update all.
create policy "submissions insert own" on public.submissions
  for insert with check (auth.uid() = player_id);
create policy "submissions read own or approved" on public.submissions
  for select using (
    auth.uid() = player_id
    or status = 'approved'
    or exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
  );
create policy "submissions admin update" on public.submissions
  for update using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

-- Planet points: readable by all; only the trigger writes (security definer)
create policy "planet_points readable" on public.planet_points
  for select using (auth.role() = 'authenticated');

-- ============================================================================
-- STORAGE: bucket for submission images
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('submissions', 'submissions', true)
on conflict (id) do nothing;

create policy "authenticated can upload submission images"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'submissions');

create policy "anyone can view submission images"
  on storage.objects for select
  using (bucket_id = 'submissions');

create policy "users can delete their own submission images"
  on storage.objects for delete to authenticated
  using (bucket_id = 'submissions' and owner = auth.uid());

-- ============================================================================
-- SEED DATA: 4 starter planets + classic 40K factions
-- ============================================================================

insert into public.factions (name, color) values
  ('Imperium', '#1a4d6b'),
  ('Chaos', '#6b1616'),
  ('Orks', '#2d5016'),
  ('Eldar', '#7a2a8a'),
  ('Tyranids', '#6b3a8a'),
  ('Necrons', '#2d5a2d'),
  ('T''au Empire', '#b8892d')
on conflict (name) do nothing;

insert into public.planets (name, description, threshold, position_x, position_y) values
  ('Vantarrus Prime', 'A massive hive world covered in towering spires and underhive slums. Once stable, now descending into chaos due to political fractures and cult uprisings.', 100, 0.25, 0.35),
  ('Ferrix-9', 'A heavily mechanized forge world producing Titans, tanks, and munitions for the Imperium.', 80, 0.70, 0.40),
  ('Thalassa Vire', 'A water-covered world with scattered island fortresses and deep-sea relics of unknown origin.', 60, 0.45, 0.65),
  ('Kharon’s Fall', 'A shattered, half-dead world partially phasing in and out of the warp. Time and reality are unstable here.', 150, 0.50, 0.50)
on conflict (name) do nothing;


-- ############################################################################
-- # 0002_expansion.sql
-- ############################################################################

-- =====================================================================
-- 0002_expansion.sql
-- Warhammer Conquest — Expansion pack
--
-- Adds:
--   * Game systems (3rd ed 40k, 10th/11th 40k, BFG, Epic 40k, Video Games)
--   * Modular point schemes (loss/draw/win values per system+size)
--   * Per-planet game-system allowlist
--   * Adversary linking on battle reports -> glory for the linked player
--   * Many-to-many player <-> faction memberships
--   * ELO ratings per (player, game_system, faction) with modular K-factor
--   * Planet image URLs
--   * Activity feed view
--
-- Safe to run on top of 0001_init.sql. All schema changes are additive
-- and use `if not exists` / `add column if not exists`.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Game systems (editions of the game)
-- ---------------------------------------------------------------------
create table if not exists public.game_systems (
  id            text primary key,            -- short slug, e.g. '40k_10'
  name          text not null,               -- display name
  short_name    text not null,               -- short display (for badges)
  supports_size boolean not null default false,      -- show small/std/large?
  supports_video_game boolean not null default false, -- show video game dropdown?
  sort_order    int not null default 0,
  is_default    boolean not null default false,
  created_at    timestamptz not null default now()
);

insert into public.game_systems (id, name, short_name, supports_size, supports_video_game, sort_order, is_default)
values
  ('40k_3',   '3rd Edition 40K',        '3rd Ed',  true,  false, 10, false),
  ('40k_10',  '10th/11th Edition 40K',  '10/11th', true,  false, 20, true),
  ('bfg',     'Battlefleet Gothic',     'BFG',     false, false, 30, false),
  ('epic',    'Epic 40K',               'Epic',    false, false, 40, false),
  ('video',   'Video Games',            'Video',   false, true,  50, false)
on conflict (id) do update set
  name = excluded.name,
  short_name = excluded.short_name,
  supports_size = excluded.supports_size,
  supports_video_game = excluded.supports_video_game,
  sort_order = excluded.sort_order,
  is_default = excluded.is_default;

alter table public.game_systems enable row level security;

drop policy if exists "game_systems readable by all" on public.game_systems;
create policy "game_systems readable by all"
  on public.game_systems for select
  using (true);

drop policy if exists "game_systems writable by admins" on public.game_systems;
create policy "game_systems writable by admins"
  on public.game_systems for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));


-- ---------------------------------------------------------------------
-- 2. Point schemes — modular point values per (system, size, result)
-- ---------------------------------------------------------------------
-- size: 'small' | 'standard' | 'large' | 'n/a'
-- result: 'loss' | 'draw' | 'win'
create table if not exists public.point_schemes (
  id            bigserial primary key,
  game_system_id text not null references public.game_systems(id) on delete cascade,
  game_size     text not null check (game_size in ('small','standard','large','n/a')),
  result        text not null check (result in ('loss','draw','win')),
  points        int  not null,
  unique (game_system_id, game_size, result)
);

-- Seed scheme values per the spec:
-- 40k_3 and 40k_10: size-aware.
--   loss: small=1 / standard=3 / large=5
--   draw: small=3 / standard=5 / large=7
--   win:  small=4 / standard=8 / large=16
-- BFG + Epic: top-tier only (size='n/a'): 5/7/16
-- Video Games: size='n/a': 1/3/4 (loss/draw/win)
insert into public.point_schemes (game_system_id, game_size, result, points) values
  -- 3rd ed 40k
  ('40k_3','small','loss',1),    ('40k_3','small','draw',3),    ('40k_3','small','win',4),
  ('40k_3','standard','loss',3), ('40k_3','standard','draw',5), ('40k_3','standard','win',8),
  ('40k_3','large','loss',5),    ('40k_3','large','draw',7),    ('40k_3','large','win',16),
  -- 10/11th ed 40k
  ('40k_10','small','loss',1),    ('40k_10','small','draw',3),    ('40k_10','small','win',4),
  ('40k_10','standard','loss',3), ('40k_10','standard','draw',5), ('40k_10','standard','win',8),
  ('40k_10','large','loss',5),    ('40k_10','large','draw',7),    ('40k_10','large','win',16),
  -- BFG
  ('bfg','n/a','loss',5), ('bfg','n/a','draw',7), ('bfg','n/a','win',16),
  -- Epic
  ('epic','n/a','loss',5), ('epic','n/a','draw',7), ('epic','n/a','win',16),
  -- Video games
  ('video','n/a','loss',1), ('video','n/a','draw',3), ('video','n/a','win',4)
on conflict (game_system_id, game_size, result) do update set points = excluded.points;

alter table public.point_schemes enable row level security;

drop policy if exists "point_schemes readable by all" on public.point_schemes;
create policy "point_schemes readable by all"
  on public.point_schemes for select
  using (true);

drop policy if exists "point_schemes writable by admins" on public.point_schemes;
create policy "point_schemes writable by admins"
  on public.point_schemes for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));


-- ---------------------------------------------------------------------
-- 3. Video game titles (dropdown for 'video' system)
-- ---------------------------------------------------------------------
create table if not exists public.video_game_titles (
  id         bigserial primary key,
  name       text not null unique,
  sort_order int  not null default 0,
  created_at timestamptz not null default now()
);

insert into public.video_game_titles (name, sort_order) values
  ('Dawn of War', 10),
  ('Dawn of War II', 20),
  ('Dawn of War III', 30),
  ('Space Marine', 40),
  ('Space Marine 2', 50),
  ('Darktide', 60),
  ('Rogue Trader', 70),
  ('Boltgun', 80),
  ('Mechanicus', 90),
  ('Chaos Gate: Daemonhunters', 100),
  ('Battlesector', 110),
  ('Gladius – Relics of War', 120),
  ('Other', 9999)
on conflict (name) do nothing;

alter table public.video_game_titles enable row level security;

drop policy if exists "video_game_titles readable by all" on public.video_game_titles;
create policy "video_game_titles readable by all"
  on public.video_game_titles for select
  using (true);

drop policy if exists "video_game_titles writable by admins" on public.video_game_titles;
create policy "video_game_titles writable by admins"
  on public.video_game_titles for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));


-- ---------------------------------------------------------------------
-- 4. Per-planet game system allowlist
-- ---------------------------------------------------------------------
-- If a planet has NO rows in this table, ALL systems are allowed (default).
-- If it has rows, only those systems are allowed for battle submissions.
create table if not exists public.planet_game_systems (
  planet_id      uuid not null references public.planets(id) on delete cascade,
  game_system_id text not null references public.game_systems(id) on delete cascade,
  primary key (planet_id, game_system_id)
);

alter table public.planet_game_systems enable row level security;

drop policy if exists "planet_game_systems readable by all" on public.planet_game_systems;
create policy "planet_game_systems readable by all"
  on public.planet_game_systems for select
  using (true);

drop policy if exists "planet_game_systems writable by admins" on public.planet_game_systems;
create policy "planet_game_systems writable by admins"
  on public.planet_game_systems for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));


-- ---------------------------------------------------------------------
-- 5. Planet image URL
-- ---------------------------------------------------------------------
alter table public.planets
  add column if not exists image_url text;


-- ---------------------------------------------------------------------
-- 6. Player <-> Faction memberships (many-to-many)
-- ---------------------------------------------------------------------
-- Players keep their original single `faction_id` on profiles (kept for
-- back-compat as their "primary" faction), but can now join additional
-- factions via this table.
create table if not exists public.player_factions (
  user_id    uuid not null references auth.users(id) on delete cascade,
  faction_id uuid not null references public.factions(id) on delete cascade,
  is_primary boolean not null default false,
  joined_at  timestamptz not null default now(),
  primary key (user_id, faction_id)
);

create index if not exists idx_player_factions_user    on public.player_factions(user_id);
create index if not exists idx_player_factions_faction on public.player_factions(faction_id);

alter table public.player_factions enable row level security;

drop policy if exists "player_factions readable by all" on public.player_factions;
create policy "player_factions readable by all"
  on public.player_factions for select
  using (true);

drop policy if exists "player_factions insert self" on public.player_factions;
create policy "player_factions insert self"
  on public.player_factions for insert
  with check (user_id = auth.uid());

drop policy if exists "player_factions update self" on public.player_factions;
create policy "player_factions update self"
  on public.player_factions for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "player_factions delete self" on public.player_factions;
create policy "player_factions delete self"
  on public.player_factions for delete
  using (user_id = auth.uid());

drop policy if exists "player_factions admin override" on public.player_factions;
create policy "player_factions admin override"
  on public.player_factions for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- Backfill: every profile with a faction_id gets a player_factions row
-- marked primary (idempotent).
insert into public.player_factions (user_id, faction_id, is_primary)
select id, faction_id, true
from public.profiles
where faction_id is not null
on conflict (user_id, faction_id) do update set is_primary = true;


-- ---------------------------------------------------------------------
-- 7. Extend submissions with new battle-report fields
-- ---------------------------------------------------------------------
alter table public.submissions
  add column if not exists game_system_id        text references public.game_systems(id),
  add column if not exists game_size             text check (game_size in ('small','standard','large','n/a')),
  add column if not exists video_game_title_id   bigint references public.video_game_titles(id),
  add column if not exists adversary_user_id     uuid references auth.users(id),
  add column if not exists adversary_faction_id  uuid references public.factions(id),
  add column if not exists elo_delta             int default 0,
  add column if not exists adversary_elo_delta   int default 0;
-- Note: submissions.result already exists in the base schema with values
-- 'win' | 'loss' | 'draw' — exactly what we need, so we don't touch it.

create index if not exists idx_submissions_adversary on public.submissions(adversary_user_id);
create index if not exists idx_submissions_system    on public.submissions(game_system_id);
create index if not exists idx_submissions_created   on public.submissions(created_at desc);


-- ---------------------------------------------------------------------
-- 8. ELO configuration (per game system — modular K-factor)
-- ---------------------------------------------------------------------
create table if not exists public.elo_config (
  game_system_id text primary key references public.game_systems(id) on delete cascade,
  starting_elo   int not null default 1200,
  k_factor       int not null default 32,
  updated_at     timestamptz not null default now()
);

insert into public.elo_config (game_system_id, starting_elo, k_factor) values
  ('40k_3',  1200, 32),
  ('40k_10', 1200, 32),
  ('bfg',    1200, 24),
  ('epic',   1200, 24),
  ('video',  1200, 16)
on conflict (game_system_id) do nothing;

alter table public.elo_config enable row level security;

drop policy if exists "elo_config readable by all" on public.elo_config;
create policy "elo_config readable by all"
  on public.elo_config for select
  using (true);

drop policy if exists "elo_config writable by admins" on public.elo_config;
create policy "elo_config writable by admins"
  on public.elo_config for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));


-- ---------------------------------------------------------------------
-- 9. ELO ratings table (per user, game system, faction)
-- ---------------------------------------------------------------------
create table if not exists public.elo_ratings (
  user_id        uuid not null references auth.users(id) on delete cascade,
  game_system_id text not null references public.game_systems(id) on delete cascade,
  faction_id     uuid not null references public.factions(id) on delete cascade,
  rating         int  not null default 1200,
  games_played   int  not null default 0,
  wins           int  not null default 0,
  losses         int  not null default 0,
  draws          int  not null default 0,
  updated_at     timestamptz not null default now(),
  primary key (user_id, game_system_id, faction_id)
);

create index if not exists idx_elo_user        on public.elo_ratings(user_id);
create index if not exists idx_elo_system      on public.elo_ratings(game_system_id);
create index if not exists idx_elo_faction     on public.elo_ratings(faction_id);
create index if not exists idx_elo_rating_desc on public.elo_ratings(rating desc);

alter table public.elo_ratings enable row level security;

drop policy if exists "elo_ratings readable by all" on public.elo_ratings;
create policy "elo_ratings readable by all"
  on public.elo_ratings for select
  using (true);

drop policy if exists "elo_ratings admin writable" on public.elo_ratings;
create policy "elo_ratings admin writable"
  on public.elo_ratings for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));


-- ---------------------------------------------------------------------
-- 10. ELO calculation helpers
-- ---------------------------------------------------------------------
-- Classic ELO update. Score is 1 (win), 0 (loss), 0.5 (draw).
create or replace function public.calc_elo_delta(
  rating_a int,
  rating_b int,
  score_a  numeric,
  k_factor int
) returns int
language plpgsql immutable as $$
declare
  expected_a numeric;
begin
  expected_a := 1.0 / (1.0 + power(10.0, (rating_b - rating_a) / 400.0));
  return round(k_factor * (score_a - expected_a))::int;
end;
$$;


-- Helper: fetch-or-seed an ELO row
create or replace function public.get_or_create_elo(
  p_user_id        uuid,
  p_game_system_id text,
  p_faction_id     uuid
) returns int
language plpgsql security definer as $$
declare
  v_rating int;
  v_start  int;
begin
  select rating into v_rating
  from public.elo_ratings
  where user_id = p_user_id
    and game_system_id = p_game_system_id
    and faction_id = p_faction_id;

  if v_rating is null then
    select coalesce(starting_elo, 1200) into v_start
    from public.elo_config
    where game_system_id = p_game_system_id;

    v_start := coalesce(v_start, 1200);

    insert into public.elo_ratings (user_id, game_system_id, faction_id, rating)
    values (p_user_id, p_game_system_id, p_faction_id, v_start)
    on conflict do nothing;

    v_rating := v_start;
  end if;

  return v_rating;
end;
$$;


-- ---------------------------------------------------------------------
-- 11. Enhanced award-on-approval trigger
-- ---------------------------------------------------------------------
-- Replaces the old trigger. Still awards glory points to the submitter's
-- faction on the planet. Adds:
--   * If adversary_user_id + adversary_faction_id are set on a battle
--     submission, award HALF glory (rounded) to the adversary's faction
--     on the same planet — so they get recognition for showing up.
--   * Update ELO for both players when possible.
--
-- Runs as security definer so RLS doesn't block writes.
create or replace function public.award_points_on_approval()
returns trigger
language plpgsql security definer as $$
declare
  v_threshold   int;
  v_current     int;
  v_new_total   int;
  v_adv_points  int;
  v_submitter_faction uuid;
  v_sub_rating  int;
  v_adv_rating  int;
  v_k           int;
  v_score       numeric;
  v_delta_sub   int;
  v_delta_adv   int;
  v_prev_status text;
begin
  v_prev_status := coalesce(old.status, 'pending');

  -- Only award when transitioning into 'approved'
  if new.status = 'approved' and v_prev_status <> 'approved' then

    -- Figure out the submitter's faction for this submission. Submissions
    -- may carry their own faction_id, else fall back to the submitter's
    -- profile.faction_id.
    v_submitter_faction := new.faction_id;
    if v_submitter_faction is null then
      select faction_id into v_submitter_faction
      from public.profiles where id = new.player_id;
    end if;

    -- 1) Submitter glory on planet
    if new.target_planet_id is not null and v_submitter_faction is not null and coalesce(new.points, 0) > 0 then
      insert into public.planet_points (planet_id, faction_id, points)
      values (new.target_planet_id, v_submitter_faction, new.points)
      on conflict (planet_id, faction_id)
      do update set points = public.planet_points.points + excluded.points;

      -- 2) Adversary glory (half, rounded up) if linked
      if new.adversary_user_id is not null
         and new.adversary_faction_id is not null
         and new.adversary_faction_id <> v_submitter_faction then

        v_adv_points := greatest(1, ceil(new.points / 2.0)::int);

        insert into public.planet_points (planet_id, faction_id, points)
        values (new.target_planet_id, new.adversary_faction_id, v_adv_points)
        on conflict (planet_id, faction_id)
        do update set points = public.planet_points.points + excluded.points;
      end if;

      -- 3) Planet threshold / control flip check
      select threshold, controlling_faction_id into v_threshold, v_submitter_faction
      from public.planets where id = new.target_planet_id;

      select coalesce(max(points),0) into v_current
      from public.planet_points
      where planet_id = new.target_planet_id;

      select faction_id into v_submitter_faction
      from public.planet_points
      where planet_id = new.target_planet_id
      order by points desc
      limit 1;

      if v_current >= coalesce(v_threshold, 0) then
        update public.planets
        set controlling_faction_id = v_submitter_faction
        where id = new.target_planet_id;
      end if;
    end if;

    -- 4) ELO update for battle submissions with an adversary
    if new.type = 'battle'
       and new.game_system_id is not null
       and new.adversary_user_id is not null
       and new.adversary_faction_id is not null
       and new.result is not null
       and new.faction_id is not null then

      select coalesce(k_factor, 32) into v_k
      from public.elo_config
      where game_system_id = new.game_system_id;
      v_k := coalesce(v_k, 32);

      v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id);
      v_adv_rating := public.get_or_create_elo(new.adversary_user_id, new.game_system_id, new.adversary_faction_id);

      v_score := case new.result
        when 'win'  then 1.0
        when 'draw' then 0.5
        when 'loss' then 0.0
      end;

      v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);
      v_delta_adv := -v_delta_sub;

      update public.elo_ratings
        set rating = rating + v_delta_sub,
            games_played = games_played + 1,
            wins   = wins   + (case when new.result = 'win'  then 1 else 0 end),
            losses = losses + (case when new.result = 'loss' then 1 else 0 end),
            draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
            updated_at = now()
      where user_id = new.player_id
        and game_system_id = new.game_system_id
        and faction_id = new.faction_id;

      update public.elo_ratings
        set rating = rating + v_delta_adv,
            games_played = games_played + 1,
            wins   = wins   + (case when new.result = 'loss' then 1 else 0 end),
            losses = losses + (case when new.result = 'win'  then 1 else 0 end),
            draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
            updated_at = now()
      where user_id = new.adversary_user_id
        and game_system_id = new.game_system_id
        and faction_id = new.adversary_faction_id;

      new.elo_delta := v_delta_sub;
      new.adversary_elo_delta := v_delta_adv;
    end if;

  end if;

  return new;
end;
$$;

-- NOTE: the existing trg_award_points trigger from 0001_init.sql already
-- calls award_points_on_approval(). Because we used CREATE OR REPLACE
-- FUNCTION above, the existing trigger automatically picks up the new
-- behaviour. We intentionally do NOT create a second trigger here.


-- ---------------------------------------------------------------------
-- 12. Activity feed view
-- ---------------------------------------------------------------------
-- Exposes only APPROVED submissions for public feed display, joined
-- with display-friendly names.
create or replace view public.activity_feed as
select
  s.id                              as submission_id,
  s.type                            as kind,
  s.status,
  s.created_at,
  s.title,
  s.body                            as description,
  s.image_url,
  s.points,
  s.result,
  s.game_size,
  p.id                              as user_id,
  coalesce(p.display_name, 'Unknown Commander') as display_name,
  null::text                        as avatar_url,
  f.id                              as faction_id,
  f.name                            as faction_name,
  f.color                           as faction_color,
  pl.id                             as planet_id,
  pl.name                           as planet_name,
  gs.id                             as game_system_id,
  gs.short_name                     as game_system_short,
  gs.name                           as game_system_name,
  adv.id                            as adversary_user_id,
  coalesce(adv.display_name, s.opponent_name) as adversary_name,
  advf.name                         as adversary_faction_name,
  advf.color                        as adversary_faction_color,
  vgt.name                          as video_game_name
from public.submissions s
left join public.profiles    p    on p.id = s.player_id
left join public.factions    f    on f.id = s.faction_id
left join public.planets     pl   on pl.id = s.target_planet_id
left join public.game_systems gs  on gs.id = s.game_system_id
left join public.profiles    adv  on adv.id = s.adversary_user_id
left join public.factions    advf on advf.id = s.adversary_faction_id
left join public.video_game_titles vgt on vgt.id = s.video_game_title_id
where s.status = 'approved';

-- Views inherit RLS from their underlying tables, but we expose the
-- approved-only filter at the view level so clients can query it freely.
grant select on public.activity_feed to anon, authenticated;


-- ---------------------------------------------------------------------
-- 13. Searchable profile view (for adversary typeahead)
-- ---------------------------------------------------------------------
create or replace view public.searchable_players as
select
  p.id,
  p.display_name,
  null::text   as avatar_url,
  p.faction_id as primary_faction_id,
  f.name       as primary_faction_name
from public.profiles p
left join public.factions f on f.id = p.faction_id
where p.display_name is not null;

grant select on public.searchable_players to anon, authenticated;


-- ---------------------------------------------------------------------
-- Done.
-- ---------------------------------------------------------------------


-- ############################################################################
-- # 0003_submission_kind_alignment.sql
-- ############################################################################

-- =====================================================================
-- 0003_submission_kind_alignment.sql
-- Warhammer Conquest — align trigger & view with the submission_type enum
--
-- Context:
--   The UI originally inserted its tab-kind values ('battle', 'painted')
--   directly into submissions.type, which is the Postgres enum
--   ('game', 'model', 'lore', 'bonus'). Those strings aren't members
--   of the enum, so the inserts failed. The frontend fix (see the
--   PR fixing issue #2) now maps 'battle' -> 'game' and
--   'painted' -> 'model' before insert, so the DB only ever sees
--   canonical enum values.
--
--   That fix exposes two follow-on problems that this migration closes:
--
--   1. award_points_on_approval's ELO-update branch was guarded by
--      `if new.type = 'battle'`. Now that battle submissions land with
--      type = 'game', that guard never matches and ELO never updates.
--
--   2. The activity_feed view selects `s.type as kind`. Frontend
--      consumers (components/ActivityFeed.tsx KindBadge, player
--      profile page) match on the UI vocabulary ('battle', 'painted').
--      With the DB now storing 'game' / 'model', those badges would
--      fall through to the unknown-kind fallback.
--
-- This migration:
--   * Rewrites award_points_on_approval() with the corrected trigger
--     guard (type = 'game' instead of 'battle'). Everything else in
--     the function is unchanged.
--   * Rewrites the activity_feed view so its `kind` column translates
--     'game' -> 'battle' and 'model' -> 'painted' back into the UI
--     vocabulary. 'lore' and 'bonus' pass through unchanged.
--
-- Safe to run on top of 0002_expansion.sql. Uses CREATE OR REPLACE
-- for both objects, so no data is touched and the existing
-- trg_award_points trigger automatically picks up the new function
-- body (same pattern as 0002).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Rewrite award_points_on_approval with the corrected ELO guard
-- ---------------------------------------------------------------------
create or replace function public.award_points_on_approval()
returns trigger
language plpgsql security definer as $$
declare
  v_threshold   int;
  v_current     int;
  v_new_total   int;
  v_adv_points  int;
  v_submitter_faction uuid;
  v_sub_rating  int;
  v_adv_rating  int;
  v_k           int;
  v_score       numeric;
  v_delta_sub   int;
  v_delta_adv   int;
  v_prev_status text;
begin
  v_prev_status := coalesce(old.status, 'pending');

  -- Only award when transitioning into 'approved'
  if new.status = 'approved' and v_prev_status <> 'approved' then

    -- Figure out the submitter's faction for this submission. Submissions
    -- may carry their own faction_id, else fall back to the submitter's
    -- profile.faction_id.
    v_submitter_faction := new.faction_id;
    if v_submitter_faction is null then
      select faction_id into v_submitter_faction
      from public.profiles where id = new.player_id;
    end if;

    -- 1) Submitter glory on planet
    if new.target_planet_id is not null and v_submitter_faction is not null and coalesce(new.points, 0) > 0 then
      insert into public.planet_points (planet_id, faction_id, points)
      values (new.target_planet_id, v_submitter_faction, new.points)
      on conflict (planet_id, faction_id)
      do update set points = public.planet_points.points + excluded.points;

      -- 2) Adversary glory (half, rounded up) if linked
      if new.adversary_user_id is not null
         and new.adversary_faction_id is not null
         and new.adversary_faction_id <> v_submitter_faction then

        v_adv_points := greatest(1, ceil(new.points / 2.0)::int);

        insert into public.planet_points (planet_id, faction_id, points)
        values (new.target_planet_id, new.adversary_faction_id, v_adv_points)
        on conflict (planet_id, faction_id)
        do update set points = public.planet_points.points + excluded.points;
      end if;

      -- 3) Planet threshold / control flip check
      select threshold, controlling_faction_id into v_threshold, v_submitter_faction
      from public.planets where id = new.target_planet_id;

      select coalesce(max(points),0) into v_current
      from public.planet_points
      where planet_id = new.target_planet_id;

      select faction_id into v_submitter_faction
      from public.planet_points
      where planet_id = new.target_planet_id
      order by points desc
      limit 1;

      if v_current >= coalesce(v_threshold, 0) then
        update public.planets
        set controlling_faction_id = v_submitter_faction
        where id = new.target_planet_id;
      end if;
    end if;

    -- 4) ELO update for battle submissions with an adversary
    --    FIX (0003): guard was 'battle' when the UI inserted that
    --    string literally. With the frontend kind->enum mapping in
    --    place, battle reports now arrive as type = 'game', so the
    --    guard has to match that.
    if new.type = 'game'
       and new.game_system_id is not null
       and new.adversary_user_id is not null
       and new.adversary_faction_id is not null
       and new.result is not null
       and new.faction_id is not null then

      select coalesce(k_factor, 32) into v_k
      from public.elo_config
      where game_system_id = new.game_system_id;
      v_k := coalesce(v_k, 32);

      v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id);
      v_adv_rating := public.get_or_create_elo(new.adversary_user_id, new.game_system_id, new.adversary_faction_id);

      v_score := case new.result
        when 'win'  then 1.0
        when 'draw' then 0.5
        when 'loss' then 0.0
      end;

      v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);
      v_delta_adv := -v_delta_sub;

      update public.elo_ratings
        set rating = rating + v_delta_sub,
            games_played = games_played + 1,
            wins   = wins   + (case when new.result = 'win'  then 1 else 0 end),
            losses = losses + (case when new.result = 'loss' then 1 else 0 end),
            draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
            updated_at = now()
      where user_id = new.player_id
        and game_system_id = new.game_system_id
        and faction_id = new.faction_id;

      update public.elo_ratings
        set rating = rating + v_delta_adv,
            games_played = games_played + 1,
            wins   = wins   + (case when new.result = 'loss' then 1 else 0 end),
            losses = losses + (case when new.result = 'win'  then 1 else 0 end),
            draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
            updated_at = now()
      where user_id = new.adversary_user_id
        and game_system_id = new.game_system_id
        and faction_id = new.adversary_faction_id;

      new.elo_delta := v_delta_sub;
      new.adversary_elo_delta := v_delta_adv;
    end if;

  end if;

  return new;
end;
$$;


-- ---------------------------------------------------------------------
-- 2. Rewrite activity_feed view to translate type -> UI kind
-- ---------------------------------------------------------------------
-- Frontend consumers (components/ActivityFeed.tsx, app/player/[id])
-- match against the UI vocabulary 'battle' / 'painted' / 'lore' /
-- 'bonus'. The DB stores the canonical enum 'game' / 'model' / 'lore'
-- / 'bonus'. Translate in the view so the storage layer stays
-- normalized and the presentation layer doesn't have to know about
-- this alias.
--
-- Postgres refuses CREATE OR REPLACE VIEW when a column's type
-- changes (the existing `kind` column is submission_type; the new
-- CASE expression is text), so we drop and recreate. No other DB
-- object depends on this view, so no CASCADE is needed and we keep
-- the DROP non-cascading to fail loudly if that ever changes.
drop view if exists public.activity_feed;

create view public.activity_feed as
select
  s.id                              as submission_id,
  case s.type
    when 'game'  then 'battle'
    when 'model' then 'painted'
    else s.type::text
  end::text                         as kind,
  s.status,
  s.created_at,
  s.title,
  s.body                            as description,
  s.image_url,
  s.points,
  s.result,
  s.game_size,
  p.id                              as user_id,
  coalesce(p.display_name, 'Unknown Commander') as display_name,
  null::text                        as avatar_url,
  f.id                              as faction_id,
  f.name                            as faction_name,
  f.color                           as faction_color,
  pl.id                             as planet_id,
  pl.name                           as planet_name,
  gs.id                             as game_system_id,
  gs.short_name                     as game_system_short,
  gs.name                           as game_system_name,
  adv.id                            as adversary_user_id,
  coalesce(adv.display_name, s.opponent_name) as adversary_name,
  advf.name                         as adversary_faction_name,
  advf.color                        as adversary_faction_color,
  vgt.name                          as video_game_name
from public.submissions s
left join public.profiles    p    on p.id = s.player_id
left join public.factions    f    on f.id = s.faction_id
left join public.planets     pl   on pl.id = s.target_planet_id
left join public.game_systems gs  on gs.id = s.game_system_id
left join public.profiles    adv  on adv.id = s.adversary_user_id
left join public.factions    advf on advf.id = s.adversary_faction_id
left join public.video_game_titles vgt on vgt.id = s.video_game_title_id
where s.status = 'approved';

grant select on public.activity_feed to anon, authenticated;


-- ---------------------------------------------------------------------
-- Done.
-- ---------------------------------------------------------------------


-- ############################################################################
-- # 0004_linked_battle_mirror_deed.sql
-- ############################################################################

-- ============================================================================
-- 0004_linked_battle_mirror_deed.sql
--
-- Issue #15: when a battle is approved with a linked adversary, the deed
-- only appears on the submitter's profile / leaderboard. The opposing
-- player has no record of it.
--
-- Solution: when an approved linked battle is committed, auto-insert a
-- "mirror" submission belonging to the adversary, with:
--   * opposite result (win <-> loss; draw <-> draw)
--   * points read from point_schemes for (game_system, game_size, mirrored
--     result) — gives the adversary leaderboard credit for the loss/draw
--   * status = 'approved' from the start (so the BEFORE UPDATE
--     award-points trigger does NOT fire on it — no double ELO,
--     no double planet glory, no recursion)
--   * elo_delta = adversary_elo_delta from the original (already computed
--     by the original trigger run)
--   * mirror_of = original.id, so the trigger can skip mirrors defensively
--     and any backfill / future re-runs stay idempotent.
--
-- Rule change at the same time: the adversary's faction now gains planet
-- glory equal to their commander's loss/draw points scheme — NOT
-- ceil(submitter.points / 2). This makes the linked-battle mechanic
-- equivalent to "as if the adversary had submitted their own report":
-- each faction's planet glory mirrors its own commander's result.
-- The backfill at the bottom corrects existing planet_points rows that
-- were credited under the old half-rule.
-- ============================================================================


-- 1. mirror_of column --------------------------------------------------------
alter table public.submissions
  add column if not exists mirror_of uuid
  references public.submissions(id) on delete cascade;

create unique index if not exists submissions_mirror_of_unique_idx
  on public.submissions(mirror_of)
  where mirror_of is not null;


-- 2. opposite_result helper --------------------------------------------------
create or replace function public.opposite_result(r text)
returns text
language sql
immutable
as $$
  select case r
    when 'win'  then 'loss'
    when 'loss' then 'win'
    when 'draw' then 'draw'
    else null
  end;
$$;


-- 3. Replace award_points_on_approval to (a) skip mirrors, (b) award the
-- adversary their own loss/draw points scheme on the planet (not half),
-- and (c) emit a mirror submission when the original transitions into
-- 'approved'.
create or replace function public.award_points_on_approval()
 returns trigger
 language plpgsql
 security definer
as $function$
declare
  v_threshold     int;
  v_current       int;
  v_submitter_faction uuid;
  v_top_faction   uuid;
  v_sub_rating    int;
  v_adv_rating    int;
  v_k             int;
  v_score         numeric;
  v_delta_sub     int;
  v_delta_adv     int;
  v_prev_status   text;
  v_mirror_result text;
  v_mirror_points int;
begin
  -- Mirror rows are passive records of the original; never run ledger
  -- logic on them, even if an admin later edits the row.
  if new.mirror_of is not null then
    return new;
  end if;

  v_prev_status := coalesce(old.status, 'pending');
  v_delta_sub := 0;
  v_delta_adv := 0;
  v_mirror_result := null;
  v_mirror_points := 0;

  if new.status = 'approved' and v_prev_status <> 'approved' then

    -- Submitter's faction (fall back to profile if submission has none).
    v_submitter_faction := new.faction_id;
    if v_submitter_faction is null then
      select faction_id into v_submitter_faction
      from public.profiles where id = new.player_id;
    end if;

    -- Pre-compute mirror points if this is a linked battle. We use the
    -- same number for the adversary's planet glory AND the mirror row.
    if new.type = 'game'
       and new.adversary_user_id is not null
       and new.adversary_faction_id is not null
       and new.result is not null then
      v_mirror_result := public.opposite_result(new.result);
      if v_mirror_result is not null then
        select coalesce(ps.points, 0) into v_mirror_points
        from public.point_schemes ps
        where ps.game_system_id = new.game_system_id
          and ps.game_size      = coalesce(new.game_size, 'n/a')
          and ps.result         = v_mirror_result
        limit 1;
        v_mirror_points := coalesce(v_mirror_points, 0);
      end if;
    end if;

    -- 1) Submitter glory on planet
    if new.target_planet_id is not null and v_submitter_faction is not null and coalesce(new.points, 0) > 0 then
      insert into public.planet_points (planet_id, faction_id, points)
      values (new.target_planet_id, v_submitter_faction, new.points)
      on conflict (planet_id, faction_id)
      do update set points = public.planet_points.points + excluded.points;

      -- 2) Adversary glory equal to their commander's loss/draw points.
      if new.adversary_faction_id is not null
         and new.adversary_faction_id <> v_submitter_faction
         and v_mirror_points > 0 then

        insert into public.planet_points (planet_id, faction_id, points)
        values (new.target_planet_id, new.adversary_faction_id, v_mirror_points)
        on conflict (planet_id, faction_id)
        do update set points = public.planet_points.points + excluded.points;
      end if;

      -- 3) Planet threshold / control flip check
      select threshold into v_threshold
      from public.planets where id = new.target_planet_id;

      select coalesce(max(points),0) into v_current
      from public.planet_points
      where planet_id = new.target_planet_id;

      select faction_id into v_top_faction
      from public.planet_points
      where planet_id = new.target_planet_id
      order by points desc
      limit 1;

      if v_current >= coalesce(v_threshold, 0) then
        update public.planets
        set controlling_faction_id = v_top_faction
        where id = new.target_planet_id;
      end if;
    end if;

    -- 4) ELO update for battle submissions with an adversary
    if new.type = 'game'
       and new.game_system_id is not null
       and new.adversary_user_id is not null
       and new.adversary_faction_id is not null
       and new.result is not null
       and new.faction_id is not null then

      select coalesce(k_factor, 32) into v_k
      from public.elo_config
      where game_system_id = new.game_system_id;
      v_k := coalesce(v_k, 32);

      v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id);
      v_adv_rating := public.get_or_create_elo(new.adversary_user_id, new.game_system_id, new.adversary_faction_id);

      v_score := case new.result
        when 'win'  then 1.0
        when 'draw' then 0.5
        when 'loss' then 0.0
      end;

      v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);
      v_delta_adv := -v_delta_sub;

      update public.elo_ratings
        set rating = rating + v_delta_sub,
            games_played = games_played + 1,
            wins   = wins   + (case when new.result = 'win'  then 1 else 0 end),
            losses = losses + (case when new.result = 'loss' then 1 else 0 end),
            draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
            updated_at = now()
      where user_id = new.player_id
        and game_system_id = new.game_system_id
        and faction_id = new.faction_id;

      update public.elo_ratings
        set rating = rating + v_delta_adv,
            games_played = games_played + 1,
            wins   = wins   + (case when new.result = 'loss' then 1 else 0 end),
            losses = losses + (case when new.result = 'win'  then 1 else 0 end),
            draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
            updated_at = now()
      where user_id = new.adversary_user_id
        and game_system_id = new.game_system_id
        and faction_id = new.adversary_faction_id;

      new.elo_delta := v_delta_sub;
      new.adversary_elo_delta := v_delta_adv;
    end if;

    -- 5) Mirror submission for linked battles.
    -- INSERT does not fire this BEFORE UPDATE trigger, so the mirror is
    -- inert ledger-wise: planet_points and ELO have already been handled
    -- above for both sides. The mirror exists purely so the deed shows up
    -- on the adversary's profile, feed, and faction totals (which sum
    -- submissions.points for status='approved').
    if v_mirror_result is not null
       and not exists (select 1 from public.submissions where mirror_of = new.id) then

      insert into public.submissions (
        player_id,
        faction_id,
        target_planet_id,
        type,
        title,
        body,
        image_url,
        opponent_name,
        result,
        points,
        status,
        reviewed_by,
        reviewed_at,
        review_notes,
        game_system_id,
        game_size,
        video_game_title_id,
        adversary_user_id,
        adversary_faction_id,
        elo_delta,
        adversary_elo_delta,
        mirror_of
      ) values (
        new.adversary_user_id,
        new.adversary_faction_id,
        new.target_planet_id,
        new.type,
        new.title,
        new.body,
        new.image_url,
        null,
        v_mirror_result,
        v_mirror_points,
        'approved',
        new.reviewed_by,
        coalesce(new.reviewed_at, now()),
        new.review_notes,
        new.game_system_id,
        new.game_size,
        new.video_game_title_id,
        new.player_id,
        new.faction_id,
        v_delta_adv,
        v_delta_sub,
        new.id
      );
    end if;

  end if;

  return new;
end;
$function$;


-- 4. Backfill ----------------------------------------------------------------
-- For every existing approved linked battle:
--   (a) correct adversary's planet_points: subtract the old half-credit
--       and add the new mirror-credit.
--   (b) re-run threshold/control flip on each touched planet.
--   (c) insert the mirror submission if missing.
-- Idempotent: skip rows that already have a mirror.
do $$
declare
  s record;
  v_submitter_faction uuid;
  v_mirror_result text;
  v_mirror_points int;
  v_old_half int;
  v_delta int;
  v_threshold int;
  v_current int;
  v_top_faction uuid;
  affected_planets uuid[] := array[]::uuid[];
  pid uuid;
begin
  for s in
    select sub.*
    from public.submissions sub
    where sub.status = 'approved'
      and sub.type = 'game'
      and sub.adversary_user_id is not null
      and sub.adversary_faction_id is not null
      and sub.result is not null
      and sub.mirror_of is null
  loop
    -- Resolve submitter's faction the same way the trigger does.
    v_submitter_faction := s.faction_id;
    if v_submitter_faction is null then
      select faction_id into v_submitter_faction
      from public.profiles where id = s.player_id;
    end if;

    v_mirror_result := public.opposite_result(s.result);
    if v_mirror_result is null then
      continue;
    end if;

    select coalesce(ps.points, 0) into v_mirror_points
    from public.point_schemes ps
    where ps.game_system_id = s.game_system_id
      and ps.game_size      = coalesce(s.game_size, 'n/a')
      and ps.result         = v_mirror_result
    limit 1;
    v_mirror_points := coalesce(v_mirror_points, 0);

    -- (a) planet_points correction. Only applies if the old trigger
    -- actually ran the half-credit branch:
    --   - planet was set
    --   - submitter points > 0
    --   - adversary faction differs from submitter faction
    if s.target_planet_id is not null
       and coalesce(s.points, 0) > 0
       and v_submitter_faction is not null
       and s.adversary_faction_id <> v_submitter_faction then

      v_old_half := greatest(1, ceil(s.points / 2.0)::int);
      v_delta := v_mirror_points - v_old_half;

      if v_delta <> 0 then
        update public.planet_points
        set points = greatest(0, points + v_delta)
        where planet_id = s.target_planet_id
          and faction_id = s.adversary_faction_id;

        if not (s.target_planet_id = any(affected_planets)) then
          affected_planets := affected_planets || s.target_planet_id;
        end if;
      end if;
    end if;

    -- (c) mirror submission
    if not exists (select 1 from public.submissions m where m.mirror_of = s.id) then
      insert into public.submissions (
        player_id, faction_id, target_planet_id, type, title, body, image_url,
        opponent_name, result, points, status, reviewed_by, reviewed_at,
        review_notes, game_system_id, game_size, video_game_title_id,
        adversary_user_id, adversary_faction_id, elo_delta, adversary_elo_delta,
        mirror_of
      ) values (
        s.adversary_user_id, s.adversary_faction_id, s.target_planet_id, s.type,
        s.title, s.body, s.image_url, null, v_mirror_result, v_mirror_points,
        'approved', s.reviewed_by, coalesce(s.reviewed_at, now()), s.review_notes,
        s.game_system_id, s.game_size, s.video_game_title_id, s.player_id,
        s.faction_id, s.adversary_elo_delta, s.elo_delta, s.id
      );
    end if;
  end loop;

  -- (b) re-run threshold/control flip on each touched planet
  foreach pid in array affected_planets loop
    select threshold into v_threshold from public.planets where id = pid;
    select coalesce(max(points), 0) into v_current
    from public.planet_points where planet_id = pid;
    select faction_id into v_top_faction
    from public.planet_points where planet_id = pid
    order by points desc limit 1;

    if v_current >= coalesce(v_threshold, 0) and v_top_faction is not null then
      update public.planets
      set controlling_faction_id = v_top_faction
      where id = pid;
    end if;
  end loop;
end $$;


-- ############################################################################
-- # 0005_profiles_avatar_url.sql
-- ############################################################################

-- ============================================================================
-- 0005_profiles_avatar_url.sql
--
-- Issue #11: configurable user avatars.
--   * Discord OAuth signups: capture `avatar_url` from raw_user_meta_data
--     into profiles.avatar_url on first signup.
--   * Anyone can override via the dashboard profile editor.
--
-- Storage: profiles.avatar_url (text, nullable). The activity_feed and
-- searchable_players views already advertised `avatar_url` to the
-- frontend but were returning placeholder `null::text`. They now expose
-- profiles.avatar_url directly.
-- ============================================================================

-- 1. Column ------------------------------------------------------------------
alter table public.profiles
  add column if not exists avatar_url text;


-- 2. handle_new_user — pull avatar_url from raw_user_meta_data on signup ----
-- Discord OAuth puts the CDN URL at raw_user_meta_data.avatar_url.
-- Email/password signups won't have one; the column simply stays null.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, display_name, email, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
    new.email,
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$;


-- 3. Backfill avatars for existing Discord users ----------------------------
update public.profiles p
set avatar_url = u.raw_user_meta_data->>'avatar_url'
from auth.users u
where u.id = p.id
  and p.avatar_url is null
  and u.raw_user_meta_data ? 'avatar_url';


-- 4. Surface avatar_url through searchable_players --------------------------
create or replace view public.searchable_players as
select
  p.id,
  p.display_name,
  p.avatar_url,
  p.faction_id as primary_faction_id,
  f.name       as primary_faction_name
from public.profiles p
left join public.factions f on f.id = p.faction_id
where p.display_name is not null;

grant select on public.searchable_players to anon, authenticated;


-- 5. Surface avatar_url through activity_feed -------------------------------
-- 0003 dropped + recreated this view because of a column type change. Here
-- we're swapping `null::text` for `p.avatar_url` (also text), so CREATE OR
-- REPLACE would suffice — but we follow the same drop-and-recreate pattern
-- 0003 used to keep the migration trail consistent.
drop view if exists public.activity_feed;

create view public.activity_feed as
select
  s.id                              as submission_id,
  case s.type
    when 'game'  then 'battle'
    when 'model' then 'painted'
    else s.type::text
  end::text                         as kind,
  s.status,
  s.created_at,
  s.title,
  s.body                            as description,
  s.image_url,
  s.points,
  s.result,
  s.game_size,
  p.id                              as user_id,
  coalesce(p.display_name, 'Unknown Commander') as display_name,
  p.avatar_url                      as avatar_url,
  f.id                              as faction_id,
  f.name                            as faction_name,
  f.color                           as faction_color,
  pl.id                             as planet_id,
  pl.name                           as planet_name,
  gs.id                             as game_system_id,
  gs.short_name                     as game_system_short,
  gs.name                           as game_system_name,
  adv.id                            as adversary_user_id,
  coalesce(adv.display_name, s.opponent_name) as adversary_name,
  advf.name                         as adversary_faction_name,
  advf.color                        as adversary_faction_color,
  vgt.name                          as video_game_name
from public.submissions s
left join public.profiles    p    on p.id = s.player_id
left join public.factions    f    on f.id = s.faction_id
left join public.planets     pl   on pl.id = s.target_planet_id
left join public.game_systems gs  on gs.id = s.game_system_id
left join public.profiles    adv  on adv.id = s.adversary_user_id
left join public.factions    advf on advf.id = s.adversary_faction_id
left join public.video_game_titles vgt on vgt.id = s.video_game_title_id
where s.status = 'approved';

grant select on public.activity_feed to anon, authenticated;


-- ############################################################################
-- # 0006_elo_unlinked_adversary.sql
-- ############################################################################

-- ============================================================================
-- 0006_elo_unlinked_adversary.sql
--
-- Issue #28: when a battle is approved against an unlinked adversary
-- (no adversary_user_id, just opponent_name), the submitter's ELO is
-- never updated. The previous guard required both adversary_user_id
-- and adversary_faction_id to be set before any ELO calculation ran.
--
-- Fix: relax the outer ELO guard, then branch:
--   * Linked   -> existing zero-sum behaviour (both sides move).
--   * Unlinked -> rate the submitter against elo_config.starting_elo
--                 (default 1200) as a stand-in for the absent opponent.
--                 Only the submitter's rating moves; adversary_elo_delta
--                 is left NULL.
-- Half-linked rows (one adversary_* column set, the other null) are
-- skipped — the UI cannot produce that state today.
--
-- All other branches (mirror submission, planet glory, threshold flip)
-- are unchanged. Body below is a verbatim copy of 0004's function except
-- section 4.
-- ============================================================================

create or replace function public.award_points_on_approval()
 returns trigger
 language plpgsql
 security definer
as $function$
declare
  v_threshold     int;
  v_current       int;
  v_submitter_faction uuid;
  v_top_faction   uuid;
  v_sub_rating    int;
  v_adv_rating    int;
  v_k             int;
  v_score         numeric;
  v_delta_sub     int;
  v_delta_adv     int;
  v_prev_status   text;
  v_mirror_result text;
  v_mirror_points int;
begin
  -- Mirror rows are passive records of the original; never run ledger
  -- logic on them, even if an admin later edits the row.
  if new.mirror_of is not null then
    return new;
  end if;

  v_prev_status := coalesce(old.status, 'pending');
  v_delta_sub := 0;
  v_delta_adv := 0;
  v_mirror_result := null;
  v_mirror_points := 0;

  if new.status = 'approved' and v_prev_status <> 'approved' then

    -- Submitter's faction (fall back to profile if submission has none).
    v_submitter_faction := new.faction_id;
    if v_submitter_faction is null then
      select faction_id into v_submitter_faction
      from public.profiles where id = new.player_id;
    end if;

    -- Pre-compute mirror points if this is a linked battle. We use the
    -- same number for the adversary's planet glory AND the mirror row.
    if new.type = 'game'
       and new.adversary_user_id is not null
       and new.adversary_faction_id is not null
       and new.result is not null then
      v_mirror_result := public.opposite_result(new.result);
      if v_mirror_result is not null then
        select coalesce(ps.points, 0) into v_mirror_points
        from public.point_schemes ps
        where ps.game_system_id = new.game_system_id
          and ps.game_size      = coalesce(new.game_size, 'n/a')
          and ps.result         = v_mirror_result
        limit 1;
        v_mirror_points := coalesce(v_mirror_points, 0);
      end if;
    end if;

    -- 1) Submitter glory on planet
    if new.target_planet_id is not null and v_submitter_faction is not null and coalesce(new.points, 0) > 0 then
      insert into public.planet_points (planet_id, faction_id, points)
      values (new.target_planet_id, v_submitter_faction, new.points)
      on conflict (planet_id, faction_id)
      do update set points = public.planet_points.points + excluded.points;

      -- 2) Adversary glory equal to their commander's loss/draw points.
      if new.adversary_faction_id is not null
         and new.adversary_faction_id <> v_submitter_faction
         and v_mirror_points > 0 then

        insert into public.planet_points (planet_id, faction_id, points)
        values (new.target_planet_id, new.adversary_faction_id, v_mirror_points)
        on conflict (planet_id, faction_id)
        do update set points = public.planet_points.points + excluded.points;
      end if;

      -- 3) Planet threshold / control flip check
      select threshold into v_threshold
      from public.planets where id = new.target_planet_id;

      select coalesce(max(points),0) into v_current
      from public.planet_points
      where planet_id = new.target_planet_id;

      select faction_id into v_top_faction
      from public.planet_points
      where planet_id = new.target_planet_id
      order by points desc
      limit 1;

      if v_current >= coalesce(v_threshold, 0) then
        update public.planets
        set controlling_faction_id = v_top_faction
        where id = new.target_planet_id;
      end if;
    end if;

    -- 4) ELO update for game submissions.
    -- Linked: both ratings move (zero-sum). Unlinked: only the submitter
    -- moves, rated against elo_config.starting_elo as a stand-in for the
    -- absent opponent. Half-linked rows (only one of adversary_user_id /
    -- adversary_faction_id set) are skipped.
    if new.type = 'game'
       and new.game_system_id is not null
       and new.result is not null
       and new.faction_id is not null then

      select coalesce(k_factor, 32) into v_k
      from public.elo_config
      where game_system_id = new.game_system_id;
      v_k := coalesce(v_k, 32);

      v_score := case new.result
        when 'win'  then 1.0
        when 'draw' then 0.5
        when 'loss' then 0.0
      end;

      if new.adversary_user_id is not null
         and new.adversary_faction_id is not null then

        v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id);
        v_adv_rating := public.get_or_create_elo(new.adversary_user_id, new.game_system_id, new.adversary_faction_id);

        v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);
        v_delta_adv := -v_delta_sub;

        update public.elo_ratings
          set rating = rating + v_delta_sub,
              games_played = games_played + 1,
              wins   = wins   + (case when new.result = 'win'  then 1 else 0 end),
              losses = losses + (case when new.result = 'loss' then 1 else 0 end),
              draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
              updated_at = now()
        where user_id = new.player_id
          and game_system_id = new.game_system_id
          and faction_id = new.faction_id;

        update public.elo_ratings
          set rating = rating + v_delta_adv,
              games_played = games_played + 1,
              wins   = wins   + (case when new.result = 'loss' then 1 else 0 end),
              losses = losses + (case when new.result = 'win'  then 1 else 0 end),
              draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
              updated_at = now()
        where user_id = new.adversary_user_id
          and game_system_id = new.game_system_id
          and faction_id = new.adversary_faction_id;

        new.elo_delta := v_delta_sub;
        new.adversary_elo_delta := v_delta_adv;

      elsif new.adversary_user_id is null
            and new.adversary_faction_id is null then

        v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id);

        select coalesce(starting_elo, 1200) into v_adv_rating
        from public.elo_config
        where game_system_id = new.game_system_id;
        v_adv_rating := coalesce(v_adv_rating, 1200);

        v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);

        update public.elo_ratings
          set rating = rating + v_delta_sub,
              games_played = games_played + 1,
              wins   = wins   + (case when new.result = 'win'  then 1 else 0 end),
              losses = losses + (case when new.result = 'loss' then 1 else 0 end),
              draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
              updated_at = now()
        where user_id = new.player_id
          and game_system_id = new.game_system_id
          and faction_id = new.faction_id;

        new.elo_delta := v_delta_sub;
      end if;
    end if;

    -- 5) Mirror submission for linked battles.
    -- INSERT does not fire this BEFORE UPDATE trigger, so the mirror is
    -- inert ledger-wise: planet_points and ELO have already been handled
    -- above for both sides. The mirror exists purely so the deed shows up
    -- on the adversary's profile, feed, and faction totals (which sum
    -- submissions.points for status='approved').
    if v_mirror_result is not null
       and not exists (select 1 from public.submissions where mirror_of = new.id) then

      insert into public.submissions (
        player_id,
        faction_id,
        target_planet_id,
        type,
        title,
        body,
        image_url,
        opponent_name,
        result,
        points,
        status,
        reviewed_by,
        reviewed_at,
        review_notes,
        game_system_id,
        game_size,
        video_game_title_id,
        adversary_user_id,
        adversary_faction_id,
        elo_delta,
        adversary_elo_delta,
        mirror_of
      ) values (
        new.adversary_user_id,
        new.adversary_faction_id,
        new.target_planet_id,
        new.type,
        new.title,
        new.body,
        new.image_url,
        null,
        v_mirror_result,
        v_mirror_points,
        'approved',
        new.reviewed_by,
        coalesce(new.reviewed_at, now()),
        new.review_notes,
        new.game_system_id,
        new.game_size,
        new.video_game_title_id,
        new.player_id,
        new.faction_id,
        v_delta_adv,
        v_delta_sub,
        new.id
      );
    end if;

  end if;

  return new;
end;
$function$;


-- ############################################################################
-- # 0007_awards.sql
-- ############################################################################

-- ============================================================================
-- 0007_awards.sql
--
-- Issue #26: Awards & Honours system. All awards derive from already-approved
-- submission data so the trust model is preserved (no award without a real
-- approved deed).
--
-- Phase 1 scope:
--   * `awards` (catalogue) and `player_awards` (instances) tables, with RLS.
--   * Featured-pinning cap of 3 enforced via constraint trigger.
--   * 27 awards seeded (20 auto-evaluated; 7 deferred to Phase 2).
--   * `evaluate_player_awards(uuid)` runs every grantable check for a player.
--   * `award_points_on_approval` trigger now calls the evaluator for the
--     submitter, and for the linked adversary after the mirror is inserted,
--     so both sides receive their badges from a single approval.
--
-- Phase 2 will add: cross-player competitive awards (warmaster, painting_daemon,
-- keeper_of_secrets, standard_bearer, first_among_equals), planet_flip_log
-- table, and the world_eater + crusade_architect awards.
-- ============================================================================

-- ---------- AWARDS CATALOGUE ----------
create table public.awards (
  id          uuid primary key default gen_random_uuid(),
  key         text unique not null,
  name        text not null,
  description text not null,
  hint        text not null,
  tier        text not null check (tier in ('common','honoured','legendary','adamantium')),
  category    text not null check (category in ('combat','painting','lore','conquest','cross')),
  icon        text not null,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

-- ---------- PLAYER AWARDS (instances) ----------
create table public.player_awards (
  id          uuid primary key default gen_random_uuid(),
  player_id   uuid not null references public.profiles(id) on delete cascade,
  award_id    uuid not null references public.awards(id)  on delete cascade,
  earned_at   timestamptz not null default now(),
  is_featured boolean not null default false,
  notified    boolean not null default false,
  unique (player_id, award_id)
);

create index on public.player_awards (player_id, notified);
create index on public.player_awards (player_id) where is_featured;

-- Cap featured awards at 3 per player.
create or replace function public.enforce_featured_award_cap()
returns trigger language plpgsql as $$
begin
  if new.is_featured and (
    select count(*) from public.player_awards
    where player_id = new.player_id and is_featured and id <> new.id
  ) >= 3 then
    raise exception 'A player may pin at most 3 featured awards';
  end if;
  return new;
end $$;

create trigger trg_featured_cap
before insert or update on public.player_awards
for each row when (new.is_featured)
execute function public.enforce_featured_award_cap();

-- ---------- RLS ----------
alter table public.awards         enable row level security;
alter table public.player_awards  enable row level security;

create policy "awards readable" on public.awards
  for select using (auth.role() = 'authenticated');

create policy "player_awards readable" on public.player_awards
  for select using (auth.role() = 'authenticated');

-- Owners can update their own rows (covers notified flag and is_featured pin).
-- INSERT and DELETE go through SECURITY DEFINER evaluator only.
create policy "player_awards self update" on public.player_awards
  for update using (auth.uid() = player_id) with check (auth.uid() = player_id);

-- ============================================================================
-- SEED CATALOGUE
-- ============================================================================
insert into public.awards (key, name, description, hint, tier, category, icon, sort_order) values
  -- Combat
  ('first_blood',            'First Blood',            'Recorded your first approved battle.',                    'Cross blades for the first time.',                          'common',     'combat',   '🩸',  100),
  ('veteran',                'Veteran',                'Three approved battles to your name.',                    'Three battles, three witnesses.',                           'common',     'combat',   '🪖',  101),
  ('honored_of_the_chapter', 'Honored of the Chapter', 'Ten approved battles. The Chapter remembers.',            'Ten battles will earn the Chapter''s notice.',              'honoured',   'combat',   '🏆',  102),
  ('warmaster',              'Warmaster',              'Twenty battles fought, and none more bloody than yours.', 'Lead the host in war beyond all peers.',                    'legendary',  'combat',   '💀',  103),
  ('double_tap',             'Double Tap',             'Three consecutive victories.',                            'Three in a row will not be forgotten.',                     'common',     'combat',   '🔫',  110),
  ('overkill',               'Overkill',               'Five consecutive victories.',                             'Five wins without a stumble.',                              'honoured',   'combat',   '💥',  111),
  ('exterminatus',           'Exterminatus',           'Ten consecutive victories. The galaxy itself trembles.',  'Ten battles, ten worlds undone.',                           'adamantium', 'combat',   '☠️',  112),
  ('david',                  'David',                  'Defeated a higher-rated adversary in a sanctioned duel.', 'Strike down one greater than yourself.',                    'honoured',   'combat',   '🗡',  120),
  ('nemesis',                'Nemesis',                'Defeated the same opponent three times.',                 'Hunt one foe across many battlefields.',                    'legendary',  'combat',   '👹',  121),

  -- Painting
  ('brush_initiate',         'Brush Initiate',         'Your first approved painted unit.',                       'The first stroke of paint upon the host.',                  'common',     'painting', '🖌',  200),
  ('production_painter',     'Production Painter',     'Three approved painted units.',                           'Three units fully painted will mark you.',                  'common',     'painting', '🎨',  201),
  ('master_artisan',         'Master Artisan',         'Ten approved painted units. A force ready for war.',      'Ten units finished is the mark of a true artisan.',         'honoured',   'painting', '👑',  202),
  ('painting_daemon',        'Painting Daemon',        'Twenty units painted, and none more prolific than you.',  'Paint beyond all rival hobbyists.',                         'legendary',  'painting', '😈',  203),
  ('the_long_vigil',         'The Long Vigil',         'Painting submissions in three consecutive months.',       'Keep the brush warm three months without pause.',           'honoured',   'painting', '🕯',  210),

  -- Lore
  ('remembrancer',           'Remembrancer',           'Your first approved lore entry.',                         'Set quill to parchment for the first time.',                'common',     'lore',     '📖',  300),
  ('chronicler',             'Chronicler',             'Three approved lore entries.',                            'Three tales recorded for posterity.',                       'common',     'lore',     '📜',  301),
  ('loremaster',             'Loremaster',             'Ten approved lore entries. The archives know your name.', 'Fill the archive with ten chronicles.',                     'honoured',   'lore',     '🏛',  302),
  ('keeper_of_secrets',      'Keeper of Secrets',      'Twenty lore entries, and none more learned than you.',    'Hold more knowledge than any other scholar.',               'legendary',  'lore',     '👁',  303),

  -- Conquest
  ('planetfall',             'Planetfall',             'Contributed to a successful planetary claim.',            'Be present when the banner is planted.',                    'common',     'conquest', '🪐',  400),
  ('world_eater',            'World Eater',            'Contributed the most points personally to a planet flip.','Be the bloodiest hand in a successful claim.',              'honoured',   'conquest', '🌍',  401),
  ('crusade_architect',      'Crusade Architect',      'Contributed to the flipping of three different planets.', 'Plant your banner on three different worlds.',              'honoured',   'conquest', '🗺',  402),
  ('holdfast',               'Holdfast',               'Logged points on a planet your faction already controls.','Defend what is already yours.',                             'common',     'conquest', '🛡',  410),

  -- Cross-cutting
  ('accept_any_challenge',   'Accept Any Challenge',   'At least one approved submission of every active type.',  'Excel in every discipline this Crusade tracks.',            'honoured',   'cross',    '✠',  500),
  ('faithful_servant',       'Faithful Servant',       'Twelve consecutive weeks of approved submissions.',       'Serve without rest for twelve weeks.',                      'legendary',  'cross',    '🙏',  501),
  ('veteran_of_the_long_war','Veteran of the Long War','One of the first ten accounts in the Crusade.',           'You walked these stars before most others.',                'adamantium', 'cross',    '🎖',  502),
  ('standard_bearer',        'Standard Bearer',        'Top glory scorer in your faction (with at least 30 glory).','Carry the banner higher than any of your faction.',        'legendary',  'cross',    '🚩',  503),
  ('first_among_equals',     'First Among Equals',     'Highest glory across all factions (with at least 50 glory).','Stand above every commander in the Crusade.',             'adamantium', 'cross',    '💎',  504);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Idempotent grant: insert (player_id, award_id) by award key.
-- Sets notified=false so the toast fires on next page load.
create or replace function public._grant_award(p_player_id uuid, p_key text)
returns void
language plpgsql
security definer
as $$
begin
  insert into public.player_awards (player_id, award_id)
  select p_player_id, a.id from public.awards a where a.key = p_key
  on conflict (player_id, award_id) do nothing;
end $$;

-- Longest run of consecutive 'win' results for a player's approved games,
-- ordered by created_at. Mirror submissions are included (they have
-- player_id = adversary_user_id of the original).
create or replace function public._max_win_streak(p_player_id uuid)
returns int
language plpgsql
stable
as $$
declare
  v_max int := 0;
  v_cur int := 0;
  r record;
begin
  for r in
    select result
    from public.submissions
    where player_id = p_player_id
      and type = 'game'
      and status = 'approved'
    order by created_at, id
  loop
    if r.result = 'win' then
      v_cur := v_cur + 1;
      if v_cur > v_max then v_max := v_cur; end if;
    else
      v_cur := 0;
    end if;
  end loop;
  return v_max;
end $$;

-- True if the player has approved 'model' submissions in three consecutive
-- calendar months at any point in their history.
create or replace function public._has_3_consecutive_painting_months(p_player_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  r record;
  prev_month date := null;
  streak int := 0;
begin
  for r in
    select distinct date_trunc('month', created_at)::date as m
    from public.submissions
    where player_id = p_player_id
      and type = 'model'
      and status = 'approved'
    order by m
  loop
    if prev_month is null then
      streak := 1;
    elsif r.m = prev_month + interval '1 month' then
      streak := streak + 1;
    else
      streak := 1;
    end if;
    if streak >= 3 then return true; end if;
    prev_month := r.m;
  end loop;
  return false;
end $$;

-- True if the player has approved submissions in 12 consecutive ISO weeks.
create or replace function public._has_12_consecutive_weeks(p_player_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  r record;
  prev_week date := null;
  streak int := 0;
begin
  for r in
    select distinct date_trunc('week', created_at)::date as w
    from public.submissions
    where player_id = p_player_id
      and status = 'approved'
    order by w
  loop
    if prev_week is null then
      streak := 1;
    elsif r.w = prev_week + interval '7 days' then
      streak := streak + 1;
    else
      streak := 1;
    end if;
    if streak >= 12 then return true; end if;
    prev_week := r.w;
  end loop;
  return false;
end $$;

-- ============================================================================
-- EVALUATOR
-- ============================================================================
-- Runs every Phase 1 award check for a player and grants any newly-met ones.
-- Idempotent: existing player_awards rows are not touched.
-- Phase 2 awards are seeded but never granted here (no logic).
create or replace function public.evaluate_player_awards(p_player_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_game_count    int;
  v_model_count   int;
  v_lore_count    int;
  v_max_streak    int;
  v_distinct_types int;
  v_total_types   int;
  v_creation_rank int;
begin
  if p_player_id is null then return; end if;

  -- Combat: total approved games (incl. mirrors)
  select count(*) into v_game_count
  from public.submissions
  where player_id = p_player_id and type = 'game' and status = 'approved';

  if v_game_count >= 1  then perform public._grant_award(p_player_id, 'first_blood'); end if;
  if v_game_count >= 3  then perform public._grant_award(p_player_id, 'veteran'); end if;
  if v_game_count >= 10 then perform public._grant_award(p_player_id, 'honored_of_the_chapter'); end if;

  -- Win streak
  v_max_streak := public._max_win_streak(p_player_id);
  if v_max_streak >= 3  then perform public._grant_award(p_player_id, 'double_tap'); end if;
  if v_max_streak >= 5  then perform public._grant_award(p_player_id, 'overkill'); end if;
  if v_max_streak >= 10 then perform public._grant_award(p_player_id, 'exterminatus'); end if;

  -- Nemesis: 3+ wins against same linked adversary
  if exists (
    select 1
    from public.submissions
    where player_id = p_player_id
      and status = 'approved'
      and type = 'game'
      and result = 'win'
      and adversary_user_id is not null
    group by adversary_user_id
    having count(*) >= 3
  ) then
    perform public._grant_award(p_player_id, 'nemesis');
  end if;

  -- David: any winning linked battle whose ELO delta exceeds K/2 (signal that
  -- the adversary was higher-rated than the submitter pre-battle).
  if exists (
    select 1
    from public.submissions s
    join public.elo_config ec on ec.game_system_id = s.game_system_id
    where s.player_id = p_player_id
      and s.status = 'approved'
      and s.type = 'game'
      and s.result = 'win'
      and s.adversary_user_id is not null
      and s.elo_delta is not null
      and s.elo_delta::numeric > (ec.k_factor::numeric / 2)
  ) then
    perform public._grant_award(p_player_id, 'david');
  end if;

  -- Painting: total approved model submissions
  select count(*) into v_model_count
  from public.submissions
  where player_id = p_player_id and type = 'model' and status = 'approved';

  if v_model_count >= 1  then perform public._grant_award(p_player_id, 'brush_initiate'); end if;
  if v_model_count >= 3  then perform public._grant_award(p_player_id, 'production_painter'); end if;
  if v_model_count >= 10 then perform public._grant_award(p_player_id, 'master_artisan'); end if;

  if public._has_3_consecutive_painting_months(p_player_id) then
    perform public._grant_award(p_player_id, 'the_long_vigil');
  end if;

  -- Lore
  select count(*) into v_lore_count
  from public.submissions
  where player_id = p_player_id and type = 'lore' and status = 'approved';

  if v_lore_count >= 1  then perform public._grant_award(p_player_id, 'remembrancer'); end if;
  if v_lore_count >= 3  then perform public._grant_award(p_player_id, 'chronicler'); end if;
  if v_lore_count >= 10 then perform public._grant_award(p_player_id, 'loremaster'); end if;

  -- Conquest: Planetfall — any approved submission whose target planet is
  -- currently controlled by the submitter's faction-of-record on that submission.
  if exists (
    select 1
    from public.submissions s
    join public.planets p on p.id = s.target_planet_id
    where s.player_id = p_player_id
      and s.status = 'approved'
      and s.faction_id is not null
      and p.controlling_faction_id = s.faction_id
  ) then
    perform public._grant_award(p_player_id, 'planetfall');
  end if;

  -- Holdfast — 2+ approved submissions to the same currently-held planet on
  -- the same faction. Approximation: the second contribution must have been
  -- after the planet was already in their faction's hands. Phase 2 will
  -- replace this with planet_flip_log lookups.
  if exists (
    select 1
    from public.submissions s
    join public.planets p on p.id = s.target_planet_id
    where s.player_id = p_player_id
      and s.status = 'approved'
      and s.faction_id is not null
      and p.controlling_faction_id = s.faction_id
    group by s.target_planet_id, s.faction_id
    having count(*) >= 2
  ) then
    perform public._grant_award(p_player_id, 'holdfast');
  end if;

  -- Accept Any Challenge: one approved submission of every enum value.
  select count(distinct type) into v_distinct_types
  from public.submissions
  where player_id = p_player_id and status = 'approved';

  v_total_types := array_length(enum_range(null::public.submission_type), 1);

  if v_distinct_types is not null
     and v_total_types is not null
     and v_distinct_types >= v_total_types then
    perform public._grant_award(p_player_id, 'accept_any_challenge');
  end if;

  -- Faithful Servant: 12 consecutive weeks of approved submissions.
  if public._has_12_consecutive_weeks(p_player_id) then
    perform public._grant_award(p_player_id, 'faithful_servant');
  end if;

  -- Veteran of the Long War: one of the first 10 accounts created.
  select rnk into v_creation_rank
  from (
    select id, dense_rank() over (order by created_at) as rnk
    from public.profiles
  ) t
  where t.id = p_player_id;

  if v_creation_rank is not null and v_creation_rank <= 10 then
    perform public._grant_award(p_player_id, 'veteran_of_the_long_war');
  end if;
end $$;

-- ============================================================================
-- WIRE EVALUATOR INTO THE APPROVAL TRIGGER
-- ============================================================================
-- Replaces the function from 0006 verbatim except for the trailing evaluator
-- calls. Mirror INSERTs do not fire BEFORE UPDATE, so we explicitly evaluate
-- both submitter and adversary after the mirror row is in place.

create or replace function public.award_points_on_approval()
 returns trigger
 language plpgsql
 security definer
as $function$
declare
  v_threshold     int;
  v_current       int;
  v_submitter_faction uuid;
  v_top_faction   uuid;
  v_sub_rating    int;
  v_adv_rating    int;
  v_k             int;
  v_score         numeric;
  v_delta_sub     int;
  v_delta_adv     int;
  v_prev_status   text;
  v_mirror_result text;
  v_mirror_points int;
begin
  if new.mirror_of is not null then
    return new;
  end if;

  v_prev_status := coalesce(old.status, 'pending');
  v_delta_sub := 0;
  v_delta_adv := 0;
  v_mirror_result := null;
  v_mirror_points := 0;

  if new.status = 'approved' and v_prev_status <> 'approved' then

    v_submitter_faction := new.faction_id;
    if v_submitter_faction is null then
      select faction_id into v_submitter_faction
      from public.profiles where id = new.player_id;
    end if;

    if new.type = 'game'
       and new.adversary_user_id is not null
       and new.adversary_faction_id is not null
       and new.result is not null then
      v_mirror_result := public.opposite_result(new.result);
      if v_mirror_result is not null then
        select coalesce(ps.points, 0) into v_mirror_points
        from public.point_schemes ps
        where ps.game_system_id = new.game_system_id
          and ps.game_size      = coalesce(new.game_size, 'n/a')
          and ps.result         = v_mirror_result
        limit 1;
        v_mirror_points := coalesce(v_mirror_points, 0);
      end if;
    end if;

    -- 1) Submitter glory on planet
    if new.target_planet_id is not null and v_submitter_faction is not null and coalesce(new.points, 0) > 0 then
      insert into public.planet_points (planet_id, faction_id, points)
      values (new.target_planet_id, v_submitter_faction, new.points)
      on conflict (planet_id, faction_id)
      do update set points = public.planet_points.points + excluded.points;

      -- 2) Adversary glory equal to their commander's loss/draw points.
      if new.adversary_faction_id is not null
         and new.adversary_faction_id <> v_submitter_faction
         and v_mirror_points > 0 then

        insert into public.planet_points (planet_id, faction_id, points)
        values (new.target_planet_id, new.adversary_faction_id, v_mirror_points)
        on conflict (planet_id, faction_id)
        do update set points = public.planet_points.points + excluded.points;
      end if;

      -- 3) Planet threshold / control flip check
      select threshold into v_threshold
      from public.planets where id = new.target_planet_id;

      select coalesce(max(points),0) into v_current
      from public.planet_points
      where planet_id = new.target_planet_id;

      select faction_id into v_top_faction
      from public.planet_points
      where planet_id = new.target_planet_id
      order by points desc
      limit 1;

      if v_current >= coalesce(v_threshold, 0) then
        update public.planets
        set controlling_faction_id = v_top_faction
        where id = new.target_planet_id;
      end if;
    end if;

    -- 4) ELO update for game submissions.
    if new.type = 'game'
       and new.game_system_id is not null
       and new.result is not null
       and new.faction_id is not null then

      select coalesce(k_factor, 32) into v_k
      from public.elo_config
      where game_system_id = new.game_system_id;
      v_k := coalesce(v_k, 32);

      v_score := case new.result
        when 'win'  then 1.0
        when 'draw' then 0.5
        when 'loss' then 0.0
      end;

      if new.adversary_user_id is not null
         and new.adversary_faction_id is not null then

        v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id);
        v_adv_rating := public.get_or_create_elo(new.adversary_user_id, new.game_system_id, new.adversary_faction_id);

        v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);
        v_delta_adv := -v_delta_sub;

        update public.elo_ratings
          set rating = rating + v_delta_sub,
              games_played = games_played + 1,
              wins   = wins   + (case when new.result = 'win'  then 1 else 0 end),
              losses = losses + (case when new.result = 'loss' then 1 else 0 end),
              draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
              updated_at = now()
        where user_id = new.player_id
          and game_system_id = new.game_system_id
          and faction_id = new.faction_id;

        update public.elo_ratings
          set rating = rating + v_delta_adv,
              games_played = games_played + 1,
              wins   = wins   + (case when new.result = 'loss' then 1 else 0 end),
              losses = losses + (case when new.result = 'win'  then 1 else 0 end),
              draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
              updated_at = now()
        where user_id = new.adversary_user_id
          and game_system_id = new.game_system_id
          and faction_id = new.adversary_faction_id;

        new.elo_delta := v_delta_sub;
        new.adversary_elo_delta := v_delta_adv;

      elsif new.adversary_user_id is null
            and new.adversary_faction_id is null then

        v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id);

        select coalesce(starting_elo, 1200) into v_adv_rating
        from public.elo_config
        where game_system_id = new.game_system_id;
        v_adv_rating := coalesce(v_adv_rating, 1200);

        v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);

        update public.elo_ratings
          set rating = rating + v_delta_sub,
              games_played = games_played + 1,
              wins   = wins   + (case when new.result = 'win'  then 1 else 0 end),
              losses = losses + (case when new.result = 'loss' then 1 else 0 end),
              draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
              updated_at = now()
        where user_id = new.player_id
          and game_system_id = new.game_system_id
          and faction_id = new.faction_id;

        new.elo_delta := v_delta_sub;
      end if;
    end if;

    -- 5) Mirror submission for linked battles.
    if v_mirror_result is not null
       and not exists (select 1 from public.submissions where mirror_of = new.id) then

      insert into public.submissions (
        player_id,
        faction_id,
        target_planet_id,
        type,
        title,
        body,
        image_url,
        opponent_name,
        result,
        points,
        status,
        reviewed_by,
        reviewed_at,
        review_notes,
        game_system_id,
        game_size,
        video_game_title_id,
        adversary_user_id,
        adversary_faction_id,
        elo_delta,
        adversary_elo_delta,
        mirror_of
      ) values (
        new.adversary_user_id,
        new.adversary_faction_id,
        new.target_planet_id,
        new.type,
        new.title,
        new.body,
        new.image_url,
        null,
        v_mirror_result,
        v_mirror_points,
        'approved',
        new.reviewed_by,
        coalesce(new.reviewed_at, now()),
        new.review_notes,
        new.game_system_id,
        new.game_size,
        new.video_game_title_id,
        new.player_id,
        new.faction_id,
        v_delta_adv,
        v_delta_sub,
        new.id
      );
    end if;

    -- 6) Award evaluation. Mirror INSERT above does not fire this BEFORE
    --    UPDATE trigger, so we evaluate both sides explicitly.
    perform public.evaluate_player_awards(new.player_id);
    if new.adversary_user_id is not null then
      perform public.evaluate_player_awards(new.adversary_user_id);
    end if;

    new.reviewed_at := coalesce(new.reviewed_at, now());
  end if;

  return new;
end;
$function$;

-- ============================================================================
-- BACKFILL: evaluate awards for every existing player based on their already
-- approved submissions. Safe to run on a fresh schema (no rows yet) and on
-- production (idempotent).
-- ============================================================================
select public.evaluate_player_awards(id) from public.profiles;

-- The backfill above sets notified=false for every newly-granted award, which
-- means all existing players will see toasts on their next page load. That is
-- the intended behaviour for the rollout: existing veterans receive their
-- earned honours retroactively.


-- ############################################################################
-- # 0008_awards_phase_2.sql
-- ############################################################################

-- ============================================================================
-- 0008_awards_phase_2.sql
--
-- Issue #26 phase 2. Phase 1 (0007) seeded all 27 awards but only auto-granted
-- 20 of them. This migration:
--
--   1. Adds `planet_flip_log` to record every change of a planet's controlling
--      faction, capturing the top points contributor at flip time. World Eater
--      and Crusade Architect derive from this log.
--   2. Adds `evaluate_competitive_awards()` so single-holder badges (Warmaster,
--      Painting Daemon, Keeper of Secrets, Standard Bearer, First Among Equals)
--      transfer when leadership changes.
--   3. Extends `evaluate_player_awards` with World Eater + Crusade Architect,
--      and replaces the placeholder Holdfast logic with a flip-log-aware check.
--   4. Replaces `award_points_on_approval` to: (a) only flip control when the
--      top faction actually changes, (b) insert a planet_flip_log row on every
--      change, (c) call `evaluate_competitive_awards()` after the per-player
--      evaluators so cross-player transfers happen on the same approval.
--   5. Backfills the flip log for currently-controlled planets and re-runs all
--      evaluators.
-- ============================================================================

-- ---------- PLANET FLIP LOG ----------
create table public.planet_flip_log (
  id                    uuid primary key default gen_random_uuid(),
  planet_id             uuid not null references public.planets(id)        on delete cascade,
  gained_faction_id     uuid not null references public.factions(id)       on delete cascade,
  lost_faction_id       uuid          references public.factions(id)       on delete set null,
  trigger_submission_id uuid          references public.submissions(id)    on delete set null,
  top_contributor_id    uuid          references public.profiles(id)       on delete set null,
  points_at_flip        int  not null default 0,
  created_at            timestamptz not null default now()
);

create index on public.planet_flip_log (planet_id);
create index on public.planet_flip_log (top_contributor_id);
create index on public.planet_flip_log (gained_faction_id);

alter table public.planet_flip_log enable row level security;

create policy "planet_flip_log readable" on public.planet_flip_log
  for select using (auth.role() = 'authenticated');

-- ============================================================================
-- COMPETITIVE EVALUATOR
-- ============================================================================
-- For single-holder awards, recomputes the current leader and grants/revokes
-- so the badge transfers cleanly. Tie-break by player_id ASC for determinism.
-- Standard Bearer has one holder per faction; the others have one global
-- holder.
create or replace function public.evaluate_competitive_awards()
returns void
language plpgsql
security definer
as $$
declare
  v_warmaster   uuid;
  v_painter     uuid;
  v_lorekeeper  uuid;
  v_global_top  uuid;
  r record;
begin
  ----------------------------------------------------------------------
  -- Warmaster: most approved games of any player, ≥ 20.
  ----------------------------------------------------------------------
  select player_id into v_warmaster
  from (
    select player_id, count(*) as cnt
    from public.submissions
    where type = 'game' and status = 'approved'
    group by player_id
  ) t
  where cnt >= 20
  order by cnt desc, player_id asc
  limit 1;

  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'warmaster'
    and (v_warmaster is null or pa.player_id <> v_warmaster);

  if v_warmaster is not null then
    perform public._grant_award(v_warmaster, 'warmaster');
  end if;

  ----------------------------------------------------------------------
  -- Painting Daemon: most approved models, ≥ 20.
  ----------------------------------------------------------------------
  select player_id into v_painter
  from (
    select player_id, count(*) as cnt
    from public.submissions
    where type = 'model' and status = 'approved'
    group by player_id
  ) t
  where cnt >= 20
  order by cnt desc, player_id asc
  limit 1;

  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'painting_daemon'
    and (v_painter is null or pa.player_id <> v_painter);

  if v_painter is not null then
    perform public._grant_award(v_painter, 'painting_daemon');
  end if;

  ----------------------------------------------------------------------
  -- Keeper of Secrets: most approved lore, ≥ 20.
  ----------------------------------------------------------------------
  select player_id into v_lorekeeper
  from (
    select player_id, count(*) as cnt
    from public.submissions
    where type = 'lore' and status = 'approved'
    group by player_id
  ) t
  where cnt >= 20
  order by cnt desc, player_id asc
  limit 1;

  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'keeper_of_secrets'
    and (v_lorekeeper is null or pa.player_id <> v_lorekeeper);

  if v_lorekeeper is not null then
    perform public._grant_award(v_lorekeeper, 'keeper_of_secrets');
  end if;

  ----------------------------------------------------------------------
  -- First Among Equals: top total glory across all players, ≥ 50.
  -- Glory = sum of approved submission points (player_totals view).
  ----------------------------------------------------------------------
  select player_id into v_global_top
  from public.player_totals
  where total_points >= 50
  order by total_points desc, player_id asc
  limit 1;

  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'first_among_equals'
    and (v_global_top is null or pa.player_id <> v_global_top);

  if v_global_top is not null then
    perform public._grant_award(v_global_top, 'first_among_equals');
  end if;

  ----------------------------------------------------------------------
  -- Standard Bearer: per-faction top scorer with primary faction match,
  -- ≥ 30 glory. One holder per faction.
  ----------------------------------------------------------------------
  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'standard_bearer'
    and pa.player_id not in (
      select distinct on (faction_id) player_id
      from public.player_totals
      where faction_id is not null and total_points >= 30
      order by faction_id, total_points desc, player_id asc
    );

  for r in
    select distinct on (faction_id) player_id
    from public.player_totals
    where faction_id is not null and total_points >= 30
    order by faction_id, total_points desc, player_id asc
  loop
    perform public._grant_award(r.player_id, 'standard_bearer');
  end loop;
end $$;

-- ============================================================================
-- EVALUATOR (extended)
-- ============================================================================
-- Adds World Eater and Crusade Architect (planet_flip_log driven), and
-- upgrades Holdfast from "currently controlled + 2 submissions" to "any
-- submission posted after a flip that gave the faction control".
create or replace function public.evaluate_player_awards(p_player_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_game_count     int;
  v_model_count    int;
  v_lore_count     int;
  v_max_streak     int;
  v_distinct_types int;
  v_total_types    int;
  v_creation_rank  int;
begin
  if p_player_id is null then return; end if;

  -- Combat: total approved games (incl. mirrors)
  select count(*) into v_game_count
  from public.submissions
  where player_id = p_player_id and type = 'game' and status = 'approved';

  if v_game_count >= 1  then perform public._grant_award(p_player_id, 'first_blood'); end if;
  if v_game_count >= 3  then perform public._grant_award(p_player_id, 'veteran'); end if;
  if v_game_count >= 10 then perform public._grant_award(p_player_id, 'honored_of_the_chapter'); end if;

  -- Win streak
  v_max_streak := public._max_win_streak(p_player_id);
  if v_max_streak >= 3  then perform public._grant_award(p_player_id, 'double_tap'); end if;
  if v_max_streak >= 5  then perform public._grant_award(p_player_id, 'overkill'); end if;
  if v_max_streak >= 10 then perform public._grant_award(p_player_id, 'exterminatus'); end if;

  -- Nemesis: 3+ wins against same linked adversary
  if exists (
    select 1
    from public.submissions
    where player_id = p_player_id
      and status = 'approved'
      and type = 'game'
      and result = 'win'
      and adversary_user_id is not null
    group by adversary_user_id
    having count(*) >= 3
  ) then
    perform public._grant_award(p_player_id, 'nemesis');
  end if;

  -- David: any winning linked battle whose ELO delta exceeds K/2 (signal that
  -- the adversary was higher-rated than the submitter pre-battle).
  if exists (
    select 1
    from public.submissions s
    join public.elo_config ec on ec.game_system_id = s.game_system_id
    where s.player_id = p_player_id
      and s.status = 'approved'
      and s.type = 'game'
      and s.result = 'win'
      and s.adversary_user_id is not null
      and s.elo_delta is not null
      and s.elo_delta::numeric > (ec.k_factor::numeric / 2)
  ) then
    perform public._grant_award(p_player_id, 'david');
  end if;

  -- Painting: total approved model submissions
  select count(*) into v_model_count
  from public.submissions
  where player_id = p_player_id and type = 'model' and status = 'approved';

  if v_model_count >= 1  then perform public._grant_award(p_player_id, 'brush_initiate'); end if;
  if v_model_count >= 3  then perform public._grant_award(p_player_id, 'production_painter'); end if;
  if v_model_count >= 10 then perform public._grant_award(p_player_id, 'master_artisan'); end if;

  if public._has_3_consecutive_painting_months(p_player_id) then
    perform public._grant_award(p_player_id, 'the_long_vigil');
  end if;

  -- Lore
  select count(*) into v_lore_count
  from public.submissions
  where player_id = p_player_id and type = 'lore' and status = 'approved';

  if v_lore_count >= 1  then perform public._grant_award(p_player_id, 'remembrancer'); end if;
  if v_lore_count >= 3  then perform public._grant_award(p_player_id, 'chronicler'); end if;
  if v_lore_count >= 10 then perform public._grant_award(p_player_id, 'loremaster'); end if;

  -- Conquest: Planetfall — any approved submission whose target planet is
  -- currently controlled by the submitter's faction-of-record on that submission.
  if exists (
    select 1
    from public.submissions s
    join public.planets p on p.id = s.target_planet_id
    where s.player_id = p_player_id
      and s.status = 'approved'
      and s.faction_id is not null
      and p.controlling_faction_id = s.faction_id
  ) then
    perform public._grant_award(p_player_id, 'planetfall');
  end if;

  -- Holdfast — at least one approved submission to a planet+faction posted
  -- AFTER a flip that gave that faction control. Replaces the phase-1
  -- approximation that required two submissions.
  if exists (
    select 1
    from public.planet_flip_log pfl
    join public.submissions s
      on s.target_planet_id = pfl.planet_id
     and s.faction_id       = pfl.gained_faction_id
     and s.status            = 'approved'
     and s.created_at        > pfl.created_at
    where s.player_id = p_player_id
  ) then
    perform public._grant_award(p_player_id, 'holdfast');
  end if;

  -- World Eater — was the top points contributor at any planet flip.
  if exists (
    select 1 from public.planet_flip_log
    where top_contributor_id = p_player_id
  ) then
    perform public._grant_award(p_player_id, 'world_eater');
  end if;

  -- Crusade Architect — contributed to flips on 3+ different planets.
  -- "Contributed" = at least one approved submission for the planet+gained
  -- faction at or before the flip moment.
  if (
    select count(distinct pfl.planet_id)
    from public.planet_flip_log pfl
    where exists (
      select 1 from public.submissions s
      where s.player_id        = p_player_id
        and s.target_planet_id = pfl.planet_id
        and s.faction_id       = pfl.gained_faction_id
        and s.status            = 'approved'
        and s.created_at        <= pfl.created_at
    )
  ) >= 3 then
    perform public._grant_award(p_player_id, 'crusade_architect');
  end if;

  -- Accept Any Challenge: one approved submission of every enum value.
  select count(distinct type) into v_distinct_types
  from public.submissions
  where player_id = p_player_id and status = 'approved';

  v_total_types := array_length(enum_range(null::public.submission_type), 1);

  if v_distinct_types is not null
     and v_total_types is not null
     and v_distinct_types >= v_total_types then
    perform public._grant_award(p_player_id, 'accept_any_challenge');
  end if;

  -- Faithful Servant: 12 consecutive weeks of approved submissions.
  if public._has_12_consecutive_weeks(p_player_id) then
    perform public._grant_award(p_player_id, 'faithful_servant');
  end if;

  -- Veteran of the Long War: one of the first 10 accounts created.
  select rnk into v_creation_rank
  from (
    select id, dense_rank() over (order by created_at) as rnk
    from public.profiles
  ) t
  where t.id = p_player_id;

  if v_creation_rank is not null and v_creation_rank <= 10 then
    perform public._grant_award(p_player_id, 'veteran_of_the_long_war');
  end if;
end $$;

-- ============================================================================
-- APPROVAL TRIGGER (replaced)
-- ============================================================================
-- Diff vs 0007:
--   * Step 3 reads the prior controlling_faction_id and only updates the
--     planet (and inserts a planet_flip_log row) when the top faction is
--     genuinely different. The new row records the deciding submission and
--     the player who has contributed the most approved points to the
--     gaining faction so far on that planet.
--   * Step 6 calls `evaluate_competitive_awards()` after the per-player
--     evaluations so single-holder badges transfer on the same approval.

create or replace function public.award_points_on_approval()
 returns trigger
 language plpgsql
 security definer
as $function$
declare
  v_threshold     int;
  v_current       int;
  v_submitter_faction uuid;
  v_top_faction   uuid;
  v_prev_controller uuid;
  v_top_contributor uuid;
  v_sub_rating    int;
  v_adv_rating    int;
  v_k             int;
  v_score         numeric;
  v_delta_sub     int;
  v_delta_adv     int;
  v_prev_status   text;
  v_mirror_result text;
  v_mirror_points int;
begin
  if new.mirror_of is not null then
    return new;
  end if;

  v_prev_status := coalesce(old.status, 'pending');
  v_delta_sub := 0;
  v_delta_adv := 0;
  v_mirror_result := null;
  v_mirror_points := 0;

  if new.status = 'approved' and v_prev_status <> 'approved' then

    v_submitter_faction := new.faction_id;
    if v_submitter_faction is null then
      select faction_id into v_submitter_faction
      from public.profiles where id = new.player_id;
    end if;

    if new.type = 'game'
       and new.adversary_user_id is not null
       and new.adversary_faction_id is not null
       and new.result is not null then
      v_mirror_result := public.opposite_result(new.result);
      if v_mirror_result is not null then
        select coalesce(ps.points, 0) into v_mirror_points
        from public.point_schemes ps
        where ps.game_system_id = new.game_system_id
          and ps.game_size      = coalesce(new.game_size, 'n/a')
          and ps.result         = v_mirror_result
        limit 1;
        v_mirror_points := coalesce(v_mirror_points, 0);
      end if;
    end if;

    -- 1) Submitter glory on planet
    if new.target_planet_id is not null and v_submitter_faction is not null and coalesce(new.points, 0) > 0 then
      insert into public.planet_points (planet_id, faction_id, points)
      values (new.target_planet_id, v_submitter_faction, new.points)
      on conflict (planet_id, faction_id)
      do update set points = public.planet_points.points + excluded.points;

      -- 2) Adversary glory equal to their commander's loss/draw points.
      if new.adversary_faction_id is not null
         and new.adversary_faction_id <> v_submitter_faction
         and v_mirror_points > 0 then

        insert into public.planet_points (planet_id, faction_id, points)
        values (new.target_planet_id, new.adversary_faction_id, v_mirror_points)
        on conflict (planet_id, faction_id)
        do update set points = public.planet_points.points + excluded.points;
      end if;

      -- 3) Planet threshold / control flip check + flip log.
      select threshold, controlling_faction_id
        into v_threshold, v_prev_controller
      from public.planets where id = new.target_planet_id;

      select coalesce(max(points),0) into v_current
      from public.planet_points
      where planet_id = new.target_planet_id;

      select faction_id into v_top_faction
      from public.planet_points
      where planet_id = new.target_planet_id
      order by points desc
      limit 1;

      if v_current >= coalesce(v_threshold, 0)
         and v_top_faction is not null
         and (v_prev_controller is null or v_prev_controller <> v_top_faction) then

        -- Top approved-points contributor for the gaining faction so far on
        -- this planet. Tie-break by earliest submission, then player_id.
        select s.player_id into v_top_contributor
        from public.submissions s
        where s.target_planet_id = new.target_planet_id
          and s.faction_id       = v_top_faction
          and s.status            = 'approved'
        group by s.player_id
        order by sum(coalesce(s.points, 0)) desc, min(s.created_at) asc, s.player_id asc
        limit 1;

        update public.planets
        set controlling_faction_id = v_top_faction,
            claimed_at = coalesce(claimed_at, now())
        where id = new.target_planet_id;

        insert into public.planet_flip_log (
          planet_id, gained_faction_id, lost_faction_id,
          trigger_submission_id, top_contributor_id, points_at_flip
        )
        values (
          new.target_planet_id, v_top_faction, v_prev_controller,
          new.id, v_top_contributor, v_current
        );
      end if;
    end if;

    -- 4) ELO update for game submissions.
    if new.type = 'game'
       and new.game_system_id is not null
       and new.result is not null
       and new.faction_id is not null then

      select coalesce(k_factor, 32) into v_k
      from public.elo_config
      where game_system_id = new.game_system_id;
      v_k := coalesce(v_k, 32);

      v_score := case new.result
        when 'win'  then 1.0
        when 'draw' then 0.5
        when 'loss' then 0.0
      end;

      if new.adversary_user_id is not null
         and new.adversary_faction_id is not null then

        v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id);
        v_adv_rating := public.get_or_create_elo(new.adversary_user_id, new.game_system_id, new.adversary_faction_id);

        v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);
        v_delta_adv := -v_delta_sub;

        update public.elo_ratings
          set rating = rating + v_delta_sub,
              games_played = games_played + 1,
              wins   = wins   + (case when new.result = 'win'  then 1 else 0 end),
              losses = losses + (case when new.result = 'loss' then 1 else 0 end),
              draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
              updated_at = now()
        where user_id = new.player_id
          and game_system_id = new.game_system_id
          and faction_id = new.faction_id;

        update public.elo_ratings
          set rating = rating + v_delta_adv,
              games_played = games_played + 1,
              wins   = wins   + (case when new.result = 'loss' then 1 else 0 end),
              losses = losses + (case when new.result = 'win'  then 1 else 0 end),
              draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
              updated_at = now()
        where user_id = new.adversary_user_id
          and game_system_id = new.game_system_id
          and faction_id = new.adversary_faction_id;

        new.elo_delta := v_delta_sub;
        new.adversary_elo_delta := v_delta_adv;

      elsif new.adversary_user_id is null
            and new.adversary_faction_id is null then

        v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id);

        select coalesce(starting_elo, 1200) into v_adv_rating
        from public.elo_config
        where game_system_id = new.game_system_id;
        v_adv_rating := coalesce(v_adv_rating, 1200);

        v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);

        update public.elo_ratings
          set rating = rating + v_delta_sub,
              games_played = games_played + 1,
              wins   = wins   + (case when new.result = 'win'  then 1 else 0 end),
              losses = losses + (case when new.result = 'loss' then 1 else 0 end),
              draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
              updated_at = now()
        where user_id = new.player_id
          and game_system_id = new.game_system_id
          and faction_id = new.faction_id;

        new.elo_delta := v_delta_sub;
      end if;
    end if;

    -- 5) Mirror submission for linked battles.
    if v_mirror_result is not null
       and not exists (select 1 from public.submissions where mirror_of = new.id) then

      insert into public.submissions (
        player_id,
        faction_id,
        target_planet_id,
        type,
        title,
        body,
        image_url,
        opponent_name,
        result,
        points,
        status,
        reviewed_by,
        reviewed_at,
        review_notes,
        game_system_id,
        game_size,
        video_game_title_id,
        adversary_user_id,
        adversary_faction_id,
        elo_delta,
        adversary_elo_delta,
        mirror_of
      ) values (
        new.adversary_user_id,
        new.adversary_faction_id,
        new.target_planet_id,
        new.type,
        new.title,
        new.body,
        new.image_url,
        null,
        v_mirror_result,
        v_mirror_points,
        'approved',
        new.reviewed_by,
        coalesce(new.reviewed_at, now()),
        new.review_notes,
        new.game_system_id,
        new.game_size,
        new.video_game_title_id,
        new.player_id,
        new.faction_id,
        v_delta_adv,
        v_delta_sub,
        new.id
      );
    end if;

    -- 6) Award evaluation. Per-player first (granted on submitter + adversary
    --    where applicable), then competitive (cross-player transfers).
    perform public.evaluate_player_awards(new.player_id);
    if new.adversary_user_id is not null then
      perform public.evaluate_player_awards(new.adversary_user_id);
    end if;
    perform public.evaluate_competitive_awards();

    new.reviewed_at := coalesce(new.reviewed_at, now());
  end if;

  return new;
end;
$function$;

-- ============================================================================
-- BACKFILL
-- ============================================================================
-- 1) Seed planet_flip_log for each currently-controlled planet so phase-2
--    awards have data to evaluate against. We don't have history of prior
--    flips, so we record one synthetic flip per controlled planet. The top
--    contributor is the player with the most approved points to the
--    controlling faction on that planet to date.
insert into public.planet_flip_log (
  planet_id, gained_faction_id, lost_faction_id,
  trigger_submission_id, top_contributor_id, points_at_flip, created_at
)
select
  p.id,
  p.controlling_faction_id,
  null,
  null,
  (
    select s.player_id
    from public.submissions s
    where s.target_planet_id = p.id
      and s.faction_id       = p.controlling_faction_id
      and s.status            = 'approved'
    group by s.player_id
    order by sum(coalesce(s.points, 0)) desc, min(s.created_at) asc, s.player_id asc
    limit 1
  ),
  coalesce((
    select sum(points)::int from public.planet_points
    where planet_id = p.id and faction_id = p.controlling_faction_id
  ), 0),
  coalesce(p.claimed_at, now())
from public.planets p
where p.controlling_faction_id is not null;

-- 2) Re-run per-player evaluator so World Eater, Crusade Architect, and the
--    upgraded Holdfast are granted retroactively.
select public.evaluate_player_awards(id) from public.profiles;

-- 3) Run the competitive evaluator once so single-holder badges land on the
--    current leaders.
select public.evaluate_competitive_awards();


-- ############################################################################
-- # 0009_lore_split_enum.sql
-- ############################################################################

-- ============================================================================
-- 0009_lore_split_enum.sql
--
-- Issue #31 part 1 of 2: split the `lore` submission type into two distinct
-- types — writing (renamed to `scribe`) and reading/listening (`loremaster`,
-- added in this migration). Issue #31 introduces the reading deed for novels
-- and audiobooks; the existing `lore` enum value semantically meant *writing*
-- fluff, so it's renamed for symmetry.
--
-- This phase ONLY:
--   1. Renames the enum value `lore` → `scribe`.
--   2. Adds the new `loremaster` enum value (cannot be referenced until the
--      next migration commits — Postgres restriction on ALTER TYPE ADD VALUE).
--   3. Recreates `faction_totals` to read `s.type = 'scribe'` and renames the
--      column `lore_submitted` → `lore_written`. The companion `lore_read`
--      column is added in 0010, once `loremaster` is referenceable.
--   4. Updates evaluator functions to use `'scribe'` instead of `'lore'` so
--      existing writing-track awards keep firing.
--   5. Renames the existing badge key `loremaster` → `master_scribe`. The
--      badge name and description are unchanged. This avoids a confusing
--      collision between the badge key and the new submission type, both
--      called `loremaster`.
--
-- 0010 then adds the loremaster-specific columns, the new badges, and the
-- evaluator logic that grants them.
-- ============================================================================

-- ---------- 1. RENAME ENUM VALUE ----------
alter type public.submission_type rename value 'lore' to 'scribe';

-- ---------- 2. ADD NEW ENUM VALUE ----------
-- IMPORTANT: 'loremaster' cannot be referenced in queries within this same
-- transaction. 0010 uses it freely.
alter type public.submission_type add value if not exists 'loremaster';

-- ---------- 3. REBUILD faction_totals VIEW ----------
-- Rename `lore_submitted` → `lore_written` for the writing track. The
-- companion `lore_read` column is added in 0010.
drop view if exists public.faction_totals;

create view public.faction_totals as
  select
    f.id as faction_id,
    f.name as faction_name,
    f.color,
    coalesce(sum(s.points), 0)::int as total_points,
    count(s.id) filter (where s.type = 'game' and s.result = 'win') as wins,
    count(s.id) filter (where s.type = 'model') as models_painted,
    count(s.id) filter (where s.type = 'scribe') as lore_written,
    count(distinct p.id) as planets_controlled
  from public.factions f
  left join public.submissions s
    on s.faction_id = f.id and s.status = 'approved'
  left join public.planets p
    on p.controlling_faction_id = f.id
  group by f.id, f.name, f.color;

grant select on public.faction_totals to anon, authenticated;

-- ---------- 4. UPDATE EVALUATORS TO USE 'scribe' ----------
-- The existing 4 lore-track awards (remembrancer, chronicler, loremaster
-- badge, keeper_of_secrets) all rewarded *written* lore. Re-bind their
-- queries to the renamed enum value.

create or replace function public.evaluate_player_awards(p_player_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_game_count     int;
  v_model_count    int;
  v_lore_count     int;
  v_max_streak     int;
  v_distinct_types int;
  v_total_types    int;
  v_creation_rank  int;
begin
  if p_player_id is null then return; end if;

  -- Combat: total approved games (incl. mirrors)
  select count(*) into v_game_count
  from public.submissions
  where player_id = p_player_id and type = 'game' and status = 'approved';

  if v_game_count >= 1  then perform public._grant_award(p_player_id, 'first_blood'); end if;
  if v_game_count >= 3  then perform public._grant_award(p_player_id, 'veteran'); end if;
  if v_game_count >= 10 then perform public._grant_award(p_player_id, 'honored_of_the_chapter'); end if;

  -- Win streak
  v_max_streak := public._max_win_streak(p_player_id);
  if v_max_streak >= 3  then perform public._grant_award(p_player_id, 'double_tap'); end if;
  if v_max_streak >= 5  then perform public._grant_award(p_player_id, 'overkill'); end if;
  if v_max_streak >= 10 then perform public._grant_award(p_player_id, 'exterminatus'); end if;

  -- Nemesis: 3+ wins against same linked adversary
  if exists (
    select 1
    from public.submissions
    where player_id = p_player_id
      and status = 'approved'
      and type = 'game'
      and result = 'win'
      and adversary_user_id is not null
    group by adversary_user_id
    having count(*) >= 3
  ) then
    perform public._grant_award(p_player_id, 'nemesis');
  end if;

  -- David: any winning linked battle whose ELO delta exceeds K/2
  if exists (
    select 1
    from public.submissions s
    join public.elo_config ec on ec.game_system_id = s.game_system_id
    where s.player_id = p_player_id
      and s.status = 'approved'
      and s.type = 'game'
      and s.result = 'win'
      and s.adversary_user_id is not null
      and s.elo_delta is not null
      and s.elo_delta::numeric > (ec.k_factor::numeric / 2)
  ) then
    perform public._grant_award(p_player_id, 'david');
  end if;

  -- Painting: total approved model submissions
  select count(*) into v_model_count
  from public.submissions
  where player_id = p_player_id and type = 'model' and status = 'approved';

  if v_model_count >= 1  then perform public._grant_award(p_player_id, 'brush_initiate'); end if;
  if v_model_count >= 3  then perform public._grant_award(p_player_id, 'production_painter'); end if;
  if v_model_count >= 10 then perform public._grant_award(p_player_id, 'master_artisan'); end if;

  if public._has_3_consecutive_painting_months(p_player_id) then
    perform public._grant_award(p_player_id, 'the_long_vigil');
  end if;

  -- Lore (writing track) — type renamed from 'lore' to 'scribe' in 0009.
  -- Badge key renamed from 'loremaster' to 'master_scribe' (same migration).
  select count(*) into v_lore_count
  from public.submissions
  where player_id = p_player_id and type = 'scribe' and status = 'approved';

  if v_lore_count >= 1  then perform public._grant_award(p_player_id, 'remembrancer'); end if;
  if v_lore_count >= 3  then perform public._grant_award(p_player_id, 'chronicler'); end if;
  if v_lore_count >= 10 then perform public._grant_award(p_player_id, 'master_scribe'); end if;

  -- Conquest: Planetfall
  if exists (
    select 1
    from public.submissions s
    join public.planets p on p.id = s.target_planet_id
    where s.player_id = p_player_id
      and s.status = 'approved'
      and s.faction_id is not null
      and p.controlling_faction_id = s.faction_id
  ) then
    perform public._grant_award(p_player_id, 'planetfall');
  end if;

  -- Holdfast — submission posted after a flip that gave that faction control.
  if exists (
    select 1
    from public.planet_flip_log pfl
    join public.submissions s
      on s.target_planet_id = pfl.planet_id
     and s.faction_id       = pfl.gained_faction_id
     and s.status            = 'approved'
     and s.created_at        > pfl.created_at
    where s.player_id = p_player_id
  ) then
    perform public._grant_award(p_player_id, 'holdfast');
  end if;

  -- World Eater — was the top points contributor at any planet flip.
  if exists (
    select 1 from public.planet_flip_log
    where top_contributor_id = p_player_id
  ) then
    perform public._grant_award(p_player_id, 'world_eater');
  end if;

  -- Crusade Architect — contributed to flips on 3+ different planets.
  if (
    select count(distinct pfl.planet_id)
    from public.planet_flip_log pfl
    where exists (
      select 1 from public.submissions s
      where s.player_id        = p_player_id
        and s.target_planet_id = pfl.planet_id
        and s.faction_id       = pfl.gained_faction_id
        and s.status            = 'approved'
        and s.created_at        <= pfl.created_at
    )
  ) >= 3 then
    perform public._grant_award(p_player_id, 'crusade_architect');
  end if;

  -- Accept Any Challenge: one approved submission of every enum value.
  select count(distinct type) into v_distinct_types
  from public.submissions
  where player_id = p_player_id and status = 'approved';

  v_total_types := array_length(enum_range(null::public.submission_type), 1);

  if v_distinct_types is not null
     and v_total_types is not null
     and v_distinct_types >= v_total_types then
    perform public._grant_award(p_player_id, 'accept_any_challenge');
  end if;

  -- Faithful Servant: 12 consecutive weeks of approved submissions.
  if public._has_12_consecutive_weeks(p_player_id) then
    perform public._grant_award(p_player_id, 'faithful_servant');
  end if;

  -- Veteran of the Long War: one of the first 10 accounts created.
  select rnk into v_creation_rank
  from (
    select id, dense_rank() over (order by created_at) as rnk
    from public.profiles
  ) t
  where t.id = p_player_id;

  if v_creation_rank is not null and v_creation_rank <= 10 then
    perform public._grant_award(p_player_id, 'veteran_of_the_long_war');
  end if;
end $$;

-- ---------- 5. UPDATE COMPETITIVE EVALUATOR TO USE 'scribe' ----------
create or replace function public.evaluate_competitive_awards()
returns void
language plpgsql
security definer
as $$
declare
  v_warmaster   uuid;
  v_painter     uuid;
  v_lorekeeper  uuid;
  v_global_top  uuid;
  r record;
begin
  -- Warmaster
  select player_id into v_warmaster
  from (
    select player_id, count(*) as cnt
    from public.submissions
    where type = 'game' and status = 'approved'
    group by player_id
  ) t
  where cnt >= 20
  order by cnt desc, player_id asc
  limit 1;

  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'warmaster'
    and (v_warmaster is null or pa.player_id <> v_warmaster);

  if v_warmaster is not null then
    perform public._grant_award(v_warmaster, 'warmaster');
  end if;

  -- Painting Daemon
  select player_id into v_painter
  from (
    select player_id, count(*) as cnt
    from public.submissions
    where type = 'model' and status = 'approved'
    group by player_id
  ) t
  where cnt >= 20
  order by cnt desc, player_id asc
  limit 1;

  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'painting_daemon'
    and (v_painter is null or pa.player_id <> v_painter);

  if v_painter is not null then
    perform public._grant_award(v_painter, 'painting_daemon');
  end if;

  -- Keeper of Secrets — most approved writing-track lore, ≥ 20.
  -- Type renamed from 'lore' to 'scribe' in this migration.
  select player_id into v_lorekeeper
  from (
    select player_id, count(*) as cnt
    from public.submissions
    where type = 'scribe' and status = 'approved'
    group by player_id
  ) t
  where cnt >= 20
  order by cnt desc, player_id asc
  limit 1;

  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'keeper_of_secrets'
    and (v_lorekeeper is null or pa.player_id <> v_lorekeeper);

  if v_lorekeeper is not null then
    perform public._grant_award(v_lorekeeper, 'keeper_of_secrets');
  end if;

  -- First Among Equals
  select player_id into v_global_top
  from public.player_totals
  where total_points >= 50
  order by total_points desc, player_id asc
  limit 1;

  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'first_among_equals'
    and (v_global_top is null or pa.player_id <> v_global_top);

  if v_global_top is not null then
    perform public._grant_award(v_global_top, 'first_among_equals');
  end if;

  -- Standard Bearer
  delete from public.player_awards pa
  using public.awards a
  where pa.award_id = a.id
    and a.key = 'standard_bearer'
    and pa.player_id not in (
      select distinct on (faction_id) player_id
      from public.player_totals
      where faction_id is not null and total_points >= 30
      order by faction_id, total_points desc, player_id asc
    );

  for r in
    select distinct on (faction_id) player_id
    from public.player_totals
    where faction_id is not null and total_points >= 30
    order by faction_id, total_points desc, player_id asc
  loop
    perform public._grant_award(r.player_id, 'standard_bearer');
  end loop;
end $$;

-- ---------- 6. RENAME EXISTING BADGE KEY ----------
-- The existing `loremaster` badge (10 written entries, honoured tier) is
-- renamed to `master_scribe` so its key doesn't collide with the new
-- `loremaster` submission type. Player_awards rows reference the badge by id,
-- so earned badges survive the rename.
update public.awards
set key = 'master_scribe'
where key = 'loremaster';
