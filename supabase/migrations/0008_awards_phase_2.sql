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
