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
