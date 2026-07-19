-- ============================================================================
-- 0017_multiplayer_battles.sql
--
-- Issue #52: multiplayer battle submissions.
--
-- A battle report may now declare additional registered players on either
-- side (2v2, 3v2, uneven sides are fine). Each listed player:
--   * earns FULL glory for their own result (win/loss/draw from the point
--     scheme) — an uneven side simply banks more faction glory, which is the
--     point of a social campaign;
--   * gets their ELO updated, rated against the AVERAGE rating of the
--     opposing team (the submitter's team average is used for opponents);
--   * receives a mirror submission on approval, exactly like the linked
--     adversary does in 1v1 battles.
--
-- Also per the issue: the home-page activity feed must stop showing mirror
-- rows (dupes of the original report) — for old 1v1 battles and new
-- multiplayer ones alike. Mirrors still show on player profiles. We expose
-- submissions.mirror_of through activity_feed and let the home feed filter
-- on it; the profile page query is unchanged.
--
-- Schema:
--   1. submissions.is_multiplayer flag.
--   2. battle_participants table (registered players only — the social
--      mechanics all require an account; unregistered opponents can still be
--      named in the description).
--   3. The one-mirror-per-original unique index becomes one-mirror-per-
--      (original, player) so a multiplayer approval can fan out.
--   4. award_points_on_approval gains a multiplayer branch.
--   5. activity_feed rebuilt with mirror_of + is_multiplayer.
--   6. battle_participants_view for display (joins profiles + factions).
-- ============================================================================


-- ---------- 1. is_multiplayer flag ----------
alter table public.submissions
  add column if not exists is_multiplayer boolean not null default false;


-- ---------- 2. battle_participants ----------
-- side: 'ally' fought alongside the submitter, 'opponent' fought against.
-- The submitter themself is NOT a row here — they are the submission.
create table if not exists public.battle_participants (
  id            uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  faction_id    uuid not null references public.factions(id) on delete cascade,
  side          text not null check (side in ('ally', 'opponent')),
  elo_delta     int  not null default 0,
  created_at    timestamptz not null default now(),
  unique (submission_id, user_id)
);

create index if not exists idx_battle_participants_submission
  on public.battle_participants(submission_id);
create index if not exists idx_battle_participants_user
  on public.battle_participants(user_id);

alter table public.battle_participants enable row level security;

-- Participant rosters are display data (names/factions/sides), same
-- sensitivity as searchable_players — readable by everyone.
drop policy if exists "battle_participants readable" on public.battle_participants;
create policy "battle_participants readable"
  on public.battle_participants for select
  using (true);

-- The submitter manages the roster while the report is still pending.
drop policy if exists "battle_participants owner insert" on public.battle_participants;
create policy "battle_participants owner insert"
  on public.battle_participants for insert
  with check (
    exists (
      select 1 from public.submissions s
      where s.id = submission_id
        and s.player_id = auth.uid()
        and s.status = 'pending'
    )
  );

drop policy if exists "battle_participants owner delete" on public.battle_participants;
create policy "battle_participants owner delete"
  on public.battle_participants for delete
  using (
    exists (
      select 1 from public.submissions s
      where s.id = submission_id
        and s.player_id = auth.uid()
        and s.status = 'pending'
    )
  );

drop policy if exists "battle_participants admin all" on public.battle_participants;
create policy "battle_participants admin all"
  on public.battle_participants for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

grant select on public.battle_participants to anon, authenticated;


-- ---------- 3. Allow one mirror per (original, player) ----------
-- 0004 enforced a single mirror per original; multiplayer needs one per
-- participant. The (mirror_of, player_id) pair keeps re-approvals idempotent.
drop index if exists public.submissions_mirror_of_unique_idx;

create unique index if not exists submissions_mirror_player_unique_idx
  on public.submissions (mirror_of, player_id)
  where mirror_of is not null;


-- ---------- 4. REPLACE TRIGGER ----------
-- Diff vs 0015's version:
--   * v_is_multi detection: is_multiplayer flag + at least one participant
--     row (excluding any stray self-row).
--   * Section 2b: participant faction glory (each player's own result's
--     scheme points) replaces the single-adversary glory when multiplayer.
--   * Section 4: multiplayer ELO — every player is rated against the average
--     rating of the opposing team; if the opposing team has no registered
--     players, elo_config.starting_elo stands in (same as the unlinked 1v1
--     rule). Deltas are stored on battle_participants.elo_delta.
--   * Section 5: one mirror submission per participant.
--   * Section 6: award evaluation runs for every participant.
-- The 1v1 paths are verbatim from 0015.
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

    -- 5) Mirror submissions.
    if v_is_multi then
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

    -- 6) Award evaluation.
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

    new.reviewed_at := coalesce(new.reviewed_at, now());
  end if;

  return new;
end;
$function$;


-- ---------- 5. Rebuild activity_feed with mirror_of + is_multiplayer ----------
-- Definition mirrors 0013 plus the two new columns. The home feed filters
-- mirror_of IS NULL; the player profile keeps showing mirrors.
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
  s.lore_title,
  s.lore_format,
  s.lore_rating,
  s.mirror_of,
  s.is_multiplayer,
  p.id                              as user_id,
  coalesce(p.display_name, 'Unknown Commander') as display_name,
  p.avatar_url,
  f.id                              as faction_id,
  f.name                            as faction_name,
  f.color                           as faction_color,
  f.emblem_url                      as faction_emblem_url,
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


-- ---------- 6. Display view for participant rosters ----------
-- battle_participants references auth.users, so PostgREST can't follow a
-- join to profiles automatically. This view does the join server-side.
create or replace view public.battle_participants_view as
select
  bp.id,
  bp.submission_id,
  bp.user_id,
  bp.side,
  bp.elo_delta,
  p.display_name,
  p.avatar_url,
  f.id    as faction_id,
  f.name  as faction_name,
  f.color as faction_color,
  f.emblem_url as faction_emblem_url
from public.battle_participants bp
left join public.profiles p on p.id = bp.user_id
left join public.factions f on f.id = bp.faction_id;

grant select on public.battle_participants_view to anon, authenticated;
