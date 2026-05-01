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
