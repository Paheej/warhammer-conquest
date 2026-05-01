-- ============================================================================
-- 0007_awards.sql
--
-- Issue #26: Awards & Honours system. All awards derive from already-approved
-- submission data so the trust model is preserved (no award without a real
-- approved deed).
--
-- Phase 1 scope:
--   * `awards` (catalogue) and `player_awards` (instances) tables, with RLS.
--   * Featured-pinning cap of 3 enforced via constraint trigger.
--   * 27 awards seeded (20 auto-evaluated; 7 deferred to Phase 2).
--   * `evaluate_player_awards(uuid)` runs every grantable check for a player.
--   * `award_points_on_approval` trigger now calls the evaluator for the
--     submitter, and for the linked adversary after the mirror is inserted,
--     so both sides receive their badges from a single approval.
--
-- Phase 2 will add: cross-player competitive awards (warmaster, painting_daemon,
-- keeper_of_secrets, standard_bearer, first_among_equals), planet_flip_log
-- table, and the world_eater + crusade_architect awards.
-- ============================================================================

-- ---------- AWARDS CATALOGUE ----------
create table public.awards (
  id          uuid primary key default gen_random_uuid(),
  key         text unique not null,
  name        text not null,
  description text not null,
  hint        text not null,
  tier        text not null check (tier in ('common','honoured','legendary','adamantium')),
  category    text not null check (category in ('combat','painting','lore','conquest','cross')),
  icon        text not null,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

-- ---------- PLAYER AWARDS (instances) ----------
create table public.player_awards (
  id          uuid primary key default gen_random_uuid(),
  player_id   uuid not null references public.profiles(id) on delete cascade,
  award_id    uuid not null references public.awards(id)  on delete cascade,
  earned_at   timestamptz not null default now(),
  is_featured boolean not null default false,
  notified    boolean not null default false,
  unique (player_id, award_id)
);

create index on public.player_awards (player_id, notified);
create index on public.player_awards (player_id) where is_featured;

-- Cap featured awards at 3 per player.
create or replace function public.enforce_featured_award_cap()
returns trigger language plpgsql as $$
begin
  if new.is_featured and (
    select count(*) from public.player_awards
    where player_id = new.player_id and is_featured and id <> new.id
  ) >= 3 then
    raise exception 'A player may pin at most 3 featured awards';
  end if;
  return new;
end $$;

create trigger trg_featured_cap
before insert or update on public.player_awards
for each row when (new.is_featured)
execute function public.enforce_featured_award_cap();

-- ---------- RLS ----------
alter table public.awards         enable row level security;
alter table public.player_awards  enable row level security;

create policy "awards readable" on public.awards
  for select using (auth.role() = 'authenticated');

create policy "player_awards readable" on public.player_awards
  for select using (auth.role() = 'authenticated');

-- Owners can update their own rows (covers notified flag and is_featured pin).
-- INSERT and DELETE go through SECURITY DEFINER evaluator only.
create policy "player_awards self update" on public.player_awards
  for update using (auth.uid() = player_id) with check (auth.uid() = player_id);

-- ============================================================================
-- SEED CATALOGUE
-- ============================================================================
insert into public.awards (key, name, description, hint, tier, category, icon, sort_order) values
  -- Combat
  ('first_blood',            'First Blood',            'Recorded your first approved battle.',                    'Cross blades for the first time.',                          'common',     'combat',   '🩸',  100),
  ('veteran',                'Veteran',                'Three approved battles to your name.',                    'Three battles, three witnesses.',                           'common',     'combat',   '🪖',  101),
  ('honored_of_the_chapter', 'Honored of the Chapter', 'Ten approved battles. The Chapter remembers.',            'Ten battles will earn the Chapter''s notice.',              'honoured',   'combat',   '🏆',  102),
  ('warmaster',              'Warmaster',              'Twenty battles fought, and none more bloody than yours.', 'Lead the host in war beyond all peers.',                    'legendary',  'combat',   '💀',  103),
  ('double_tap',             'Double Tap',             'Three consecutive victories.',                            'Three in a row will not be forgotten.',                     'common',     'combat',   '🔫',  110),
  ('overkill',               'Overkill',               'Five consecutive victories.',                             'Five wins without a stumble.',                              'honoured',   'combat',   '💥',  111),
  ('exterminatus',           'Exterminatus',           'Ten consecutive victories. The galaxy itself trembles.',  'Ten battles, ten worlds undone.',                           'adamantium', 'combat',   '☠️',  112),
  ('david',                  'David',                  'Defeated a higher-rated adversary in a sanctioned duel.', 'Strike down one greater than yourself.',                    'honoured',   'combat',   '🗡',  120),
  ('nemesis',                'Nemesis',                'Defeated the same opponent three times.',                 'Hunt one foe across many battlefields.',                    'legendary',  'combat',   '👹',  121),

  -- Painting
  ('brush_initiate',         'Brush Initiate',         'Your first approved painted unit.',                       'The first stroke of paint upon the host.',                  'common',     'painting', '🖌',  200),
  ('production_painter',     'Production Painter',     'Three approved painted units.',                           'Three units fully painted will mark you.',                  'common',     'painting', '🎨',  201),
  ('master_artisan',         'Master Artisan',         'Ten approved painted units. A force ready for war.',      'Ten units finished is the mark of a true artisan.',         'honoured',   'painting', '👑',  202),
  ('painting_daemon',        'Painting Daemon',        'Twenty units painted, and none more prolific than you.',  'Paint beyond all rival hobbyists.',                         'legendary',  'painting', '😈',  203),
  ('the_long_vigil',         'The Long Vigil',         'Painting submissions in three consecutive months.',       'Keep the brush warm three months without pause.',           'honoured',   'painting', '🕯',  210),

  -- Lore
  ('remembrancer',           'Remembrancer',           'Your first approved lore entry.',                         'Set quill to parchment for the first time.',                'common',     'lore',     '📖',  300),
  ('chronicler',             'Chronicler',             'Three approved lore entries.',                            'Three tales recorded for posterity.',                       'common',     'lore',     '📜',  301),
  ('loremaster',             'Loremaster',             'Ten approved lore entries. The archives know your name.', 'Fill the archive with ten chronicles.',                     'honoured',   'lore',     '🏛',  302),
  ('keeper_of_secrets',      'Keeper of Secrets',      'Twenty lore entries, and none more learned than you.',    'Hold more knowledge than any other scholar.',               'legendary',  'lore',     '👁',  303),

  -- Conquest
  ('planetfall',             'Planetfall',             'Contributed to a successful planetary claim.',            'Be present when the banner is planted.',                    'common',     'conquest', '🪐',  400),
  ('world_eater',            'World Eater',            'Contributed the most points personally to a planet flip.','Be the bloodiest hand in a successful claim.',              'honoured',   'conquest', '🌍',  401),
  ('crusade_architect',      'Crusade Architect',      'Contributed to the flipping of three different planets.', 'Plant your banner on three different worlds.',              'honoured',   'conquest', '🗺',  402),
  ('holdfast',               'Holdfast',               'Logged points on a planet your faction already controls.','Defend what is already yours.',                             'common',     'conquest', '🛡',  410),

  -- Cross-cutting
  ('accept_any_challenge',   'Accept Any Challenge',   'At least one approved submission of every active type.',  'Excel in every discipline this Crusade tracks.',            'honoured',   'cross',    '✠',  500),
  ('faithful_servant',       'Faithful Servant',       'Twelve consecutive weeks of approved submissions.',       'Serve without rest for twelve weeks.',                      'legendary',  'cross',    '🙏',  501),
  ('veteran_of_the_long_war','Veteran of the Long War','One of the first ten accounts in the Crusade.',           'You walked these stars before most others.',                'adamantium', 'cross',    '🎖',  502),
  ('standard_bearer',        'Standard Bearer',        'Top glory scorer in your faction (with at least 30 glory).','Carry the banner higher than any of your faction.',        'legendary',  'cross',    '🚩',  503),
  ('first_among_equals',     'First Among Equals',     'Highest glory across all factions (with at least 50 glory).','Stand above every commander in the Crusade.',             'adamantium', 'cross',    '💎',  504);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Idempotent grant: insert (player_id, award_id) by award key.
-- Sets notified=false so the toast fires on next page load.
create or replace function public._grant_award(p_player_id uuid, p_key text)
returns void
language plpgsql
security definer
as $$
begin
  insert into public.player_awards (player_id, award_id)
  select p_player_id, a.id from public.awards a where a.key = p_key
  on conflict (player_id, award_id) do nothing;
end $$;

-- Longest run of consecutive 'win' results for a player's approved games,
-- ordered by created_at. Mirror submissions are included (they have
-- player_id = adversary_user_id of the original).
create or replace function public._max_win_streak(p_player_id uuid)
returns int
language plpgsql
stable
as $$
declare
  v_max int := 0;
  v_cur int := 0;
  r record;
begin
  for r in
    select result
    from public.submissions
    where player_id = p_player_id
      and type = 'game'
      and status = 'approved'
    order by created_at, id
  loop
    if r.result = 'win' then
      v_cur := v_cur + 1;
      if v_cur > v_max then v_max := v_cur; end if;
    else
      v_cur := 0;
    end if;
  end loop;
  return v_max;
end $$;

-- True if the player has approved 'model' submissions in three consecutive
-- calendar months at any point in their history.
create or replace function public._has_3_consecutive_painting_months(p_player_id uuid)
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
      and type = 'model'
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
    if streak >= 3 then return true; end if;
    prev_month := r.m;
  end loop;
  return false;
end $$;

-- True if the player has approved submissions in 12 consecutive ISO weeks.
create or replace function public._has_12_consecutive_weeks(p_player_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  r record;
  prev_week date := null;
  streak int := 0;
begin
  for r in
    select distinct date_trunc('week', created_at)::date as w
    from public.submissions
    where player_id = p_player_id
      and status = 'approved'
    order by w
  loop
    if prev_week is null then
      streak := 1;
    elsif r.w = prev_week + interval '7 days' then
      streak := streak + 1;
    else
      streak := 1;
    end if;
    if streak >= 12 then return true; end if;
    prev_week := r.w;
  end loop;
  return false;
end $$;

-- ============================================================================
-- EVALUATOR
-- ============================================================================
-- Runs every Phase 1 award check for a player and grants any newly-met ones.
-- Idempotent: existing player_awards rows are not touched.
-- Phase 2 awards are seeded but never granted here (no logic).
create or replace function public.evaluate_player_awards(p_player_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_game_count    int;
  v_model_count   int;
  v_lore_count    int;
  v_max_streak    int;
  v_distinct_types int;
  v_total_types   int;
  v_creation_rank int;
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

  -- Holdfast — 2+ approved submissions to the same currently-held planet on
  -- the same faction. Approximation: the second contribution must have been
  -- after the planet was already in their faction's hands. Phase 2 will
  -- replace this with planet_flip_log lookups.
  if exists (
    select 1
    from public.submissions s
    join public.planets p on p.id = s.target_planet_id
    where s.player_id = p_player_id
      and s.status = 'approved'
      and s.faction_id is not null
      and p.controlling_faction_id = s.faction_id
    group by s.target_planet_id, s.faction_id
    having count(*) >= 2
  ) then
    perform public._grant_award(p_player_id, 'holdfast');
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
-- WIRE EVALUATOR INTO THE APPROVAL TRIGGER
-- ============================================================================
-- Replaces the function from 0006 verbatim except for the trailing evaluator
-- calls. Mirror INSERTs do not fire BEFORE UPDATE, so we explicitly evaluate
-- both submitter and adversary after the mirror row is in place.

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

    -- 6) Award evaluation. Mirror INSERT above does not fire this BEFORE
    --    UPDATE trigger, so we evaluate both sides explicitly.
    perform public.evaluate_player_awards(new.player_id);
    if new.adversary_user_id is not null then
      perform public.evaluate_player_awards(new.adversary_user_id);
    end if;

    new.reviewed_at := coalesce(new.reviewed_at, now());
  end if;

  return new;
end;
$function$;

-- ============================================================================
-- BACKFILL: evaluate awards for every existing player based on their already
-- approved submissions. Safe to run on a fresh schema (no rows yet) and on
-- production (idempotent).
-- ============================================================================
select public.evaluate_player_awards(id) from public.profiles;

-- The backfill above sets notified=false for every newly-granted award, which
-- means all existing players will see toasts on their next page load. That is
-- the intended behaviour for the rollout: existing veterans receive their
-- earned honours retroactively.
