-- ============================================================================
-- 0016_discord_avatar_sync.sql
--
-- Issue #51: Discord avatars go stale. profiles.avatar_url is captured once
-- at signup (handle_new_user, 0005). When a user later changes their Discord
-- avatar, the old CDN URL (which embeds the avatar hash) starts 404ing and
-- the site shows a broken image.
--
-- GoTrue refreshes auth.users.raw_user_meta_data from the Discord identity
-- on every OAuth sign-in, and touches the row (last_sign_in_at) on every
-- login. So an AFTER UPDATE trigger on auth.users is enough to re-sync the
-- profile avatar each time the user logs in.
--
-- Custom avatars are preserved: the sync only overwrites when the profile's
-- current avatar is empty or itself a Discord CDN URL. A user who uploaded
-- a file or pasted a non-Discord URL on the dashboard keeps it.
-- ============================================================================


-- 1. Sync function + trigger -------------------------------------------------
create or replace function public.sync_profile_avatar()
returns trigger
language plpgsql
security definer
as $$
declare
  v_meta_avatar text;
begin
  v_meta_avatar := new.raw_user_meta_data->>'avatar_url';

  if v_meta_avatar is null or v_meta_avatar = '' then
    return new;
  end if;

  update public.profiles p
  set avatar_url = v_meta_avatar
  where p.id = new.id
    and (p.avatar_url is null
         or p.avatar_url = ''
         or p.avatar_url like 'https://cdn.discordapp.com/%')
    and p.avatar_url is distinct from v_meta_avatar;

  return new;
end;
$$;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
after update on auth.users
for each row execute function public.sync_profile_avatar();


-- 2. Backfill: repair avatars that already went stale ------------------------
-- Same guard as the trigger: only touch profiles still pointing at Discord's
-- CDN (or empty) whose metadata has a newer URL.
update public.profiles p
set avatar_url = u.raw_user_meta_data->>'avatar_url'
from auth.users u
where u.id = p.id
  and coalesce(u.raw_user_meta_data->>'avatar_url', '') <> ''
  and (p.avatar_url is null
       or p.avatar_url = ''
       or p.avatar_url like 'https://cdn.discordapp.com/%')
  and p.avatar_url is distinct from u.raw_user_meta_data->>'avatar_url';
