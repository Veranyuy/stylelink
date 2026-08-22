-- ============================================================================
-- StyleLink — bring the deployed `services` table in line with schema.sql
-- Run this in the Supabase SQL editor (idempotent; safe to re-run).
--
-- The deployed table drifted from this repo's schema: it uses a `title`
-- column instead of `name`, and lacks `price` and `is_active` entirely.
-- The app reads/writes `name`, `price` and `is_active`, so any service
-- fetch/insert fails with PGRST204 / 42703 until the columns are aligned.
-- ============================================================================

-- `name` — the app's service name column (backfill from the legacy `title`).
alter table public.services
  add column if not exists name text;

update public.services
set name = coalesce(name, title)
where name is null and title is not null;

alter table public.services
  alter column name set not null;

-- `price` — whole FCFA, matching the app model.
alter table public.services
  add column if not exists price integer not null default 0
    check (price >= 0);

-- `is_active` — the app only lists active services.
alter table public.services
  add column if not exists is_active boolean not null default true;

-- Legacy column no longer read by the app; kept for reference. Drop it once
-- you've confirmed no other tooling depends on it:
--   alter table public.services drop column title;
