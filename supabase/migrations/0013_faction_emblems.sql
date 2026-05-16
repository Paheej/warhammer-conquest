-- ============================================================================
-- 0013_faction_emblems.sql
--
-- Points each seeded faction at its monochrome SVG emblem under
-- /public/factions/. The SVGs are mask sources so the front-end tints them
-- with the faction's color at render time. Also rebuilds activity_feed to
-- surface the new column so the home feed pill can show the emblem chip.
-- ============================================================================

update public.factions set emblem_url = '/factions/imperium.svg' where name = 'Imperium';
update public.factions set emblem_url = '/factions/chaos.svg'    where name = 'Chaos';
update public.factions set emblem_url = '/factions/orks.svg'     where name = 'Orks';
update public.factions set emblem_url = '/factions/eldar.svg'    where name = 'Eldar';
update public.factions set emblem_url = '/factions/tyranids.svg' where name = 'Tyranids';
update public.factions set emblem_url = '/factions/necrons.svg'  where name = 'Necrons';
update public.factions set emblem_url = '/factions/tau.svg'      where name = 'T''au Empire';
update public.factions set emblem_url = '/factions/votann.svg'   where name = 'Votann';

-- Rebuild activity_feed (definition mirrors 0002_features.sql with one extra
-- column: faction_emblem_url so the home feed pill can render the emblem).
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
