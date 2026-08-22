-- ============================================================================
-- StyleLink — create the missing `messages` table
-- Run this in the Supabase SQL editor (idempotent; safe to re-run).
--
-- The deployed database is missing the `messages` table entirely, so the
-- Messages tab and per-provider chat threads fail with:
--   PostgrestException PGRST205 "Could not find the table 'public.messages'
--   in the schema cache"
-- This creates the table, its RLS policies and the realtime publication
-- entry, mirroring `supabase/schema.sql`.
-- ============================================================================

create table if not exists public.messages (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.profiles (id) on delete cascade,
  provider_id uuid not null references public.providers (id) on delete cascade,
  sender_id   uuid not null references public.profiles (id) on delete cascade,
  body        text not null,
  created_at  timestamptz not null default now()
);

create index if not exists messages_thread_idx
  on public.messages (client_id, provider_id, created_at);

alter table public.messages enable row level security;

-- Thread participants (the client, or the account that owns the provider
-- row) can read every message in the thread.
drop policy if exists "thread participants can read messages" on public.messages;
create policy "thread participants can read messages"
  on public.messages for select using (
    auth.uid() = client_id
    or exists (
      select 1 from public.providers p
      where p.id = messages.provider_id and p.user_id = auth.uid()
    )
  );

-- Only the participant who is sending may insert a message, and the sender
-- must be one of the two thread participants.
drop policy if exists "thread participants can insert messages" on public.messages;
create policy "thread participants can insert messages"
  on public.messages for insert with check (
    sender_id = auth.uid()
    and (
      sender_id = client_id
      or exists (
        select 1 from public.providers p
        where p.id = messages.provider_id and p.user_id = auth.uid()
      )
    )
  );

-- Publish changes so open chat screens stay live via
-- `watchMessages` / `watchMessagesForClient`. Idempotent: no-op if the
-- table is already in the publication.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

-- Sanity check after running: as a signed-in user, GET
-- /rest/v1/messages?client_id=eq.<your id> returns [] (200) instead of
-- PGRST205 (404), and sending a message inserts without an RLS error.
