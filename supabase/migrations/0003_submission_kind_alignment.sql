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
create or replace view public.activity_feed as
select
  s.id                              as submission_id,
  case s.type
    when 'game'  then 'battle'
    when 'model' then 'painted'
    else s.type::text
  end                               as kind,
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
