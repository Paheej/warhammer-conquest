-- ============================================================================
-- 0020_admin_ledger_rebuild.sql
--
-- Admin tool: correct an already-approved report and recalculate everything
-- derived from it (ELO, planet glory, planet control, mirror rows).
--
-- ELO and glory are applied exactly once, by award_points_on_approval, when a
-- submission flips to 'approved'. Editing an approved row afterwards changes
-- nothing downstream, and ELO is path-dependent (each game's delta depends on
-- the ratings left by every earlier game), so a one-row patch is not enough.
--
-- The rebuild therefore replays history through the real trigger:
--   1. Wipe elo_ratings, planet_points, planet_flip_log and planet control.
--   2. Park every approved row (originals + mirrors) as 'pending'.
--   3. Re-approve originals one by one in reviewed_at order (each followed by
--      its mirrors), so the trigger sees exactly the state it saw originally.
--   4. Sync mirror rows from their originals, restore historical timestamps
--      on the flip log / planet claims, then evaluate awards once.
--
-- The app.ledger_replay GUC tells the triggers to skip mirror creation (they
-- already exist) and per-row award evaluation (done once at the end).
--
-- Every public entry point takes p_dry_run (default true): the work runs in a
-- subtransaction that is rolled back, returning the diff as a preview.
--
-- Awards are grant-only except the competitive titles, so an award granted
-- off a mistaken report is not revoked by a rebuild.
-- ============================================================================


