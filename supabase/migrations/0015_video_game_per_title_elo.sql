-- ============================================================================
-- 0015_video_game_per_title_elo.sql
--
-- Issue #49: ELO ratings for video games were lumped together under a single
-- game_system_id = 'video' rating, regardless of which video game was played.
-- That collapsed Dawn of War, Battlesector, Space Marine 2 etc. into one
-- combined ladder. Tabletop systems remain one rating per (player, system,
-- faction) — they are themselves distinct rule sets.
--
-- This migration:
--   1. Adds `video_game_title_id` to elo_ratings (nullable; only set when the
--      ELO row is for a video-game match).
--   2. Replaces the primary key with a unique index using NULLS NOT DISTINCT
--      (PG 15+) so the NULL on non-video rows is treated as a real value and
--      collisions on (user, system, faction) are still prevented.
--   3. Extends get_or_create_elo() with a video_game_title_id parameter.
--   4. Replaces award_points_on_approval to pass video_game_title_id through
--      to the ELO functions when game_system_id = 'video'.
--   5. Backfills: deletes existing 'video' elo_ratings rows (they pooled all
--      titles together and can't be deconvolved), then replays every approved
--      video-game submission in created_at order to rebuild per-title ratings.
--
-- All non-video systems are unchanged.
-- ============================================================================


-- ---------- 1. NEW COLUMN ----------
alter table public.elo_ratings
  add column if not exists video_game_title_id bigint
  references public.video_game_titles(id) on delete cascade;

create index if not exists idx_elo_video_game on public.elo_ratings(video_game_title_id);


-- ---------- 2. REPLACE PK WITH UNIQUE INDEX (NULLS NOT DISTINCT) ----------
-- Drop the old PK that ignored video_game_title_id. We use a unique index with
-- NULLS NOT DISTINCT instead of a new PK because PostgreSQL forbids NULLs in
-- primary key columns, and we want one row per non-video tabletop system to
-- continue using video_game_title_id = NULL.
alter table public.elo_ratings
  drop constraint if exists elo_ratings_pkey;

drop index if exists elo_ratings_unique_idx;

create unique index elo_ratings_unique_idx
  on public.elo_ratings (user_id, game_system_id, faction_id, video_game_title_id)
  nulls not distinct;


-- ---------- 3. EXTEND get_or_create_elo ----------
-- Backwards-compatible: existing 3-arg callers continue to work because we
-- give video_game_title_id a default of NULL, and PostgreSQL resolves the
-- 4-arg overload only when the caller passes it explicitly.
create or replace function public.get_or_create_elo(
  p_user_id            uuid,
  p_game_system_id     text,
  p_faction_id         uuid,
  p_video_game_title_id bigint default null
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
    and faction_id = p_faction_id
    and video_game_title_id is not distinct from p_video_game_title_id;

  if v_rating is null then
    select coalesce(starting_elo, 1200) into v_start
    from public.elo_config
    where game_system_id = p_game_system_id;

    v_start := coalesce(v_start, 1200);

    insert into public.elo_ratings (user_id, game_system_id, faction_id, video_game_title_id, rating)
    values (p_user_id, p_game_system_id, p_faction_id, p_video_game_title_id, v_start)
    on conflict do nothing;

    v_rating := v_start;
  end if;

  return v_rating;
end;
$$;


-- ---------- 4. REPLACE TRIGGER ----------
-- Diff vs 0008's version: section 4 now derives a v_vg_id from
-- new.video_game_title_id when the game system supports video games, and
-- threads it through every get_or_create_elo and elo_ratings UPDATE in both
-- the linked and unlinked branches. Non-video systems pass NULL, matching
-- their existing rows.
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
  v_supports_vg   boolean;
  v_vg_id         bigint;
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

      select coalesce(supports_video_game, false) into v_supports_vg
      from public.game_systems
      where id = new.game_system_id;
      v_supports_vg := coalesce(v_supports_vg, false);

      v_vg_id := case when v_supports_vg then new.video_game_title_id else null end;

      select coalesce(k_factor, 32) into v_k
      from public.elo_config
      where game_system_id = new.game_system_id;
      v_k := coalesce(v_k, 32);

      v_score := case new.result
        when 'win'  then 1.0
        when 'draw' then 0.5
        when 'loss' then 0.0
      end;

      -- Video games require a title for per-title rating; skip ELO if missing.
      if not v_supports_vg or v_vg_id is not null then

        if new.adversary_user_id is not null
           and new.adversary_faction_id is not null then

          v_sub_rating := public.get_or_create_elo(new.player_id,           new.game_system_id, new.faction_id,           v_vg_id);
          v_adv_rating := public.get_or_create_elo(new.adversary_user_id,   new.game_system_id, new.adversary_faction_id, v_vg_id);

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
            and faction_id = new.faction_id
            and video_game_title_id is not distinct from v_vg_id;

          update public.elo_ratings
            set rating = rating + v_delta_adv,
                games_played = games_played + 1,
                wins   = wins   + (case when new.result = 'loss' then 1 else 0 end),
                losses = losses + (case when new.result = 'win'  then 1 else 0 end),
                draws  = draws  + (case when new.result = 'draw' then 1 else 0 end),
                updated_at = now()
          where user_id = new.adversary_user_id
            and game_system_id = new.game_system_id
            and faction_id = new.adversary_faction_id
            and video_game_title_id is not distinct from v_vg_id;

          new.elo_delta := v_delta_sub;
          new.adversary_elo_delta := v_delta_adv;

        elsif new.adversary_user_id is null
              and new.adversary_faction_id is null then

          v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id, v_vg_id);

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
            and faction_id = new.faction_id
            and video_game_title_id is not distinct from v_vg_id;

          new.elo_delta := v_delta_sub;
        end if;
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

    -- 6) Award evaluation.
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


