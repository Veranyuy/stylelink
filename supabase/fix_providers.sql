-- ============================================================================
-- StyleLink — bring the deployed `providers` table in line with schema.sql
-- Run this in the Supabase SQL editor (idempotent; safe to re-run).
--
-- The deployed table is missing three columns the app writes when saving a
-- listing, and it has no INSERT policy, so both creating and updating a NEW
-- listing fail:
--   - `alter table ... add column` missing columns ->
--       PostgrestException PGRST204 "Could not find the 'service_type'
--       column of 'providers' in the schema cache"
--   - no insert policy ->
--       PostgresException 42501 "new row violates row-level security
--       policy for table providers"
-- UPDATE of an existing row already works; this unblocks the first save.
-- ============================================================================

-- Columns present in schema.sql but missing on this deployment.
alter table public.providers
  add column if not exists service_type text not null default 'studio'
    check (service_type in ('studio', 'home', 'both'));

alter table public.providers
  add column if not exists price_from integer not null default 0;

alter table public.providers
  add column if not exists working_hours jsonb not null default '{}'::jsonb;

-- `quarter` is nullable in schema.sql, but this deployment made it NOT
-- NULL — the app sends null when the field is left empty, so relax it.
alter table public.providers
  alter column quarter drop not null;

-- A provider may create their own business row (the first "List My Business"
-- save is an INSERT; PostgREST's upsert also needs this).
drop policy if exists "providers can insert their own row" on public.providers;
create policy "providers can insert their own row"
  on public.providers for insert
  with check (auth.uid() = user_id);

-- Ensure the owner-level manage policy exists with an explicit WITH CHECK.
drop policy if exists "providers can manage their own row" on public.providers;
create policy "providers can manage their own row"
  on public.providers for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
