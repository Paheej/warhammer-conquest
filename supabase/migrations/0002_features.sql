-- ============================================================================
-- Campaign Chronicle — Database Setup, Part 2 of 2: Features
-- ============================================================================
--
-- Run this AFTER setup_01_schema.sql has completed successfully.
--
-- This file references the 'loremaster' enum value that was added at the end
-- of Part 1. PostgreSQL requires the ADD VALUE to be committed before it can
-- be referenced, which is why the setup is split.
--
-- Concatenation of historical migrations 0010-0012.
-- ============================================================================



-- ############################################################################
-- # 0010_loremaster_features.sql
-- ############################################################################

-- ============================================================================
-- 0010_loremaster_features.sql
--
-- Issue #31 part 2 of 2: build out the loremaster (reading/listening) deed
-- type that 0009 added to the enum. This migration:
--
--   1. Adds reading-specific columns on `submissions` (lore_title,
--      lore_format, lore_rating, lore_reflection) with CHECK constraints.
--   2. Rebuilds `faction_totals` to add the companion `lore_read` column.
--   3. Rebuilds `activity_feed` to surface the new columns so the public
--      submission detail and admin queue can render format / rating /
--      reflection without an extra round trip.
--   4. Inserts six new awards in the `lore` category (cosmetic only — no
--      glory points awarded by these badges).
--   5. Adds the `_has_12_consecutive_loremaster_months` helper.
--   6. Extends `evaluate_player_awards` with reading-track logic.
--   7. Extends `evaluate_competitive_awards` with the Astropathic Choir
--      (group achievement: every active player ≥1 reading deed in the
--      same calendar month).
--   8. Backfills the per-player evaluator + competitive evaluator so any
--      pre-existing data that already qualifies grants the new badges.
-- ============================================================================

-- ---------- 1. NEW SUBMISSION COLUMNS ----------
alter table public.submissions
  add column if not exists lore_title      text,
  add column if not exists lore_format     text
    check (lore_format is null or lore_format in ('novel','audiobook')),
  add column if not exists lore_rating     smallint
    check (lore_rating is null or lore_rating between 1 and 5),
  add column if not exists lore_reflection text;

comment on column public.submissions.lore_title is
  'Non-null for type=loremaster: book or audio drama title.';
comment on column public.submissions.lore_format is
  'Non-null for type=loremaster: novel or audiobook.';
comment on column public.submissions.lore_rating is
  'Non-null for type=loremaster: 1-5 star rating.';
comment on column public.submissions.lore_reflection is
  'Non-null for type=loremaster: 50-500 char proof-of-engagement.';

-- ---------- 2. REBUILD faction_totals WITH lore_read ----------
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
    count(s.id) filter (where s.type = 'loremaster') as lore_read,
    count(distinct p.id) as planets_controlled
  from public.factions f
  left join public.submissions s
    on s.faction_id = f.id and s.status = 'approved'
  left join public.planets p
    on p.controlling_faction_id = f.id
  group by f.id, f.name, f.color;

grant select on public.faction_totals to anon, authenticated;

-- ---------- 3. REBUILD activity_feed WITH LORE COLUMNS ----------
-- The public detail page reads from this view. Add lore_title/format/rating
-- so the loremaster renderer doesn't need a second query. (lore_reflection
-- is surfaced via the existing `description` column when the submission is
-- a loremaster; the form writes its reflection into both s.body and
-- s.lore_reflection so the existing description path keeps working.)
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
  p.id                              as user_id,
  coalesce(p.display_name, 'Unknown Commander') as display_name,
  p.avatar_url,
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

-- ---------- 4. SEED NEW AWARDS ----------
insert into public.awards (key, name, description, hint, tier, category, icon, sort_order) values
  ('seeker_of_truth',             'Seeker of Truth',             'Recorded your first novel.',                              'Read your first Black Library tome.',                       'common',     'lore', '📕', 304),
  ('vox_logged',                  'Vox-Logged',                  'Recorded your first audio drama.',                        'Hear the vox-cast for the first time.',                     'common',     'lore', '🎧', 305),
  ('witness_of_the_word',         'Witness of the Word',         'Fifteen approved reading deeds across novels and audio.', 'Read or listen fifteen times over.',                        'honoured',   'lore', '📚', 306),
  ('keeper_of_the_black_library', 'Keeper of the Black Library', 'One hundred approved reading deeds. Cegorach himself takes notice.', 'Walk the stacks of the Black Library a hundred times.',     'legendary',  'lore', '🏛', 307),
  ('astropathic_choir',           'Astropathic Choir',           'Every active commander logged a lore reading in the same month — and you were one of them.', 'A reading vigil joined by every active commander.',         'adamantium', 'lore', '🔱', 308),
  ('eternal_witness',             'The Eternal Witness',         'Logged at least one reading deed every month for twelve consecutive months.', 'Twelve months without a silent vigil.',                     'adamantium', 'lore', '👁', 309)
