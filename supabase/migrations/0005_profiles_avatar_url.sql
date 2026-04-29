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
