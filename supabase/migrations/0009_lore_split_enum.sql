-- ============================================================================
-- 0009_lore_split_enum.sql
--
-- Issue #31 part 1 of 2: split the `lore` submission type into two distinct
-- types — writing (renamed to `scribe`) and reading/listening (`loremaster`,
-- added in this migration). Issue #31 introduces the reading deed for novels
-- and audiobooks; the existing `lore` enum value semantically meant *writing*
-- fluff, so it's renamed for symmetry.
--
-- This phase ONLY:
--   1. Renames the enum value `lore` → `scribe`.
--   2. Adds the new `loremaster` enum value (cannot be referenced until the
--      next migration commits — Postgres restriction on ALTER TYPE ADD VALUE).
--   3. Recreates `faction_totals` to read `s.type = 'scribe'` and renames the
--      column `lore_submitted` → `lore_written`. The companion `lore_read`
--      column is added in 0010, once `loremaster` is referenceable.
--   4. Updates evaluator functions to use `'scribe'` instead of `'lore'` so
--      existing writing-track awards keep firing.
--   5. Renames the existing badge key `loremaster` → `master_scribe`. The
--      badge name and description are unchanged. This avoids a confusing
--      collision between the badge key and the new submission type, both
--      called `loremaster`.
--
-- 0010 then adds the loremaster-specific columns, the new badges, and the
-- evaluator logic that grants them.
-- ============================================================================

-- ---------- 1. RENAME ENUM VALUE ----------
alter type public.submission_type rename value 'lore' to 'scribe';

-- ---------- 2. ADD NEW ENUM VALUE ----------
-- IMPORTANT: 'loremaster' cannot be referenced in queries within this same
-- transaction. 0010 uses it freely.
alter type public.submission_type add value if not exists 'loremaster';

-- ---------- 3. REBUILD faction_totals VIEW ----------
-- Rename `lore_submitted` → `lore_written` for the writing track. The
-- companion `lore_read` column is added in 0010.
drop view if exists public.faction_totals;

create view public.faction_totals as
  select
    f.id as faction_id,
    f.name as faction_name,
    f.color,
    coalesce(sum(s.points), 0)::int as total_points,
    count(s.id) filter (where s.type = 'game' and s.result = 'win') as wins,
    count(s.id) filter (where s.type = 'model') as models_painted,
    count(s.id) filter (where s.type = 'scribe') as lore_written,
    count(distinct p.id) as planets_controlled
  from public.factions f
  left join public.submissions s
    on s.faction_id = f.id and s.status = 'approved'
  left join public.planets p
    on p.controlling_faction_id = f.id
  group by f.id, f.name, f.color;

grant select on public.faction_totals to anon, authenticated;

-- ---------- 4. UPDATE EVALUATORS TO USE 'scribe' ----------
-- The existing 4 lore-track awards (remembrancer, chronicler, loremaster
-- badge, keeper_of_secrets) all rewarded *written* lore. Re-bind their
-- queries to the renamed enum value.

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

  -- David: any winning linked battle whose ELO delta exceeds K/2
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

  -- Lore (writing track) — type renamed from 'lore' to 'scribe' in 0009.
  -- Badge key renamed from 'loremaster' to 'master_scribe' (same migration).
  select count(*) into v_lore_count
  from public.submissions
  where player_id = p_player_id and type = 'scribe' and status = 'approved';

  if v_lore_count >= 1  then perform public._grant_award(p_player_id, 'remembrancer'); end if;
  if v_lore_count >= 3  then perform public._grant_award(p_player_id, 'chronicler'); end if;
  if v_lore_count >= 10 then perform public._grant_award(p_player_id, 'master_scribe'); end if;

  -- Conquest: Planetfall
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

  -- Holdfast — submission posted after a flip that gave that faction control.
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

-- ---------- 5. UPDATE COMPETITIVE EVALUATOR TO USE 'scribe' ----------
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
  -- Warmaster
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

  -- Painting Daemon
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

  -- Keeper of Secrets — most approved writing-track lore, ≥ 20.
  -- Type renamed from 'lore' to 'scribe' in this migration.
  select player_id into v_lorekeeper
  from (
    select player_id, count(*) as cnt
    from public.submissions
    where type = 'scribe' and status = 'approved'
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

  -- First Among Equals
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

  -- Standard Bearer
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

-- ---------- 6. RENAME EXISTING BADGE KEY ----------
-- The existing `loremaster` badge (10 written entries, honoured tier) is
-- renamed to `master_scribe` so its key doesn't collide with the new
-- `loremaster` submission type. Player_awards rows reference the badge by id,
-- so earned badges survive the rename.
update public.awards
set key = 'master_scribe'
where key = 'loremaster';