on conflict (key) do nothing;

-- ---------- 5. CONSECUTIVE-MONTHS HELPER ----------
create or replace function public._has_12_consecutive_loremaster_months(p_player_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  r record;
  prev_month date := null;
  streak int := 0;
begin
  for r in
    select distinct date_trunc('month', created_at)::date as m
    from public.submissions
    where player_id = p_player_id
      and type = 'loremaster'
      and status = 'approved'
    order by m
  loop
    if prev_month is null then
      streak := 1;
    elsif r.m = prev_month + interval '1 month' then
      streak := streak + 1;
    else
      streak := 1;
    end if;
    if streak >= 12 then return true; end if;
    prev_month := r.m;
  end loop;
  return false;
end $$;

-- ---------- 6. EXTEND PER-PLAYER EVALUATOR ----------
-- Adds reading-track logic alongside the writing-track checks already wired
-- by 0009. Astropathic Choir is granted by the competitive evaluator below
-- (group achievement, not per-player threshold).
create or replace function public.evaluate_player_awards(p_player_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_game_count        int;
  v_model_count       int;
  v_lore_count        int;
  v_loremaster_count  int;
  v_novel_count       int;
  v_audiobook_count   int;
  v_max_streak        int;
  v_distinct_types    int;
  v_total_types       int;
  v_creation_rank     int;
begin
  if p_player_id is null then return; end if;

  -- Combat: total approved games
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

  -- Nemesis
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

  -- David
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

  -- Painting
  select count(*) into v_model_count
  from public.submissions
  where player_id = p_player_id and type = 'model' and status = 'approved';

  if v_model_count >= 1  then perform public._grant_award(p_player_id, 'brush_initiate'); end if;
  if v_model_count >= 3  then perform public._grant_award(p_player_id, 'production_painter'); end if;
  if v_model_count >= 10 then perform public._grant_award(p_player_id, 'master_artisan'); end if;

  if public._has_3_consecutive_painting_months(p_player_id) then
    perform public._grant_award(p_player_id, 'the_long_vigil');
  end if;

  -- Lore writing track (type = 'scribe')
  select count(*) into v_lore_count
  from public.submissions
  where player_id = p_player_id and type = 'scribe' and status = 'approved';

  if v_lore_count >= 1  then perform public._grant_award(p_player_id, 'remembrancer'); end if;
  if v_lore_count >= 3  then perform public._grant_award(p_player_id, 'chronicler'); end if;
  if v_lore_count >= 10 then perform public._grant_award(p_player_id, 'master_scribe'); end if;

  -- Lore reading track (type = 'loremaster')
  select
    count(*) filter (where type = 'loremaster'),
    count(*) filter (where type = 'loremaster' and lore_format = 'novel'),
    count(*) filter (where type = 'loremaster' and lore_format = 'audiobook')
    into v_loremaster_count, v_novel_count, v_audiobook_count
  from public.submissions
  where player_id = p_player_id and status = 'approved';

  if v_novel_count      >= 1   then perform public._grant_award(p_player_id, 'seeker_of_truth'); end if;
  if v_audiobook_count  >= 1   then perform public._grant_award(p_player_id, 'vox_logged'); end if;
  if v_loremaster_count >= 15  then perform public._grant_award(p_player_id, 'witness_of_the_word'); end if;
  if v_loremaster_count >= 100 then perform public._grant_award(p_player_id, 'keeper_of_the_black_library'); end if;

  if public._has_12_consecutive_loremaster_months(p_player_id) then
    perform public._grant_award(p_player_id, 'eternal_witness');
  end if;

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

  -- Holdfast
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

  -- World Eater
  if exists (
    select 1 from public.planet_flip_log
    where top_contributor_id = p_player_id
  ) then
    perform public._grant_award(p_player_id, 'world_eater');
  end if;

  -- Crusade Architect
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

  -- Accept Any Challenge
  select count(distinct type) into v_distinct_types
  from public.submissions
  where player_id = p_player_id and status = 'approved';

  v_total_types := array_length(enum_range(null::public.submission_type), 1);

  if v_distinct_types is not null
     and v_total_types is not null
     and v_distinct_types >= v_total_types then
    perform public._grant_award(p_player_id, 'accept_any_challenge');
  end if;

  -- Faithful Servant
  if public._has_12_consecutive_weeks(p_player_id) then
    perform public._grant_award(p_player_id, 'faithful_servant');
  end if;

  -- Veteran of the Long War
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

-- ---------- 7. EXTEND COMPETITIVE EVALUATOR ----------
-- Adds Astropathic Choir. "Active commander" = any profile with at least one
-- approved submission of any type. The badge unlocks for every active
-- commander once a calendar month exists in which all of them logged ≥1
-- approved loremaster deed. Once earned, the badge is permanent (we don't
-- delete it if a later month has gaps) — it commemorates a moment.
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
  v_active_count int;
  v_choir_month date;
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

  -- Keeper of Secrets (writing-track competitive)
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

  -- Astropathic Choir
  --
  -- Find any month in which every active commander logged ≥ 1 approved
  -- loremaster deed. If such a month exists, grant the badge to all
  -- commanders who participated in any such month. The badge is sticky:
  -- we never revoke it.
  select count(distinct s.player_id) into v_active_count
  from public.submissions s
  where s.status = 'approved';

  if v_active_count is not null and v_active_count > 0 then
    select date_trunc('month', s.created_at)::date into v_choir_month
    from public.submissions s
    where s.type = 'loremaster' and s.status = 'approved'
    group by date_trunc('month', s.created_at)::date
    having count(distinct s.player_id) >= v_active_count
    order by date_trunc('month', s.created_at)::date desc
    limit 1;

    if v_choir_month is not null then
      for r in
        select distinct s.player_id
        from public.submissions s
        where s.type = 'loremaster'
          and s.status = 'approved'
          and date_trunc('month', s.created_at)::date in (
            select date_trunc('month', s2.created_at)::date
            from public.submissions s2
            where s2.type = 'loremaster' and s2.status = 'approved'
            group by date_trunc('month', s2.created_at)::date
            having count(distinct s2.player_id) >= v_active_count
          )
      loop
        perform public._grant_award(r.player_id, 'astropathic_choir');
      end loop;
    end if;
  end if;
end $$;

-- ---------- 8. BACKFILL ----------
select public.evaluate_player_awards(id) from public.profiles;
select public.evaluate_competitive_awards();


-- ############################################################################
-- # 0011_lore_split_polish.sql
-- ############################################################################

-- ============================================================================
-- 0011_lore_split_polish.sql
--
-- Polish pass on top of 0009/0010:
--
--   1. Renames the renamed `master_scribe` badge's *display name* from
--      "Loremaster" to "Master Scribe" so it no longer collides with the
--      Loremaster submission-type label. Tightens the description and icon.
--   2. Updates icons on every award that collided with another award or with
--      a submission-type icon (paintbrush, scroll, open book, eye, classical
--      building). Every submission-type and award icon is now unique.
--   3. Tightens descriptions of the three other writing-track badges
--      (remembrancer, chronicler, keeper_of_secrets) which read "lore
--      entries" before the split — now ambiguous between writing/reading.
--   4. Reworks `accept_any_challenge` to count only the four user-facing
--      submission types (game/model/scribe/loremaster). Bonus is admin-only,
--      so the original `enum_range`-based threshold made the badge effectively
--      unattainable without an admin grant. After the lore split the
--      threshold rose from 4 to 5; this migration anchors it at the four
--      types a player can actually submit.
--   5. Backfills `evaluate_player_awards` for every profile so the changed
--      threshold takes effect immediately and any previously-missed grants
--      (including Nemesis if it was missed for any reason) are reapplied.
-- ============================================================================

-- ---------- 1. RENAME MASTER SCRIBE BADGE DISPLAY ----------
update public.awards
set name        = 'Master Scribe',
    description = 'Ten approved chronicles. The archives know your name.',
    hint        = 'Author ten chronicles to fill the archive.',
    icon        = '✒️'
where key = 'master_scribe';

-- ---------- 2. RESOLVE ICON COLLISIONS ----------
-- brush_initiate (🖌) collided with the `painted` submission type.
update public.awards set icon = '🖍' where key = 'brush_initiate';

-- remembrancer (📖) collided with the `loremaster` submission type.
update public.awards set icon = '🪶' where key = 'remembrancer';

-- chronicler (📜) collided with the `scribe` submission type.
update public.awards set icon = '📝' where key = 'chronicler';

-- keeper_of_secrets (👁) collided with eternal_witness (also 👁).
update public.awards set icon = '🔮' where key = 'keeper_of_secrets';

-- ---------- 3. CLARIFY WRITING-TRACK DESCRIPTIONS ----------
-- After the split, "lore entries" is ambiguous. These three are all
-- writing-track; the new copy says so explicitly.
update public.awards
set description = 'Your first approved chronicle.',
    hint        = 'Set quill to parchment for the first time.'
where key = 'remembrancer';

update public.awards
set description = 'Three approved chronicles.',
    hint        = 'Three tales recorded for posterity.'
where key = 'chronicler';

update public.awards
set description = 'Twenty chronicles, and none more learned than you.',
    hint        = 'Hold more knowledge than any other scholar.'
where key = 'keeper_of_secrets';

-- ---------- 4. ACCEPT ANY CHALLENGE: 4 user-facing types ----------
-- Replace the per-player evaluator. The only behavioural change vs 0010 is
-- the Accept Any Challenge block: count distinct types excluding `bonus`,
-- threshold of 4. Everything else is identical to 0010.
create or replace function public.evaluate_player_awards(p_player_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_game_count        int;
  v_model_count       int;
  v_lore_count        int;
  v_loremaster_count  int;
  v_novel_count       int;
  v_audiobook_count   int;
  v_max_streak        int;
  v_distinct_types    int;
  v_creation_rank     int;
begin
  if p_player_id is null then return; end if;

  -- Combat: total approved games
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

  -- Nemesis
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

  -- David
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

  -- Painting
  select count(*) into v_model_count
  from public.submissions
  where player_id = p_player_id and type = 'model' and status = 'approved';

  if v_model_count >= 1  then perform public._grant_award(p_player_id, 'brush_initiate'); end if;
  if v_model_count >= 3  then perform public._grant_award(p_player_id, 'production_painter'); end if;
  if v_model_count >= 10 then perform public._grant_award(p_player_id, 'master_artisan'); end if;

  if public._has_3_consecutive_painting_months(p_player_id) then
    perform public._grant_award(p_player_id, 'the_long_vigil');
  end if;

  -- Lore writing track
  select count(*) into v_lore_count
  from public.submissions
  where player_id = p_player_id and type = 'scribe' and status = 'approved';

  if v_lore_count >= 1  then perform public._grant_award(p_player_id, 'remembrancer'); end if;
  if v_lore_count >= 3  then perform public._grant_award(p_player_id, 'chronicler'); end if;
  if v_lore_count >= 10 then perform public._grant_award(p_player_id, 'master_scribe'); end if;

  -- Lore reading track
  select
    count(*) filter (where type = 'loremaster'),
    count(*) filter (where type = 'loremaster' and lore_format = 'novel'),
    count(*) filter (where type = 'loremaster' and lore_format = 'audiobook')
    into v_loremaster_count, v_novel_count, v_audiobook_count
  from public.submissions
  where player_id = p_player_id and status = 'approved';

  if v_novel_count      >= 1   then perform public._grant_award(p_player_id, 'seeker_of_truth'); end if;
  if v_audiobook_count  >= 1   then perform public._grant_award(p_player_id, 'vox_logged'); end if;
  if v_loremaster_count >= 15  then perform public._grant_award(p_player_id, 'witness_of_the_word'); end if;
  if v_loremaster_count >= 100 then perform public._grant_award(p_player_id, 'keeper_of_the_black_library'); end if;

  if public._has_12_consecutive_loremaster_months(p_player_id) then
    perform public._grant_award(p_player_id, 'eternal_witness');
  end if;

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

  -- Holdfast
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

  -- World Eater
  if exists (
    select 1 from public.planet_flip_log
    where top_contributor_id = p_player_id
  ) then
    perform public._grant_award(p_player_id, 'world_eater');
  end if;

  -- Crusade Architect
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

  -- Accept Any Challenge: one approved submission of every USER-FACING type.
  -- Bonus is admin-only and is excluded from the requirement so the badge is
  -- attainable through normal play. Threshold is the fixed count of
  -- player-submittable types (game, model, scribe, loremaster) = 4.
  select count(distinct type) into v_distinct_types
  from public.submissions
  where player_id = p_player_id
    and status = 'approved'
    and type in ('game','model','scribe','loremaster');

  if v_distinct_types is not null and v_distinct_types >= 4 then
    perform public._grant_award(p_player_id, 'accept_any_challenge');
  end if;

  -- Faithful Servant
  if public._has_12_consecutive_weeks(p_player_id) then
    perform public._grant_award(p_player_id, 'faithful_servant');
  end if;

  -- Veteran of the Long War
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

-- ---------- 5. BACKFILL ----------
-- Re-evaluate every player so the new accept_any_challenge threshold and any
-- previously-missed grants (e.g. Nemesis) are applied immediately.
select public.evaluate_player_awards(id) from public.profiles;


-- ############################################################################
-- # 0012_season_admin.sql
-- ############################################################################

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
