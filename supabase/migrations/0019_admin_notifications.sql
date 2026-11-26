-- ============================================================================
-- 0019_admin_notifications.sql
--
-- Issue #54: email admins when submissions are waiting for approval.
--
--   * new_submission  — sent when a player submits, at most once per 24h.
--   * weekly_digest   — Sunday reminder (Vercel cron) if anything is pending.
--
-- admin_notification_state holds one row per notification kind with the
-- last time it went out. claim_admin_notification() atomically checks and
-- bumps that timestamp, so two submissions landing at the same moment can't
-- both send an email. release_admin_notification() puts the timestamp back
-- if the email provider fails, so the next submission retries.
--
-- Only the service role (server-side API routes) can touch any of this.
-- ============================================================================

create table if not exists public.admin_notification_state (
  kind          text primary key,
  last_sent_at  timestamptz
);

alter table public.admin_notification_state enable row level security;
-- No policies: anon/authenticated get nothing. The service role bypasses RLS.

insert into public.admin_notification_state (kind) values
  ('new_submission'),
  ('weekly_digest')
on conflict (kind) do nothing;

-- Returns the previous last_sent_at (null on first send) via out param, and
-- whether the claim succeeded.
create or replace function public.claim_admin_notification(
  p_kind         text,
  p_min_interval interval,
  out claimed    boolean,
  out previous   timestamptz
)
 language plpgsql
 security definer
 set search_path = public
as $function$
begin
  select last_sent_at into previous
  from public.admin_notification_state
  where kind = p_kind
  for update;

  if not found then
    insert into public.admin_notification_state (kind, last_sent_at)
    values (p_kind, now());
    claimed := true;
    return;
  end if;

  if previous is null or previous <= now() - p_min_interval then
    update public.admin_notification_state
    set last_sent_at = now()
    where kind = p_kind;
    claimed := true;
  else
    claimed := false;
  end if;
end;
$function$;

create or replace function public.release_admin_notification(
  p_kind     text,
  p_previous timestamptz
)
 returns void
 language sql
 security definer
 set search_path = public
as $function$
  update public.admin_notification_state
  set last_sent_at = p_previous
  where kind = p_kind;
$function$;

revoke all on function public.claim_admin_notification(text, interval)      from public, anon, authenticated;
revoke all on function public.release_admin_notification(text, timestamptz) from public, anon, authenticated;
grant execute on function public.claim_admin_notification(text, interval)      to service_role;
grant execute on function public.release_admin_notification(text, timestamptz) to service_role;
