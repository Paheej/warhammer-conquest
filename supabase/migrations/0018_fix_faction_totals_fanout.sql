-- ============================================================================
-- 0018_fix_faction_totals_fanout.sql
--
-- Issue #56: faction totals inflated by planets controlled.
--
-- faction_totals (0014) left-joined submissions AND planets onto factions in
-- a single query, so every approved submission row was repeated once per
-- planet the faction controlled. total_points, wins, models_painted,
-- lore_written and lore_read were all multiplied by the planet count (only
-- planets_controlled was right, thanks to count(distinct)). Factions holding
-- 0 or 1 planets looked correct, which hid the bug until Imperium took a
-- second world.
--
-- Fix: aggregate submissions and planets in separate subqueries, then join
-- each one row-per-faction. Column names, order and types are unchanged, so
-- the leaderboard and the Season Administration export need no code changes.
-- ============================================================================

create or replace view public.faction_totals as
  with sub as (
    select
      s.faction_id,
      coalesce(sum(s.points), 0)::int as total_points,
      count(s.id) filter (where s.type = 'game' and s.result = 'win') as wins,
      count(s.id) filter (where s.type = 'model') as models_painted,
      count(s.id) filter (where s.type = 'scribe') as lore_written,
      count(s.id) filter (where s.type = 'loremaster') as lore_read
    from public.submissions s
    where s.status = 'approved'
      and s.faction_id is not null
    group by s.faction_id
  ),
  pl as (
    select
      p.controlling_faction_id as faction_id,
      count(p.id) as planets_controlled
    from public.planets p
    where p.controlling_faction_id is not null
    group by p.controlling_faction_id
  )
  select
    f.id              as faction_id,
    f.name            as faction_name,
    f.color,
    f.emblem_url,
    coalesce(sub.total_points, 0)::int     as total_points,
    coalesce(sub.wins, 0)                  as wins,
    coalesce(sub.models_painted, 0)        as models_painted,
    coalesce(sub.lore_written, 0)          as lore_written,
    coalesce(sub.lore_read, 0)             as lore_read,
    coalesce(pl.planets_controlled, 0)     as planets_controlled
  from public.factions f
  left join sub on sub.faction_id = f.id
  left join pl  on pl.faction_id  = f.id;

grant select on public.faction_totals to anon, authenticated;
