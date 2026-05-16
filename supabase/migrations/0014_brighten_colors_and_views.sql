-- ============================================================================
-- 0014_brighten_colors_and_views.sql
--
-- 1. Brightens the very-dark faction colors so emblems tinted with the
--    faction color stay visible on the dark UI background (the badge sits
--    on bg-ink-2; a near-black tint was washing out).
-- 2. Rebuilds faction_totals and player_totals so the leaderboard can
--    render emblems without a second round trip for the factions table.
-- ============================================================================

update public.factions set color = '#c8102e' where name = 'Chaos';     -- was #6b1616
update public.factions set color = '#3c8dbc' where name = 'Imperium';  -- was #1a4d6b
update public.factions set color = '#5fa83f' where name = 'Orks';      -- was #2d5016

-- ---------- faction_totals ----------
drop view if exists public.faction_totals;

create view public.faction_totals as
  select
    f.id              as faction_id,
    f.name            as faction_name,
    f.color,
    f.emblem_url,
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
  group by f.id, f.name, f.color, f.emblem_url;

grant select on public.faction_totals to anon, authenticated;

-- ---------- player_totals ----------
drop view if exists public.player_totals;

create view public.player_totals as
  select
    pr.id             as player_id,
    pr.display_name,
    pr.faction_id,
    f.name            as faction_name,
    f.color           as faction_color,
    f.emblem_url      as faction_emblem_url,
    coalesce(sum(s.points), 0)::int as total_points,
    count(s.id) filter (where s.status = 'approved') as approved_count
  from public.profiles pr
  left join public.factions f on f.id = pr.faction_id
  left join public.submissions s
    on s.player_id = pr.id and s.status = 'approved'
  group by pr.id, pr.display_name, pr.faction_id, f.name, f.color, f.emblem_url;

grant select on public.player_totals to anon, authenticated;
