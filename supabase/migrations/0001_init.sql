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
