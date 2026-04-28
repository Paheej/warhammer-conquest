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