-- ---------- 5. BACKFILL ----------
-- Existing video-system elo_ratings rows pooled every video game together.
-- We can't deconvolve them, so we wipe them and replay every approved
-- video-game submission in chronological order to rebuild per-title ratings.
-- Non-video systems are untouched.
do $$
declare
  s record;
  v_k          int;
  v_sub_rating int;
  v_adv_rating int;
  v_start      int;
  v_score      numeric;
  v_delta_sub  int;
  v_delta_adv  int;
begin
  -- Wipe pooled video-system ratings. Mirror submissions for video games
  -- share game_system_id = 'video', so we clear the whole partition.
  delete from public.elo_ratings where game_system_id = 'video';

  -- elo_delta and adversary_elo_delta on the submissions themselves were
  -- computed against the pooled rating. Zero them out for video matches so
  -- the David award (which inspects elo_delta) isn't misled by stale values.
  update public.submissions
  set elo_delta = 0,
      adversary_elo_delta = 0
  where game_system_id = 'video';

  -- Replay video matches in time order. Originals only (mirrors are inserted
  -- by the trigger; here we mimic that by handling both sides explicitly).
  select coalesce(k_factor, 32), coalesce(starting_elo, 1200)
    into v_k, v_start
  from public.elo_config where game_system_id = 'video';
  v_k     := coalesce(v_k, 16);
  v_start := coalesce(v_start, 1200);

  for s in
    select sub.*
    from public.submissions sub
    where sub.status = 'approved'
      and sub.type = 'game'
      and sub.game_system_id = 'video'
      and sub.mirror_of is null
      and sub.result is not null
      and sub.faction_id is not null
      and sub.video_game_title_id is not null
    order by sub.created_at, sub.id
  loop
    v_score := case s.result
      when 'win'  then 1.0
      when 'draw' then 0.5
      when 'loss' then 0.0
    end;

    if s.adversary_user_id is not null and s.adversary_faction_id is not null then
      v_sub_rating := public.get_or_create_elo(s.player_id,         'video', s.faction_id,           s.video_game_title_id);
      v_adv_rating := public.get_or_create_elo(s.adversary_user_id, 'video', s.adversary_faction_id, s.video_game_title_id);

      v_delta_sub := public.calc_elo_delta(v_sub_rating, v_adv_rating, v_score, v_k);
      v_delta_adv := -v_delta_sub;

      update public.elo_ratings
        set rating = rating + v_delta_sub,
            games_played = games_played + 1,
            wins   = wins   + (case when s.result = 'win'  then 1 else 0 end),
            losses = losses + (case when s.result = 'loss' then 1 else 0 end),
            draws  = draws  + (case when s.result = 'draw' then 1 else 0 end),
            updated_at = now()
      where user_id = s.player_id
        and game_system_id = 'video'
        and faction_id = s.faction_id
        and video_game_title_id is not distinct from s.video_game_title_id;

      update public.elo_ratings
        set rating = rating + v_delta_adv,
            games_played = games_played + 1,
            wins   = wins   + (case when s.result = 'loss' then 1 else 0 end),
            losses = losses + (case when s.result = 'win'  then 1 else 0 end),
            draws  = draws  + (case when s.result = 'draw' then 1 else 0 end),
            updated_at = now()
      where user_id = s.adversary_user_id
        and game_system_id = 'video'
        and faction_id = s.adversary_faction_id
        and video_game_title_id is not distinct from s.video_game_title_id;

      update public.submissions
      set elo_delta = v_delta_sub,
          adversary_elo_delta = v_delta_adv
      where id = s.id;

    elsif s.adversary_user_id is null and s.adversary_faction_id is null then
      v_sub_rating := public.get_or_create_elo(s.player_id, 'video', s.faction_id, s.video_game_title_id);
      v_delta_sub  := public.calc_elo_delta(v_sub_rating, v_start, v_score, v_k);

      update public.elo_ratings
        set rating = rating + v_delta_sub,
            games_played = games_played + 1,
            wins   = wins   + (case when s.result = 'win'  then 1 else 0 end),
            losses = losses + (case when s.result = 'loss' then 1 else 0 end),
            draws  = draws  + (case when s.result = 'draw' then 1 else 0 end),
            updated_at = now()
      where user_id = s.player_id
        and game_system_id = 'video'
        and faction_id = s.faction_id
        and video_game_title_id is not distinct from s.video_game_title_id;

      update public.submissions
      set elo_delta = v_delta_sub
      where id = s.id;
    end if;
  end loop;
end $$;
