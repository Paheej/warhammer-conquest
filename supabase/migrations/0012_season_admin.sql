-- ============================================================================
-- 0012_season_admin.sql
--
-- Season Administration: a single SECURITY DEFINER RPC that wipes all
-- campaign-generated data so a fresh season can begin without dropping users
-- or rebuilding the catalogue.
--
--   * Keeps: profiles, factions, planets (rows themselves), awards catalogue,
--            game_systems, point_schemes, video_game_titles, planet_game_systems,
--            player_factions, elo_config.
--   * Wipes: submissions, planet_points, planet_flip_log, player_awards,
--            elo_ratings.
--   * Resets: planets.controlling_faction_id = null, planets.claimed_at = null.
--
-- Caller must be an admin (`profiles.is_admin = true`); checked inside the
-- function so the SECURITY DEFINER context cannot be abused.
-- ============================================================================

create or replace function public.admin_clear_campaign()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and is_admin = true
  ) then
    raise exception 'Only administrators may clear the campaign';
  end if;

  -- Order matters only for FKs without cascade; most of these cascade from
  -- submissions/planets, but explicit deletes keep intent obvious.
  -- `where true` satisfies pg_safeupdate, which Supabase loads for API roles
  -- and which rejects bare DELETE/UPDATE even inside SECURITY DEFINER bodies.
  delete from public.elo_ratings      where true;
  delete from public.planet_flip_log  where true;
  delete from public.player_awards    where true;
  delete from public.planet_points    where true;
  delete from public.submissions      where true;

  update public.planets
  set controlling_faction_id = null,
      claimed_at             = null
  where controlling_faction_id is not null
     or claimed_at is not null;
end $$;

revoke all on function public.admin_clear_campaign() from public;
grant execute on function public.admin_clear_campaign() to authenticated;