-- ---------- 1. Approval trigger: replay guard ----------
-- Body is 0017's verbatim, plus v_replay and the two guarded sections.
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
  v_is_multi      boolean := false;
  v_part          record;
  v_part_result   text;
  v_part_points   int;
  v_part_score    numeric;
  v_part_rating   int;
  v_part_delta    int;
  v_ally_sum      bigint;
  v_ally_cnt      int;
  v_opp_sum       bigint;
  v_opp_cnt       int;
  v_ally_avg      int;
  v_opp_avg       int;
  -- Set by admin_rebuild_ledger(): skip mirrors + awards while replaying.
  v_replay        boolean := coalesce(current_setting('app.ledger_replay', true), '') = 'on';
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

    v_is_multi := coalesce(new.is_multiplayer, false)
      and new.type = 'game'
      and new.result is not null
      and exists (
        select 1 from public.battle_participants bp
        where bp.submission_id = new.id
          and bp.user_id <> new.player_id
      );

    -- 1v1 mirror precompute (multiplayer handles its own mirrors in 5b).
    if not v_is_multi
       and new.type = 'game'
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

      if not v_is_multi then
        -- 2) 1v1 adversary glory equal to their commander's result points.
        if new.adversary_faction_id is not null
           and new.adversary_faction_id <> v_submitter_faction
           and v_mirror_points > 0 then

          insert into public.planet_points (planet_id, faction_id, points)
          values (new.target_planet_id, new.adversary_faction_id, v_mirror_points)
          on conflict (planet_id, faction_id)
          do update set points = public.planet_points.points + excluded.points;
        end if;
      else
        -- 2b) Multiplayer: every listed player banks their own result's
        -- scheme points for their designated faction. Allies share the
        -- submitter's result; opponents get the opposite.
        for v_part in
          select * from public.battle_participants
          where submission_id = new.id and user_id <> new.player_id
        loop
          v_part_result := case when v_part.side = 'ally'
                                then new.result
                                else public.opposite_result(new.result) end;
          if v_part_result is not null then
            select coalesce(ps.points, 0) into v_part_points
            from public.point_schemes ps
            where ps.game_system_id = new.game_system_id
              and ps.game_size      = coalesce(new.game_size, 'n/a')
              and ps.result         = v_part_result
            limit 1;
            v_part_points := coalesce(v_part_points, 0);

            if v_part_points > 0 then
              insert into public.planet_points (planet_id, faction_id, points)
              values (new.target_planet_id, v_part.faction_id, v_part_points)
              on conflict (planet_id, faction_id)
              do update set points = public.planet_points.points + excluded.points;
            end if;
          end if;
        end loop;
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

        if v_is_multi then
          -- 4b) Multiplayer ELO. Seed every rating row, average per team
          -- (ally team includes the submitter), then rate each player
          -- against the opposing team's average.
          v_sub_rating := public.get_or_create_elo(new.player_id, new.game_system_id, new.faction_id, v_vg_id);
          v_ally_sum := v_sub_rating;
          v_ally_cnt := 1;
          v_opp_sum  := 0;
          v_opp_cnt  := 0;

          for v_part in
            select * from public.battle_participants
            where submission_id = new.id and user_id <> new.player_id
          loop
            v_part_rating := public.get_or_create_elo(v_part.user_id, new.game_system_id, v_part.faction_id, v_vg_id);
            if v_part.side = 'ally' then
              v_ally_sum := v_ally_sum + v_part_rating;
              v_ally_cnt := v_ally_cnt + 1;
            else
              v_opp_sum := v_opp_sum + v_part_rating;
              v_opp_cnt := v_opp_cnt + 1;
            end if;
          end loop;

          v_ally_avg := round(v_ally_sum::numeric / v_ally_cnt)::int;
          if v_opp_cnt > 0 then
            v_opp_avg := round(v_opp_sum::numeric / v_opp_cnt)::int;
          else
            select coalesce(starting_elo, 1200) into v_opp_avg
            from public.elo_config
            where game_system_id = new.game_system_id;
            v_opp_avg := coalesce(v_opp_avg, 1200);
          end if;

          v_delta_sub := public.calc_elo_delta(v_sub_rating, v_opp_avg, v_score, v_k);

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

          for v_part in
            select * from public.battle_participants
            where submission_id = new.id and user_id <> new.player_id
          loop
            v_part_result := case when v_part.side = 'ally'
                                  then new.result
                                  else public.opposite_result(new.result) end;
            if v_part_result is null then
              continue;
            end if;
            v_part_score := case v_part_result
              when 'win'  then 1.0
              when 'draw' then 0.5
              else 0.0
            end;

            select rating into v_part_rating
            from public.elo_ratings
            where user_id = v_part.user_id
              and game_system_id = new.game_system_id
              and faction_id = v_part.faction_id
              and video_game_title_id is not distinct from v_vg_id;
            v_part_rating := coalesce(v_part_rating, 1200);

            v_part_delta := public.calc_elo_delta(
              v_part_rating,
              case when v_part.side = 'ally' then v_opp_avg else v_ally_avg end,
              v_part_score,
              v_k
            );

            update public.elo_ratings
              set rating = rating + v_part_delta,
                  games_played = games_played + 1,
                  wins   = wins   + (case when v_part_result = 'win'  then 1 else 0 end),
                  losses = losses + (case when v_part_result = 'loss' then 1 else 0 end),
                  draws  = draws  + (case when v_part_result = 'draw' then 1 else 0 end),
                  updated_at = now()
            where user_id = v_part.user_id
              and game_system_id = new.game_system_id
              and faction_id = v_part.faction_id
              and video_game_title_id is not distinct from v_vg_id;

            update public.battle_participants
            set elo_delta = v_part_delta
            where id = v_part.id;
          end loop;

        elsif new.adversary_user_id is not null
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

    -- 5) Mirror submissions (mirrors already exist during a ledger replay).
    if v_replay then
      null;
    elsif v_is_multi then
      -- 5b) One mirror per participant. INSERT doesn't fire this BEFORE
      -- UPDATE trigger, so mirrors stay ledger-inert; the loops above
      -- already handled glory and ELO for everyone. Participant rows are
      -- re-read here so elo_delta reflects the update in section 4b.
      for v_part in
        select * from public.battle_participants
        where submission_id = new.id and user_id <> new.player_id
      loop
        v_part_result := case when v_part.side = 'ally'
                              then new.result
                              else public.opposite_result(new.result) end;
        if v_part_result is null then
          continue;
        end if;

        select coalesce(ps.points, 0) into v_part_points
        from public.point_schemes ps
        where ps.game_system_id = new.game_system_id
          and ps.game_size      = coalesce(new.game_size, 'n/a')
          and ps.result         = v_part_result
        limit 1;
        v_part_points := coalesce(v_part_points, 0);

        if not exists (
          select 1 from public.submissions m
          where m.mirror_of = new.id and m.player_id = v_part.user_id
        ) then
          insert into public.submissions (
            player_id, faction_id, target_planet_id, type, title, body,
            image_url, opponent_name, result, points, status, reviewed_by,
            reviewed_at, review_notes, game_system_id, game_size,
            video_game_title_id, adversary_user_id, adversary_faction_id,
            elo_delta, adversary_elo_delta, mirror_of, is_multiplayer
          ) values (
            v_part.user_id,
            v_part.faction_id,
            new.target_planet_id,
            new.type,
            new.title,
            new.body,
            new.image_url,
            case when v_part.side = 'ally' then new.opponent_name else null end,
            v_part_result,
            v_part_points,
            'approved',
            new.reviewed_by,
            coalesce(new.reviewed_at, now()),
            new.review_notes,
            new.game_system_id,
            new.game_size,
            new.video_game_title_id,
            case when v_part.side = 'opponent' then new.player_id else null end,
            case when v_part.side = 'opponent' then new.faction_id else null end,
            v_part.elo_delta,
            case when v_part.side = 'opponent' then v_delta_sub else null end,
            new.id,
            true
          );
        end if;
      end loop;

    elsif v_mirror_result is not null
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

    -- 6) Award evaluation (run once at the end of a ledger replay instead).
    if not v_replay then
    perform public.evaluate_player_awards(new.player_id);
    if new.adversary_user_id is not null then
      perform public.evaluate_player_awards(new.adversary_user_id);
    end if;
    if v_is_multi then
      for v_part in
        select distinct user_id from public.battle_participants
        where submission_id = new.id and user_id <> new.player_id
      loop
        perform public.evaluate_player_awards(v_part.user_id);
      end loop;
    end if;
    perform public.evaluate_competitive_awards();
    end if;

    new.reviewed_at := coalesce(new.reviewed_at, now());
  end if;

  return new;
