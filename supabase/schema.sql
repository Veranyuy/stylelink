-- ============================================================================
-- StyleLink — Supabase schema
-- Run this in the Supabase SQL editor (or `supabase db push`).
-- Mirrors the models in lib/models/*.dart and the queries in
-- lib/services/supabase_service.dart.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Profiles: one row per authenticated user, created by the trigger below.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  full_name           text,
  email               text,
  phone_number        text,
  role                text not null default 'client'
                        check (role in ('client', 'provider')),
  avatar_url          text,
  language_preference text not null default 'en',
  city                text,
  created_at          timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles are readable by everyone" on public.profiles;
create policy "profiles are readable by everyone"
  on public.profiles for select using (true);

drop policy if exists "users can update their own profile" on public.profiles;
create policy "users can update their own profile"
  on public.profiles for update using (auth.uid() = id);

-- Create/keep a profile row in sync with auth.users.
-- (Canonical copy lives in supabase/auth_trigger.sql — this must stay in sync.)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  meta jsonb := new.raw_user_meta_data;
begin
  insert into public.profiles (
    id, full_name, email, phone_number, role, avatar_url, language_preference
  )
  values (
    new.id,
    coalesce(meta ->> 'full_name', meta ->> 'name'),
    new.email,
    coalesce(new.phone, meta ->> 'phone_number'),
    coalesce(meta ->> 'role', 'client'),
    meta ->> 'avatar_url',
    coalesce(meta ->> 'language_preference', 'en')
  )
  on conflict (id) do update set
    full_name           = excluded.full_name,
    email               = excluded.email,
    phone_number        = excluded.phone_number,
    role                = excluded.role,
    avatar_url          = excluded.avatar_url,
    language_preference = excluded.language_preference;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Allow a signed-in user to create their own profile row (the app's
-- role-completion upsert needs INSERT, not just UPDATE).
drop policy if exists "users can insert their own profile" on public.profiles;
create policy "users can insert their own profile"
  on public.profiles for insert with check (auth.uid() = id);

-- Canonical copy of `supabase/set_user_role.sql` — the app's role-completion
-- sheet saves the chosen role through this RPC instead of writing the table
-- directly (security definer, so RLS on `profiles` is bypassed for the
-- single column the function owns). `profiles.role` is a `user_role` enum on
-- some deployments and `text` on others — the function detects which and
-- casts accordingly.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'set_user_role'
  loop
    execute 'drop function ' || r.sig;
  end loop;
end $$;

create or replace function public.set_user_role(target_role text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  meta jsonb := auth.jwt() -> 'user_metadata';
  full_name text := coalesce(
    nullif(meta ->> 'full_name', ''),
    nullif(meta ->> 'name', ''),
    ''
  );
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  if target_role is null or target_role not in ('client', 'provider') then
    raise exception 'Invalid role: %', coalesce(target_role, 'null');
  end if;
  if exists (
    select 1 from pg_type t
    where t.typname = 'user_role' and t.typtype = 'e'
  ) then
    execute
      'insert into public.profiles (id, full_name, role)
       values ($1, $2, $3::user_role)
       on conflict (id) do update set role = excluded.role'
      using uid, full_name, target_role;
  else
    insert into public.profiles (id, full_name, role)
    values (uid, full_name, target_role)
    on conflict (id) do update set role = excluded.role;
  end if;
end;
$$;

revoke execute on function public.set_user_role(text) from public, anon;
grant execute on function public.set_user_role(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Providers: the business/portfolio row for users with role = 'provider'.
-- ---------------------------------------------------------------------------
create table if not exists public.providers (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  business_name text not null,
  category      text not null,
  city          text not null,
  quarter       text,
  bio           text,
  rating        numeric(3, 2) not null default 0,
  review_count  integer not null default 0,
  service_type  text not null default 'studio'
                  check (service_type in ('studio', 'home', 'both')),
  price_from    integer not null default 0,
  cover_url     text,
  is_verified   boolean not null default false,
  working_hours jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);

-- `working_hours` shape: { "Mon": "09:00-19:00", "Tue": "09:00-19:00",
-- ... "Sun": null } — a null/absent value means the provider is closed that
-- day. Kept as jsonb so the provider app can edit it day by day.

create index if not exists providers_city_idx on public.providers (city);
create index if not exists providers_rating_idx on public.providers (rating desc);

alter table public.providers enable row level security;

drop policy if exists "providers are readable by everyone" on public.providers;
create policy "providers are readable by everyone"
  on public.providers for select using (true);

drop policy if exists "providers can manage their own row" on public.providers;
create policy "providers can manage their own row"
  on public.providers for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "providers can insert their own row" on public.providers;
create policy "providers can insert their own row"
  on public.providers for insert
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Services: a provider's bookable menu.
-- ---------------------------------------------------------------------------
create table if not exists public.services (
  id               uuid primary key default gen_random_uuid(),
  provider_id      uuid not null references public.providers (id) on delete cascade,
  name             text not null,
  description      text,
  price            integer not null check (price >= 0),
  duration_minutes integer not null default 30 check (duration_minutes > 0),
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);

create index if not exists services_provider_idx on public.services (provider_id);

alter table public.services enable row level security;

drop policy if exists "services are readable by everyone" on public.services;
create policy "services are readable by everyone"
  on public.services for select using (true);

drop policy if exists "providers can manage their own services" on public.services;
create policy "providers can manage their own services"
  on public.services for all using (
    exists (
      select 1 from public.providers p
      where p.id = services.provider_id and p.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- Bookings: client requests against a provider's schedule.
-- ---------------------------------------------------------------------------
create table if not exists public.bookings (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references public.profiles (id) on delete cascade,
  provider_id     uuid not null references public.providers (id) on delete cascade,
  service_ids     uuid[] not null default '{}',
  scheduled_at    timestamptz not null,
  status          text not null default 'pending'
                    check (status in ('pending', 'confirmed', 'arrived', 'in_progress', 'completed', 'cancelled', 'rejected')),
  arrived_at      timestamptz,
  started_at      timestamptz,
  completed_at    timestamptz,
  arrival_lat     double precision,
  arrival_lng     double precision,
  verification_pin text,
  total_price_fcfa integer not null default 0 check (total_price_fcfa >= 0),
  notes           text,
  created_at      timestamptz not null default now()
);

create index if not exists bookings_provider_idx on public.bookings (provider_id, scheduled_at);
create index if not exists bookings_client_idx on public.bookings (client_id, scheduled_at);

alter table public.bookings enable row level security;

-- Clients see bookings they made.
drop policy if exists "clients read their own bookings" on public.bookings;
create policy "clients read their own bookings"
  on public.bookings for select using (auth.uid() = client_id);

-- Providers see bookings against their provider row.
drop policy if exists "providers read their schedule" on public.bookings;
create policy "providers read their schedule"
  on public.bookings for select using (
    exists (
      select 1 from public.providers p
      where p.id = bookings.provider_id and p.user_id = auth.uid()
    )
  );

-- Clients insert new booking requests.
drop policy if exists "clients can request bookings" on public.bookings;
create policy "clients can request bookings"
  on public.bookings for insert with check (auth.uid() = client_id);

-- Providers update status / notes on their schedule.
drop policy if exists "providers can update their schedule" on public.bookings;
create policy "providers can update their schedule"
  on public.bookings for update using (
    exists (
      select 1 from public.providers p
      where p.id = bookings.provider_id and p.user_id = auth.uid()
    )
  );

-- Clients may cancel their own upcoming bookings (status -> 'cancelled').
drop policy if exists "clients can cancel their own bookings" on public.bookings;
create policy "clients can cancel their own bookings"
  on public.bookings for update
  using (auth.uid() = client_id)
  with check (auth.uid() = client_id and status = 'cancelled');

-- ---------------------------------------------------------------------------
-- Favorites: a client's saved providers (heart on provider cards).
-- ---------------------------------------------------------------------------
create table if not exists public.favorites (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  provider_id uuid not null references public.providers (id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (user_id, provider_id)
);

create index if not exists favorites_user_idx on public.favorites (user_id);

alter table public.favorites enable row level security;

drop policy if exists "users read their own favorites" on public.favorites;
create policy "users read their own favorites"
  on public.favorites for select using (auth.uid() = user_id);

drop policy if exists "users insert their own favorites" on public.favorites;
create policy "users insert their own favorites"
  on public.favorites for insert with check (auth.uid() = user_id);

-- The app's heart uses `upsert(... onConflict: 'user_id,provider_id')`;
-- `INSERT ... ON CONFLICT DO UPDATE` must satisfy BOTH an INSERT and an
-- UPDATE policy, so a bare UPDATE policy is required here even though the
-- client never edits favorite rows directly.
drop policy if exists "users update their own favorites" on public.favorites;
create policy "users update their own favorites"
  on public.favorites for update using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "users delete their own favorites" on public.favorites;
create policy "users delete their own favorites"
  on public.favorites for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Messages: direct chat between a client and a provider.
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.profiles (id) on delete cascade,
  provider_id uuid not null references public.providers (id) on delete cascade,
  sender_id   uuid not null references public.profiles (id) on delete cascade,
  body        text not null,
  created_at  timestamptz not null default now()
);

create index if not exists messages_thread_idx on public.messages (client_id, provider_id, created_at);

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

-- ---------------------------------------------------------------------------
-- Realtime: publish booking / favorites / message changes so the app's
-- schedule, hearts and chat stay live.
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.bookings;
alter publication supabase_realtime add table public.favorites;
alter publication supabase_realtime add table public.messages;

-- ---------------------------------------------------------------------------
-- Storage: provider cover photos.
-- ---------------------------------------------------------------------------
-- Public bucket holding one cover image per provider at
-- `covers/<user_id>.jpg` (the app uploads with `upsert: true`, so re-saving
-- overwrites the same object). The bucket must be public for the public URL
-- returned by `getPublicUrl` to render without auth.
insert into storage.buckets (id, name, public)
values ('provider_assets', 'provider_assets', true)
on conflict (id) do nothing;

-- Anyone can read covers (public bucket).
drop policy if exists "provider covers are readable" on storage.objects;
create policy "provider covers are readable"
  on storage.objects for select
  using (bucket_id = 'provider_assets');

-- Signed-in users may upload/overwrite their own cover only.
drop policy if exists "users upload their own covers" on storage.objects;
create policy "users upload their own covers"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'provider_assets'
    and (storage.foldername(name))[1] = 'covers'
  );

drop policy if exists "users update their own covers" on storage.objects;
create policy "users update their own covers"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'provider_assets' and owner = auth.uid())
  with check (
    bucket_id = 'provider_assets'
    and (storage.foldername(name))[1] = 'covers'
  );

drop policy if exists "users delete their own covers" on storage.objects;
create policy "users delete their own covers"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'provider_assets' and owner = auth.uid());
