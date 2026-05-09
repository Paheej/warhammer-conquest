-- ============================================================================
-- 0003_fix_award_evaluation_timing.sql
--
-- Fixes #38: First Blood, Brush Initiate, and other threshold-based awards
-- only granted on the SECOND qualifying approval rather than the first.
--
-- Root cause
-- ----------
-- `trg_award_points` is a BEFORE UPDATE trigger on `public.submissions`. When
-- the trigger fires on a status flip pending → approved, the row currently
-- being approved has not yet been written to the table. The evaluator then
-- runs `select count(*) from submissions where status = 'approved'`, and the
-- count excludes the row in flight. So:
--   * 1st qualifying approval: count = 0 → no badge.
--   * 2nd qualifying approval: count = 1 → first_blood / brush_initiate fire,
--     but they reflect the previously-approved submission, not the new one.
-- The same off-by-one affects every threshold check (veteran ≥ 3, master_*
-- ≥ 10, warmaster ≥ 20, etc.).
--
-- Fix
-- ---
-- Add an AFTER UPDATE trigger that re-runs the per-player and competitive
-- evaluators once the approved row is visible. `_grant_award` is idempotent
-- (`on conflict do nothing`), so the existing BEFORE-trigger evaluator calls
-- remain harmless — they grant whatever they can with the off-by-one count,
-- and the AFTER pass picks up anything they missed.
--
-- Mirror submissions are inserted directly with status = 'approved', so they
-- never fire either trigger; the original-side evaluator pass already covers
-- the adversary explicitly, so nothing else needs to change.
--
-- A backfill at the end re-evaluates every existing player so any badges
-- previously missed because of this bug are granted retroactively.
-- ============================================================================

create or replace function public.evaluate_awards_after_approval()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.mirror_of is not null then
    return null;
  end if;

  if new.status = 'approved'
     and (old.status is null or old.status <> 'approved') then
    perform public.evaluate_player_awards(new.player_id);
    if new.adversary_user_id is not null then
      perform public.evaluate_player_awards(new.adversary_user_id);
    end if;
    perform public.evaluate_competitive_awards();
  end if;

  return null;
end $$;

drop trigger if exists trg_evaluate_awards_after on public.submissions;
create trigger trg_evaluate_awards_after
after update on public.submissions
for each row execute function public.evaluate_awards_after_approval();

-- Backfill: re-evaluate every player so badges previously missed because of
-- the off-by-one are granted retroactively.
select public.evaluate_player_awards(id) from public.profiles;
select public.evaluate_competitive_awards();
