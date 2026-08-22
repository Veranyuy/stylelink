-- ============================================================================
-- StyleLink — create the missing `favorites` table
-- Run this in the Supabase SQL editor (idempotent; safe to re-run).
--
-- The deployed database is missing the `favorites` table entirely, so the
-- Profile screen's saved-provider hearts fail with:
--   PostgrestException PGRST205 "Could not find the table 'public.favorites'
--   in the schema cache"
-- This creates the table, its RLS policies and the realtime publication
-- entry, mirroring `supabase/schema.sql`.
-- ============================================================================

create table if not exists public.favorites (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  provider_id uuid not null references public.providers (id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (user_id, provider_id)
);

create index if not exists favorites_user_idx on public.favorites (user_id);

alter table public.favorites enable row level security;

-- Users see their own saved providers.
drop policy if exists "users read their own favorites" on public.favorites;
create policy "users read their own favorites"
  on public.favorites for select using (auth.uid() = user_id);

-- Users save a provider (the app's heart uses upsert on
-- `(user_id, provider_id)`, so an UPDATE policy is needed too — an
-- `INSERT ... ON CONFLICT DO UPDATE` must satisfy both policies).
drop policy if exists "users insert their own favorites" on public.favorites;
create policy "users insert their own favorites"
  on public.favorites for insert with check (auth.uid() = user_id);

drop policy if exists "users update their own favorites" on public.favorites;
create policy "users update their own favorites"
  on public.favorites for update using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Users unsave a provider.
drop policy if exists "users delete their own favorites" on public.favorites;
create policy "users delete their own favorites"
  on public.favorites for delete using (auth.uid() = user_id);

-- Publish changes so the app's live heart stream
-- (`watchFavoriteProviderIds`) stays in sync. Idempotent: no-op if the
-- table is already in the publication.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'favorites'
  ) then
    alter publication supabase_realtime add table public.favorites;
  end if;
end $$;

-- Sanity check after running: as a signed-in user, GET
-- /rest/v1/favorites?user_id=eq.<your id> returns [] (200) instead of
-- PGRST205 (404), and tapping a heart upserts without an RLS error.