end;
$function$;


create or replace function public.evaluate_awards_after_approval()
 returns trigger
 language plpgsql
 security definer
as $function$
begin
  if new.mirror_of is not null then
    return null;
  end if;

  if coalesce(current_setting('app.ledger_replay', true), '') = 'on' then
    return null;
  end if;

  if new.status = 'approved'
     and (old.status is null or old.status <> 'approved') then
    perform public.evaluate_player_awards(new.player_id);
    if new.adversary_user_id is not null then
      perform public.evaluate_player_awards(new.adversary_user_id);
    end if;
    perform public.evaluate_competitive_awards();
  end if;

  return null;
end $function$;


-- ---------- 2. Internal helpers (not callable from the API) ----------

create or replace function public._assert_admin()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.profiles where id = auth.uid() and is_admin = true
  ) then
    raise exception 'Only administrators may recalculate the ledger';
  end if;
end $$;

-- Everything a rebuild can change, keyed for diffing.
create or replace function public._ledger_snapshot()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'elo', coalesce((
      select jsonb_object_agg(
        e.user_id || '|' || e.game_system_id || '|' || e.faction_id || '|' || coalesce(e.video_game_title_id::text, ''),
        jsonb_build_object('rating', e.rating, 'games', e.games_played,
                           'wins', e.wins, 'losses', e.losses, 'draws', e.draws))
      from public.elo_ratings e), '{}'::jsonb),
    'glory', coalesce((
      select jsonb_object_agg(pp.planet_id || '|' || pp.faction_id, pp.points)
      from public.planet_points pp where pp.points <> 0), '{}'::jsonb),
    'control', coalesce((
      select jsonb_object_agg(p.id::text, p.controlling_faction_id)
      from public.planets p), '{}'::jsonb),
    'subs', coalesce((
      select jsonb_object_agg(s.id::text, jsonb_build_array(
        s.elo_delta, s.adversary_elo_delta, s.faction_id, s.adversary_faction_id, s.result, s.points))
      from public.submissions s where s.status = 'approved'), '{}'::jsonb)
  );
$$;

