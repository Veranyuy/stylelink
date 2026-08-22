-- ============================================================================
-- StyleLink — unblock service saves: align the legacy `title` column
-- Run this in the Supabase SQL editor (idempotent; safe to re-run).
--
-- The deployed `services` table carries a legacy `title` column that is
-- NOT NULL, while the app (matching this repo's schema.sql) inserts the
-- service name into `name`. Saving a service therefore fails with:
--   PostgresException 23502 "null value in column \"title\" of relation
--   \"services\" violates not-null constraint"
-- This is the same drift family that supabase/fix_services.sql addresses
-- (which added/backfilled `name`, `price` and `is_active`) — this script
-- finishes the job by making the legacy `title` a nullable alias of `name`.
--
-- The whole script is guarded on `title` existing, so it is also safe to
-- run against a fresh deployment (schema.sql has no `title` at all).
-- ============================================================================

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'services'
      and column_name = 'title'
  ) then
    -- Backfill both directions so existing rows are consistent whichever
    -- column a dashboard or legacy query reads.
    update public.services
      set title = name
      where title is null and name is not null;

    update public.services
      set name = title
      where name is null and title is not null;

    -- The actual fix: the app's createService/updateService inserts never
    -- send `title`, so it must not be mandatory.
    alter table public.services alter column title drop not null;

    -- `name` is the app's service-name column (schema.sql) — keep it the
    -- mandatory one. Only enforced once the backfill guarantees no nulls.
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'services'
        and column_name = 'name'
        and is_nullable = 'YES'
    ) and not exists (
      select 1 from public.services where name is null
    ) then
      alter table public.services alter column name set not null;
    end if;
  end if;
end $$;

-- Sanity check after running: saving a service from the app (the insert
-- sends provider_id/name/description/price/duration_minutes/is_active —
-- no `title`) should return 201 instead of 23502.
--
-- `title` is legacy and no longer read by the app; once you've confirmed
-- no other tooling depends on it, drop it for good:
--   alter table public.services drop column title;
