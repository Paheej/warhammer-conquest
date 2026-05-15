-- ============================================================================
-- 0004_vlw_on_profile_insert.sql
--
-- Fixes #41: Veteran of the Long War (one of the first ten accounts) did not
-- fire for a new user who registered as the 8th account.
--
-- Root cause
-- ----------
-- VLW was only evaluated inside `evaluate_player_awards`, which runs on
-- submission approval. A user who registers in the first 10 but has not yet
-- had a submission approved never gets the badge. Even after the AFTER UPDATE
-- evaluator pass from 0003, the badge is gated on the timing of an admin
-- approval rather than on the event the badge actually rewards (account
-- creation order).
--
-- Fix
-- ---
-- Grant VLW directly when the profile row is inserted, if total profile count
-- is still <= 10. `_grant_award` is idempotent. A backfill at the end grants
-- VLW to any of the current first-10 profiles (by created_at) that don't yet
-- have it, covering users affected by the old behaviour.
-- ============================================================================

create or replace function public.grant_vlw_on_profile_insert()
returns trigger
language plpgsql
security definer
as $$
begin
  if (select count(*) from public.profiles) <= 10 then
    perform public._grant_award(new.id, 'veteran_of_the_long_war');
  end if;
  return null;
end $$;

drop trigger if exists trg_grant_vlw_on_profile on public.profiles;
create trigger trg_grant_vlw_on_profile
after insert on public.profiles
for each row execute function public.grant_vlw_on_profile_insert();

-- Backfill: grant VLW to the first 10 profiles by created_at that don't have
-- it yet.
do $$
declare
  r record;
begin
  for r in
    select id
    from public.profiles
    order by created_at
    limit 10
  loop
    perform public._grant_award(r.id, 'veteran_of_the_long_war');
  end loop;
end $$;