-- Human-readable diff between two snapshots.
create or replace function public._ledger_diff(a jsonb, b jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with
  elo as (
    select coalesce(o.key, n.key) k, o.value ov, n.value nv
    from jsonb_each(a->'elo') o
    full join jsonb_each(b->'elo') n on n.key = o.key
    where o.value is distinct from n.value
  ),
  elo_rows as (
    select
      pr.display_name                         as player,
      gs.name                                 as game_system,
      f.name                                  as faction,
      vg.name                                 as video_game,
      (ov->>'rating')::int                    as old_rating,
      (nv->>'rating')::int                    as new_rating,
      coalesce(ov->>'wins','0') || '-' || coalesce(ov->>'losses','0') || '-' || coalesce(ov->>'draws','0') as old_record,
      coalesce(nv->>'wins','0') || '-' || coalesce(nv->>'losses','0') || '-' || coalesce(nv->>'draws','0') as new_record
    from elo
    left join public.profiles pr          on pr.id::text = split_part(k, '|', 1)
    left join public.game_systems gs      on gs.id       = split_part(k, '|', 2)
    left join public.factions f           on f.id::text  = split_part(k, '|', 3)
    left join public.video_game_titles vg on vg.id::text = nullif(split_part(k, '|', 4), '')
  ),
  glory as (
    select coalesce(o.key, n.key) k, (o.value)::text::int ov, (n.value)::text::int nv
    from jsonb_each(a->'glory') o
    full join jsonb_each(b->'glory') n on n.key = o.key
    where o.value is distinct from n.value
  ),
  glory_rows as (
    select pl.name as planet, f.name as faction, coalesce(ov, 0) as old_points, coalesce(nv, 0) as new_points
    from glory
    left join public.planets pl on pl.id::text = split_part(k, '|', 1)
    left join public.factions f on f.id::text  = split_part(k, '|', 2)
  ),
  ctl as (
    select o.key k, o.value #>> '{}' ov, n.value #>> '{}' nv
    from jsonb_each(a->'control') o
    join jsonb_each(b->'control') n on n.key = o.key
    where o.value is distinct from n.value
  ),
  ctl_rows as (
    select pl.name as planet, fo.name as old_controller, fn.name as new_controller
    from ctl
    left join public.planets pl  on pl.id::text = k
    left join public.factions fo on fo.id::text = ov
    left join public.factions fn on fn.id::text = nv
  ),
  subs as (
    select count(*) c
    from jsonb_each(a->'subs') o
    full join jsonb_each(b->'subs') n on n.key = o.key
    where o.value is distinct from n.value
  )
  select jsonb_build_object(
    'elo', coalesce((select jsonb_agg(to_jsonb(r) order by abs(coalesce(r.new_rating,0) - coalesce(r.old_rating,0)) desc, r.player)
                     from elo_rows r), '[]'::jsonb),
    'glory', coalesce((select jsonb_agg(to_jsonb(r) order by r.planet, r.faction) from glory_rows r), '[]'::jsonb),
    'control', coalesce((select jsonb_agg(to_jsonb(r) order by r.planet) from ctl_rows r), '[]'::jsonb),
    'submissions_changed', (select c from subs)
  );
$$;

-- The replay itself. Caller is responsible for auth and transaction shape.
create or replace function public._rebuild_ledger()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
  r     record;
begin
  -- Block concurrent approvals for the duration (self-conflicting mode, so
  -- two rebuilds also serialize).
  lock table public.submissions in share row exclusive mode;

  perform set_config('app.ledger_replay', 'on', true);

  -- `where true` satisfies pg_safeupdate (see 0012).
  delete from public.elo_ratings     where true;
  delete from public.planet_flip_log where true;
  delete from public.planet_points   where true;
  update public.planets
     set controlling_faction_id = null, claimed_at = null
   where controlling_faction_id is not null or claimed_at is not null;
  update public.battle_participants set elo_delta = 0 where elo_delta <> 0;

  select array_agg(id) into v_ids from public.submissions where status = 'approved';
  if v_ids is null then
    perform set_config('app.ledger_replay', 'off', true);
    return;
  end if;

  -- Park everything. Neither trigger acts on a move away from 'approved'.
  update public.submissions
     set status = 'pending', elo_delta = 0, adversary_elo_delta = 0
   where id = any(v_ids);

  for r in
    select id from public.submissions
    where id = any(v_ids) and mirror_of is null
    order by reviewed_at nulls first, created_at, id
  loop
    update public.submissions set status = 'approved' where id = r.id;
    update public.submissions set status = 'approved'
     where mirror_of = r.id and id = any(v_ids);
  end loop;

  -- Orphan mirrors (original no longer approved) go back as they were.
  update public.submissions set status = 'approved'
   where id = any(v_ids) and status = 'pending';

  -- 1v1 mirrors follow their original.
  update public.submissions m
     set faction_id          = o.adversary_faction_id,
         adversary_faction_id = o.faction_id,
         result              = public.opposite_result(o.result),
         -- SET sees the pre-update row, so this only fires on a result change.
         points              = case
                                 when m.result is distinct from public.opposite_result(o.result) then
                                   coalesce((select ps.points from public.point_schemes ps
                                             where ps.game_system_id = o.game_system_id
                                               and ps.game_size      = coalesce(o.game_size, 'n/a')
                                               and ps.result         = public.opposite_result(o.result)
                                             limit 1), 0)
                                 else m.points
                               end,
         elo_delta           = o.adversary_elo_delta,
         adversary_elo_delta = o.elo_delta
    from public.submissions o
   where m.mirror_of = o.id
     and not coalesce(o.is_multiplayer, false)
     and m.player_id = o.adversary_user_id
     and o.adversary_faction_id is not null;

  -- Multiplayer mirrors follow the roster.
  update public.submissions m
     set faction_id          = bp.faction_id,
         elo_delta           = bp.elo_delta,
         adversary_faction_id = case when bp.side = 'opponent' then o.faction_id else null end,
         adversary_elo_delta = case when bp.side = 'opponent' then o.elo_delta  else null end
    from public.submissions o
    join public.battle_participants bp on bp.submission_id = o.id
   where m.mirror_of = o.id
     and coalesce(o.is_multiplayer, false)
     and bp.user_id = m.player_id;

  -- Replayed flips/claims carry now(); restore the historical moment.
  update public.planet_flip_log fl
     set created_at = coalesce(s.reviewed_at, s.created_at)
    from public.submissions s
   where s.id = fl.trigger_submission_id;

  update public.planets p
     set claimed_at = f.first_flip
    from (select planet_id, min(created_at) first_flip
          from public.planet_flip_log group by planet_id) f
   where f.planet_id = p.id
     and p.controlling_faction_id is not null;

  perform set_config('app.ledger_replay', 'off', true);

  perform public.evaluate_player_awards(id) from public.profiles;
  perform public.evaluate_competitive_awards();
end $$;

revoke all on function public._assert_admin()            from public, anon, authenticated;
revoke all on function public._ledger_snapshot()         from public, anon, authenticated;
revoke all on function public._ledger_diff(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public._rebuild_ledger()          from public, anon, authenticated;


-- ---------- 3. Public RPCs ----------

-- Full recalculation from the approved history.
create or replace function public.admin_rebuild_ledger(p_dry_run boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
  v_diff   jsonb;
begin
  perform public._assert_admin();
  v_before := public._ledger_snapshot();

  begin
    perform public._rebuild_ledger();
    v_diff := public._ledger_diff(v_before, public._ledger_snapshot());
    if p_dry_run then
      raise exception using errcode = 'LD001', message = 'ledger dry run';
    end if;
  exception when sqlstate 'LD001' then
    null;  -- subtransaction rolled back; v_diff survives
  end;

  return v_diff || jsonb_build_object('dry_run', p_dry_run);
end $$;

-- Correct an approved original report, then recalculate.
create or replace function public.admin_correct_submission(
  p_submission_id        uuid,
  p_faction_id           uuid,
  p_adversary_faction_id uuid,
  p_result               text,
  p_points               int,
  p_dry_run              boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub    public.submissions%rowtype;
  v_before jsonb;
  v_diff   jsonb;
begin
  perform public._assert_admin();

  select * into v_sub from public.submissions where id = p_submission_id;
  if not found then
    raise exception 'Submission not found';
  end if;
  if v_sub.status <> 'approved' or v_sub.mirror_of is not null then
    raise exception 'Only approved original reports can be corrected (edit the original, not its mirror)';
  end if;
  if p_points is null or p_points < 0 then
    raise exception 'Points must be zero or more';
  end if;

  if v_sub.type = 'game' then
    if p_result is null or p_result not in ('win', 'loss', 'draw') then
      raise exception 'A battle result must be win, loss or draw';
    end if;
    if v_sub.adversary_user_id is not null and p_adversary_faction_id is null then
      raise exception 'Pick which faction the linked opponent fielded';
    end if;
    if v_sub.adversary_user_id is null and p_adversary_faction_id is distinct from v_sub.adversary_faction_id then
      raise exception 'Opponent faction can only be changed for a linked opponent';
    end if;
  else
    p_result := v_sub.result;
    p_adversary_faction_id := v_sub.adversary_faction_id;
  end if;

  v_before := public._ledger_snapshot();

  begin
    update public.submissions
       set faction_id           = p_faction_id,
           adversary_faction_id = p_adversary_faction_id,
           result               = p_result,
           points               = p_points
     where id = p_submission_id;

    perform public._rebuild_ledger();
    v_diff := public._ledger_diff(v_before, public._ledger_snapshot());
    if p_dry_run then
      raise exception using errcode = 'LD001', message = 'ledger dry run';
    end if;
  exception when sqlstate 'LD001' then
    null;
  end;

  return v_diff || jsonb_build_object('dry_run', p_dry_run);
end $$;

revoke all on function public.admin_rebuild_ledger(boolean) from public, anon;
revoke all on function public.admin_correct_submission(uuid, uuid, uuid, text, int, boolean) from public, anon;
grant execute on function public.admin_rebuild_ledger(boolean) to authenticated;
grant execute on function public.admin_correct_submission(uuid, uuid, uuid, text, int, boolean) to authenticated;
