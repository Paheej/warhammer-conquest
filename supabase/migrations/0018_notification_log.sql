-- ============================================================================
-- 0018_notification_log.sql
--
-- Issue #54: email admins when a submission needs review.
--
-- Tracks the last time each admin-notification kind was sent so the
-- new-submission webhook can cap itself to one email per day regardless of
-- how many submissions land, and the weekly digest cron can record its runs.
-- Only ever touched by the service-role client from server-only API routes,
-- so RLS is enabled with no policies (service role bypasses RLS entirely).
-- ============================================================================

create table public.notification_log (
  key text primary key,
  last_sent_at timestamptz not null default now()
);

alter table public.notification_log enable row level security;
