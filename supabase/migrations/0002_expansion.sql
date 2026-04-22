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
  add column if not exists result                text check (result in ('loss','draw','win')),
  add column if not exists elo_delta             int default 0,
  add column if not exists adversary_elo_delta   int default 0;

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
      from public.profiles where id = new.user_id;
    end if;

    -- 1) Submitter glory on planet
    if new.planet_id is not null and v_submitter_faction is not null and coalesce(new.points, 0) > 0 then
      insert into public.planet_points (planet_id, faction_id, points)
      values (new.planet_id, v_submitter_faction, new.points)
      on conflict (planet_id, faction_id)
      do update set points = public.planet_points.points + excluded.points;

      -- 2) Adversary glory (half, rounded up) if linked
      if new.adversary_user_id is not null
         and new.adversary_faction_id is not null
         and new.adversary_faction_id <> v_submitter_faction then

        v_adv_points := greatest(1, ceil(new.points / 2.0)::int);

        insert into public.planet_points (planet_id, faction_id, points)
        values (new.planet_id, new.adversary_faction_id, v_adv_points)
        on conflict (planet_id, faction_id)
        do update set points = public.planet_points.points + excluded.points;
      end if;

      -- 3) Planet threshold / control flip check
      select claim_threshold, controlling_faction_id into v_threshold, v_submitter_faction
      from public.planets where id = new.planet_id;

      select coalesce(max(points),0) into v_current
      from public.planet_points
      where planet_id = new.planet_id;

      select faction_id into v_submitter_faction
      from public.planet_points
      where planet_id = new.planet_id
      order by points desc
      limit 1;

      if v_current >= coalesce(v_threshold, 0) then
        update public.planets
        set controlling_faction_id = v_submitter_faction
        where id = new.planet_id;
      end if;
    end if;

    -- 4) ELO update for battle submissions with an adversary
    if new.kind = 'battle'
       and new.game_system_id is not null
       and new.adversary_user_id is not null
       and new.adversary_faction_id is not null
       and new.result is not null
       and new.faction_id is not null then

      select coalesce(k_factor, 32) into v_k
      from public.elo_config
      where game_system_id = new.game_system_id;
      v_k := coalesce(v_k, 32);

      v_sub_rating := public.get_or_create_elo(new.user_id, new.game_system_id, new.faction_id);
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
      where user_id = new.user_id
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

-- Replace the existing trigger (ignore if it doesn't exist)
drop trigger if exists award_points_on_approval_trg on public.submissions;
create trigger award_points_on_approval_trg
  before update on public.submissions
  for each row execute function public.award_points_on_approval();


-- ---------------------------------------------------------------------
-- 12. Activity feed view
-- ---------------------------------------------------------------------
-- Exposes only APPROVED submissions for public feed display, joined
-- with display-friendly names.
create or replace view public.activity_feed as
select
  s.id                              as submission_id,
  s.kind,
  s.status,
  s.created_at,
  s.title,
  s.description,
  s.image_url,
  s.points,
  s.result,
  s.game_size,
  p.id                              as user_id,
  coalesce(p.display_name, 'Unknown Commander') as display_name,
  p.avatar_url,
  f.id                              as faction_id,
  f.name                            as faction_name,
  f.color                           as faction_color,
  pl.id                             as planet_id,
  pl.name                           as planet_name,
  gs.id                             as game_system_id,
  gs.short_name                     as game_system_short,
  gs.name                           as game_system_name,
  adv.id                            as adversary_user_id,
  adv.display_name                  as adversary_name,
  advf.name                         as adversary_faction_name,
  advf.color                        as adversary_faction_color,
  vgt.name                          as video_game_name
from public.submissions s
left join public.profiles    p    on p.id = s.user_id
left join public.factions    f    on f.id = s.faction_id
left join public.planets     pl   on pl.id = s.planet_id
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
  p.avatar_url,
  p.faction_id as primary_faction_id,
  f.name       as primary_faction_name
from public.profiles p
left join public.factions f on f.id = p.faction_id
where p.display_name is not null;

grant select on public.searchable_players to anon, authenticated;


-- ---------------------------------------------------------------------
-- Done.
-- ---------------------------------------------------------------------
