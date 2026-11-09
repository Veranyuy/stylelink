-- ============================================================================
-- StyleLink — launch readiness migration
-- ============================================================================
-- This is the single ordered schema path for StyleLink. It is safe to run on
-- a fresh Supabase project and on the existing project: every object is created
-- with IF NOT EXISTS / CREATE OR REPLACE, old permissive policies are dropped,
-- and legacy columns are backfilled before they are removed.
--
-- Apply with:
--   supabase link --project-ref <PROJECT_REF>
--   supabase db push
--
-- Then run supabase/verify_launch_readiness.sql and require every check to pass.
--
-- Security model
--   * profiles: only the owner can read the row (email/phone/FCM token are
--     private). Other users read public.public_profiles, a view that exposes
--     only display fields.
--   * bookings: only participants can SELECT. All writes go through
--     SECURITY DEFINER RPCs that enforce ownership, role, price, slot, and
--     state transitions. No direct INSERT/UPDATE/DELETE grants.
--   * verification PINs live in booking_pins, which has no client grants.
--     The client reads its own PIN through get_my_booking_pin(); providers
--     verify it through provider_verify_pin() without ever reading it.
--   * providers/services: public read only when the shop is visible; owners
--     manage their own rows. Sensitive provider columns (rating, review_count,
--     is_verified) cannot be written by clients.
-- ============================================================================

create extension if not exists pgcrypto;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- 1. Profiles
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
  fcm_token           text,
  created_at          timestamptz not null default now()
);

alter table public.profiles add column if not exists fcm_token text;
alter table public.profiles add column if not exists language_preference text not null default 'en';

alter table public.profiles enable row level security;

-- Remove every historical permissive policy. Profile contact details are
-- private; other users use public.public_profiles below.
drop policy if exists "profiles are readable by everyone" on public.profiles;
drop policy if exists "profiles are readable by authenticated users" on public.profiles;
drop policy if exists "users can read their own profile" on public.profiles;
create policy "users can read their own profile"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

drop policy if exists "users can update their own profile" on public.profiles;
create policy "users can update their own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "users can insert their own profile" on public.profiles;
create policy "users can insert their own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

-- Column-level grants stop direct role/email escalation even if a policy is
-- later loosened. Role changes go through set_user_role/upgrade_to_provider.
revoke insert, update, delete on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant insert (id, full_name, email, phone_number, avatar_url, language_preference, city)
  on public.profiles to authenticated;
grant update (full_name, phone_number, avatar_url, language_preference, city, fcm_token)
  on public.profiles to authenticated;

-- Public projection for provider names/avatars shown to clients.
create or replace view public.public_profiles
with (security_invoker = false) as
select
  id,
  full_name,
  avatar_url,
  role,
  city,
  language_preference,
  created_at
from public.profiles;

revoke all on public.public_profiles from public, anon;
grant select on public.public_profiles to authenticated;

comment on view public.public_profiles is
  'Public display fields only. Intentionally runs with the view owner so it can '
  'read profiles while the base table remains owner-only. Never add email, '
  'phone_number, or fcm_token here.';

-- Create/keep a profile row in sync with auth.users.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  meta jsonb := new.raw_user_meta_data;
  requested_role text := nullif(meta ->> 'role', '');
begin
  -- Insert without `role` so the column default works whether it is text or
  -- the legacy user_role enum. The requested role is applied below with the
  -- right cast only when the metadata carries a valid value.
  insert into public.profiles (
    id, full_name, email, phone_number, avatar_url, language_preference
  )
  values (
    new.id,
    coalesce(meta ->> 'full_name', meta ->> 'name'),
    new.email,
    coalesce(new.phone, meta ->> 'phone_number'),
    meta ->> 'avatar_url',
    coalesce(meta ->> 'language_preference', 'en')
  )
  on conflict (id) do update set
    full_name           = coalesce(excluded.full_name, public.profiles.full_name),
    email               = coalesce(excluded.email, public.profiles.email),
    phone_number        = coalesce(excluded.phone_number, public.profiles.phone_number),
    avatar_url          = coalesce(excluded.avatar_url, public.profiles.avatar_url),
    language_preference = coalesce(excluded.language_preference, public.profiles.language_preference);

  if requested_role in ('client', 'provider') then
    if exists (
      select 1 from pg_type t
      where t.typname = 'user_role' and t.typtype = 'e'
    ) then
      execute 'update public.profiles set role = $2::user_role where id = $1'
        using new.id, requested_role;
    else
      update public.profiles set role = requested_role where id = new.id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Role assignment RPC (handles deployments where role is an enum or text).
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'set_user_role'
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
-- 2. Providers and services
-- ---------------------------------------------------------------------------
create table if not exists public.providers (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles (id) on delete cascade,
  business_name    text not null,
  category         text not null,
  city             text not null,
  quarter          text,
  bio              text,
  rating           numeric(3, 2) not null default 0,
  review_count     integer not null default 0,
  service_type     text not null default 'studio'
                     check (service_type in ('studio', 'home', 'both')),
  price_from       integer not null default 0,
  cover_url        text,
  avatar_url       text,
  is_verified      boolean not null default false,
  is_available     boolean not null default true,
  portfolio_images text[] not null default '{}',
  working_hours    jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  unique (user_id)
);

alter table public.providers add column if not exists avatar_url text;
alter table public.providers add column if not exists is_available boolean not null default true;
alter table public.providers add column if not exists portfolio_images text[] not null default '{}';
alter table public.providers add column if not exists working_hours jsonb not null default '{}'::jsonb;

-- Backfill provider avatars from the (previously public) profile row.
update public.providers p
set avatar_url = pr.avatar_url
from public.profiles pr
where p.user_id = pr.id
  and (p.avatar_url is null or p.avatar_url = '')
  and pr.avatar_url is not null;

create index if not exists providers_city_idx on public.providers (city);
create index if not exists providers_rating_idx on public.providers (rating desc);
create unique index if not exists providers_user_id_key on public.providers (user_id);

alter table public.providers enable row level security;

drop policy if exists "providers are readable by everyone" on public.providers;
drop policy if exists "providers can manage their own row" on public.providers;
drop policy if exists "providers can insert their own row" on public.providers;

create policy "providers can manage their own row"
  on public.providers for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "providers can insert their own row"
  on public.providers for insert
  to authenticated
  with check (auth.uid() = user_id);

create table if not exists public.services (
  id               uuid primary key default gen_random_uuid(),
  provider_id      uuid not null references public.providers (id) on delete cascade,
  name             text not null,
  description      text,
  price            integer not null check (price >= 0),
  duration_minutes integer not null default 30 check (duration_minutes > 0),
  is_active        boolean not null default true,
  title            text,
  created_at       timestamptz not null default now()
);

alter table public.services add column if not exists is_active boolean not null default true;
alter table public.services add column if not exists title text;
alter table public.services add column if not exists name text;
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'services' and column_name = 'title'
  ) then
    execute 'update public.services set name = title where (name is null or name = '''') and title is not null';
  end if;
end $$;

create index if not exists services_provider_idx on public.services (provider_id);

alter table public.services enable row level security;

-- Hidden-shop gate: a shop is visible only once it lists an active service.
create or replace function public.provider_is_visible(p_provider_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1
    from public.services s
    where s.provider_id = p_provider_id
      and s.is_active
    limit 1
  );
$$;

revoke execute on function public.provider_is_visible(uuid) from public;
grant execute on function public.provider_is_visible(uuid) to anon, authenticated;

drop policy if exists "providers are readable by everyone" on public.providers;
create policy "providers are readable by everyone"
  on public.providers for select
  using (
    auth.uid() = user_id
    or public.provider_is_visible(id)
  );

drop policy if exists "services are readable by everyone" on public.services;
create policy "services are readable by everyone"
  on public.services for select
  using (
    public.provider_is_visible(provider_id)
    or exists (
      select 1 from public.providers p
      where p.id = services.provider_id and p.user_id = auth.uid()
    )
  );

drop policy if exists "providers can manage their own services" on public.services;
create policy "providers can manage their own services"
  on public.services for all
  to authenticated
  using (
    exists (
      select 1 from public.providers p
      where p.id = services.provider_id and p.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.providers p
      where p.id = services.provider_id and p.user_id = auth.uid()
    )
  );

-- Column grants: a provider cannot self-verify or forge rating/review stats.
revoke insert, update, delete on public.providers from anon, authenticated;
grant select on public.providers to anon, authenticated;
grant insert (
  user_id, business_name, category, city, quarter, bio, service_type,
  price_from, cover_url, avatar_url, working_hours, is_available,
  portfolio_images
) on public.providers to authenticated;
grant update (
  business_name, category, city, quarter, bio, service_type, price_from,
  cover_url, avatar_url, working_hours, is_available, portfolio_images
) on public.providers to authenticated;

revoke insert, update, delete on public.services from anon, authenticated;
grant select on public.services to anon, authenticated;
grant insert (provider_id, name, description, price, duration_minutes, is_active)
  on public.services to authenticated;
grant update (name, description, price, duration_minutes, is_active)
  on public.services to authenticated;
grant delete on public.services to authenticated;

-- Keep providers.price_from in sync with the cheapest active service.
create or replace function public.sync_provider_price_from()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  target uuid := coalesce(new.provider_id, old.provider_id);
begin
  update public.providers p
  set price_from = coalesce((
    select min(s.price)
    from public.services s
    where s.provider_id = target and s.is_active
  ), 0)
  where p.id = target;
  return coalesce(new, old);
end;
$$;

drop trigger if exists on_services_price_sync on public.services;
create trigger on_services_price_sync
  after insert or update of price, is_active or delete on public.services
  for each row execute procedure public.sync_provider_price_from();

-- Upgrade a client to a provider. Creates the providers row first, then the
-- role. SECURITY DEFINER because profiles.role is not writable by clients.
create or replace function public.upgrade_to_provider(
  p_business_name text,
  p_category text,
  p_city text
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_business_name is null or trim(p_business_name) = '' then
    raise exception 'Business name is required';
  end if;
  if p_category is null or trim(p_category) = '' then
    raise exception 'Category is required';
  end if;
  if p_city is null or trim(p_city) = '' then
    raise exception 'City is required';
  end if;

  insert into public.providers (id, user_id, business_name, category, city)
  values (uid, uid, trim(p_business_name), trim(p_category), trim(p_city))
  on conflict (user_id) do update set
    business_name = excluded.business_name,
    category      = excluded.category,
    city          = excluded.city;

  perform public.set_user_role('provider');
end;
$$;

revoke execute on function public.upgrade_to_provider(text, text, text) from public, anon;
grant execute on function public.upgrade_to_provider(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Bookings and private verification PINs
-- ---------------------------------------------------------------------------
create table if not exists public.bookings (
  id                    uuid primary key default gen_random_uuid(),
  client_id             uuid not null references public.profiles (id) on delete cascade,
  provider_id           uuid not null references public.providers (id) on delete cascade,
  service_ids           uuid[] not null default '{}',
  scheduled_at          timestamptz not null,
  status                text not null default 'pending'
                          check (status in ('pending', 'confirmed', 'arrived',
                                            'in_progress', 'completed',
                                            'cancelled', 'rejected')),
  arrived_at            timestamptz,
  started_at            timestamptz,
  completed_at          timestamptz,
  responded_at          timestamptz,
  arrival_lat           double precision,
  arrival_lng           double precision,
  proposed_scheduled_at timestamptz,
  reschedule_status     text,
  total_price_fcfa      integer not null default 0 check (total_price_fcfa >= 0),
  notes                 text,
  created_at            timestamptz not null default now()
);

alter table public.bookings add column if not exists responded_at timestamptz;
alter table public.bookings add column if not exists proposed_scheduled_at timestamptz;
alter table public.bookings add column if not exists reschedule_status text;
alter table public.bookings add column if not exists arrival_lat double precision;
alter table public.bookings add column if not exists arrival_lng double precision;

-- Repair legacy rows before enforcing the reschedule pairing invariant.
update public.bookings
set proposed_scheduled_at = null,
    reschedule_status = null
where (proposed_scheduled_at is null and reschedule_status is not null)
   or (proposed_scheduled_at is not null and reschedule_status is distinct from 'pending');

alter table public.bookings drop constraint if exists bookings_reschedule_pairing_check;
alter table public.bookings add constraint bookings_reschedule_pairing_check check (
  (proposed_scheduled_at is null and reschedule_status is null)
  or (proposed_scheduled_at is not null and reschedule_status = 'pending')
  or (proposed_scheduled_at is null and reschedule_status in ('accepted', 'rejected', 'declined'))
);

create index if not exists bookings_provider_idx on public.bookings (provider_id, scheduled_at);
create index if not exists bookings_client_idx on public.bookings (client_id, scheduled_at);
create index if not exists idx_bookings_responded_at
  on public.bookings (provider_id, responded_at)
  where responded_at is not null;

-- Private PIN store. No client grants: providers verify through RPC, clients
-- read their own through RPC. Attempt throttling prevents brute force.
create table if not exists public.booking_pins (
  booking_id      uuid primary key references public.bookings (id) on delete cascade,
  pin             text not null,
  failed_attempts integer not null default 0,
  locked_until    timestamptz,
  created_at      timestamptz not null default now()
);

alter table public.booking_pins enable row level security;
revoke all on public.booking_pins from public, anon, authenticated;

-- Backfill legacy PINs, then remove the publicly readable column.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings'
      and column_name = 'verification_pin'
  ) then
    execute $sql$
      insert into public.booking_pins (booking_id, pin)
      select id, verification_pin
      from public.bookings
      where verification_pin is not null and verification_pin <> ''
      on conflict (booking_id) do nothing
    $sql$;
    execute 'alter table public.bookings drop column verification_pin';
  end if;
end $$;

alter table public.bookings enable row level security;

-- Remove all historical write policies: every mutation is RPC-only.
drop policy if exists "clients can request bookings" on public.bookings;
drop policy if exists "providers can update their schedule" on public.bookings;
drop policy if exists "clients can cancel their own bookings" on public.bookings;
drop policy if exists "clients can reschedule their own bookings" on public.bookings;
drop policy if exists "providers can delete their own bookings" on public.bookings;

drop policy if exists "clients read their own bookings" on public.bookings;
create policy "clients read their own bookings"
  on public.bookings for select
  to authenticated
  using (auth.uid() = client_id);

drop policy if exists "providers read their schedule" on public.bookings;
create policy "providers read their schedule"
  on public.bookings for select
  to authenticated
  using (
    exists (
      select 1 from public.providers p
      where p.id = bookings.provider_id and p.user_id = auth.uid()
    )
  );

revoke insert, update, delete on public.bookings from public, anon, authenticated;
grant select on public.bookings to authenticated;

-- Keep the original slot frozen while a proposal is pending, and clear
-- proposals on terminal transitions.
create or replace function public.guard_reschedule_proposal()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if new.reschedule_status = 'pending'
       and new.proposed_scheduled_at is not null
       and old.scheduled_at is distinct from new.scheduled_at then
      raise exception 'Cannot move scheduled_at while a reschedule proposal is pending';
    end if;

    if new.status in ('completed', 'cancelled', 'rejected')
       and (new.reschedule_status is not null or new.proposed_scheduled_at is not null) then
      new.reschedule_status := null;
      new.proposed_scheduled_at := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists on_guard_reschedule_proposal on public.bookings;
create trigger on_guard_reschedule_proposal
  before update on public.bookings
  for each row execute procedure public.guard_reschedule_proposal();

-- Internal helpers -----------------------------------------------------------

create or replace function public.assert_provider_owns_booking(
  p_booking_id uuid,
  p_uid uuid
)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if not exists (
    select 1 from public.providers p
    where p.id = b.provider_id and p.user_id = p_uid
  ) then
    raise exception 'You do not own this booking';
  end if;
  return b;
end;
$$;

revoke execute on function public.assert_provider_owns_booking(uuid, uuid)
  from public, anon, authenticated;

-- Create a booking. Price and availability are computed here, never trusted
-- from the client. Returns the created row.
create or replace function public.create_booking(
  p_provider_id uuid,
  p_service_ids uuid[],
  p_scheduled_at timestamptz,
  p_notes text default null
)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_provider public.providers;
  v_total integer;
  v_count integer;
  v_pin text;
  v_booking public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_scheduled_at is null or p_scheduled_at <= now() then
    raise exception 'Choose a future appointment time';
  end if;
  if p_service_ids is null or array_length(p_service_ids, 1) is null then
    raise exception 'Select at least one service';
  end if;
  if array_length(p_service_ids, 1) <> (
    select count(distinct x) from unnest(p_service_ids) as x
  ) then
    raise exception 'Duplicate services are not allowed';
  end if;

  select * into v_provider from public.providers where id = p_provider_id;
  if not found then raise exception 'Provider not found'; end if;
  if v_provider.user_id = uid then
    raise exception 'You cannot book your own shop';
  end if;
  if not v_provider.is_available then
    raise exception 'This provider is not accepting bookings right now';
  end if;
  if not public.provider_is_visible(p_provider_id) then
    raise exception 'This provider is not available for booking';
  end if;

  select coalesce(sum(price), 0), count(*)
  into v_total, v_count
  from public.services
  where id = any(p_service_ids)
    and provider_id = p_provider_id
    and is_active;

  if v_count <> array_length(p_service_ids, 1) then
    raise exception 'One or more selected services are unavailable';
  end if;

  -- Serialize slot checks per provider to close the double-booking race.
  perform pg_advisory_xact_lock(hashtextextended(p_provider_id::text, 0));

  if exists (
    select 1 from public.bookings b
    where b.provider_id = p_provider_id
      and b.scheduled_at = p_scheduled_at
      and b.status not in ('cancelled', 'rejected')
  ) then
    raise exception 'That time slot is no longer available';
  end if;

  if exists (
    select 1 from public.bookings b
    where b.provider_id = p_provider_id
      and b.proposed_scheduled_at = p_scheduled_at
      and b.reschedule_status = 'pending'
  ) then
    raise exception 'That time slot is no longer available';
  end if;

  insert into public.bookings (
    client_id, provider_id, service_ids, scheduled_at, status,
    total_price_fcfa, notes, proposed_scheduled_at, reschedule_status
  ) values (
    uid, p_provider_id, p_service_ids, p_scheduled_at, 'pending',
    v_total, nullif(trim(coalesce(p_notes, '')), ''), null, null
  )
  returning * into v_booking;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');
  insert into public.booking_pins (booking_id, pin) values (v_booking.id, v_pin);

  return v_booking;
end;
$$;

-- Provider accepts or rejects a pending request.
create or replace function public.provider_respond_booking(
  p_booking_id uuid,
  p_accept boolean
)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  b := public.assert_provider_owns_booking(p_booking_id, uid);
  if b.status <> 'pending' then
    raise exception 'Only pending bookings can be accepted or declined';
  end if;

  update public.bookings
  set status = case when p_accept then 'confirmed' else 'rejected' end,
      responded_at = now()
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;

-- Provider cancels an upcoming booking.
create or replace function public.provider_cancel_booking(p_booking_id uuid)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  b := public.assert_provider_owns_booking(p_booking_id, uid);
  if b.status not in ('pending', 'confirmed', 'arrived') then
    raise exception 'This booking can no longer be cancelled';
  end if;

  update public.bookings
  set status = 'cancelled', responded_at = coalesce(responded_at, now())
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;

-- Provider logs arrival with optional GPS coordinates.
create or replace function public.provider_mark_arrived(
  p_booking_id uuid,
  p_lat double precision default null,
  p_lng double precision default null
)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  b := public.assert_provider_owns_booking(p_booking_id, uid);
  if b.status <> 'confirmed' then
    raise exception 'Only confirmed bookings can be marked as arrived';
  end if;
  if p_lat is not null and (p_lat < -90 or p_lat > 90) then
    raise exception 'Invalid latitude';
  end if;
  if p_lng is not null and (p_lng < -180 or p_lng > 180) then
    raise exception 'Invalid longitude';
  end if;

  update public.bookings
  set status = 'arrived',
      arrived_at = now(),
      arrival_lat = coalesce(p_lat, arrival_lat),
      arrival_lng = coalesce(p_lng, arrival_lng)
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;

-- Provider verifies the client's PIN and starts the session. The PIN is never
-- returned; five failures lock verification for 15 minutes.
create or replace function public.provider_verify_pin(
  p_booking_id uuid,
  p_pin text
)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
  p public.booking_pins;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  b := public.assert_provider_owns_booking(p_booking_id, uid);
  if b.status <> 'arrived' then
    raise exception 'Verify the PIN only after marking arrival';
  end if;
  if p_pin is null or length(trim(p_pin)) = 0 then
    raise exception 'Verification PIN is required';
  end if;

  select * into p from public.booking_pins where booking_id = p_booking_id for update;
  if not found then raise exception 'No verification PIN is set for this booking'; end if;
  if p.locked_until is not null and p.locked_until > now() then
    raise exception 'Too many incorrect attempts. Try again later.';
  end if;

  if p.pin <> trim(p_pin) then
    update public.booking_pins
    set failed_attempts = p.failed_attempts + 1,
        locked_until = case
          when p.failed_attempts + 1 >= 5 then now() + interval '15 minutes'
          else locked_until
        end
    where booking_id = p_booking_id;
    raise exception 'Incorrect verification PIN';
  end if;

  update public.booking_pins
  set failed_attempts = 0, locked_until = null
  where booking_id = p_booking_id;

  update public.bookings
  set status = 'in_progress', started_at = now()
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;

-- Provider completes a running session.
create or replace function public.provider_complete_booking(p_booking_id uuid)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  b := public.assert_provider_owns_booking(p_booking_id, uid);
  if b.status <> 'in_progress' then
    raise exception 'Start the session (PIN verification) before completing it';
  end if;

  update public.bookings
  set status = 'completed', completed_at = now()
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;

-- Narrow provider status update used by list/detail actions. It cannot skip
-- arrival, PIN verification, or completion steps.
create or replace function public.provider_update_booking_status(
  p_booking_id uuid,
  p_status text
)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  b := public.assert_provider_owns_booking(p_booking_id, uid);

  if p_status = 'confirmed' and b.status = 'pending' then
    return public.provider_respond_booking(p_booking_id, true);
  elsif p_status = 'rejected' and b.status = 'pending' then
    return public.provider_respond_booking(p_booking_id, false);
  elsif p_status = 'cancelled' and b.status in ('pending', 'confirmed', 'arrived') then
    return public.provider_cancel_booking(p_booking_id);
  elsif p_status = 'completed' and b.status = 'in_progress' then
    return public.provider_complete_booking(p_booking_id);
  else
    raise exception 'Invalid status transition from % to %', b.status, p_status;
  end if;
end;
$$;

-- Client cancels before the session starts.
create or replace function public.client_cancel_booking(p_booking_id uuid)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if b.client_id <> uid then raise exception 'You do not own this booking'; end if;
  if b.status not in ('pending', 'confirmed') then
    raise exception 'This booking can no longer be cancelled';
  end if;

  update public.bookings
  set status = 'cancelled', responded_at = coalesce(responded_at, now())
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;

-- Client proposes a new time. The original slot/status may not change.
create or replace function public.client_reschedule_booking(
  p_booking_id uuid,
  p_new_scheduled_at timestamptz
)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_new_scheduled_at is null or p_new_scheduled_at <= now() then
    raise exception 'Choose a future appointment time';
  end if;

  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if b.client_id <> uid then raise exception 'You do not own this booking'; end if;
  if b.status not in ('pending', 'confirmed') then
    raise exception 'Only pending or confirmed bookings can be rescheduled';
  end if;
  if b.reschedule_status = 'pending' then
    raise exception 'A reschedule request is already awaiting a response';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(b.provider_id::text, 0));

  if exists (
    select 1 from public.bookings x
    where x.provider_id = b.provider_id
      and x.id <> b.id
      and x.scheduled_at = p_new_scheduled_at
      and x.status not in ('cancelled', 'rejected')
  ) or exists (
    select 1 from public.bookings x
    where x.provider_id = b.provider_id
      and x.id <> b.id
      and x.proposed_scheduled_at = p_new_scheduled_at
      and x.reschedule_status = 'pending'
  ) then
    raise exception 'That time slot is no longer available';
  end if;

  update public.bookings
  set proposed_scheduled_at = p_new_scheduled_at,
      reschedule_status = 'pending'
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;

-- Provider accepts/declines a client proposal.
create or replace function public.provider_respond_reschedule(
  p_booking_id uuid,
  p_accept boolean
)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  b := public.assert_provider_owns_booking(p_booking_id, uid);
  if b.reschedule_status <> 'pending' or b.proposed_scheduled_at is null then
    raise exception 'There is no pending reschedule request';
  end if;

  if p_accept then
    update public.bookings
    set scheduled_at = b.proposed_scheduled_at,
        status = 'confirmed',
        proposed_scheduled_at = null,
        reschedule_status = 'accepted',
        responded_at = now()
    where id = p_booking_id
    returning * into b;
  else
    update public.bookings
    set proposed_scheduled_at = null,
        reschedule_status = 'rejected',
        responded_at = now()
    where id = p_booking_id
    returning * into b;
  end if;
  return b;
end;
$$;

-- Provider counters a request (or a new booking) with a different time.
create or replace function public.provider_counter_booking(
  p_booking_id uuid,
  p_proposed_at timestamptz
)
returns public.bookings
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_proposed_at is null or p_proposed_at <= now() then
    raise exception 'Choose a future appointment time';
  end if;
  b := public.assert_provider_owns_booking(p_booking_id, uid);
  if b.status not in ('pending', 'confirmed', 'arrived') then
    raise exception 'This booking can no longer be countered';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(b.provider_id::text, 0));
  if exists (
    select 1 from public.bookings x
    where x.provider_id = b.provider_id
      and x.id <> b.id
      and x.scheduled_at = p_proposed_at
      and x.status not in ('cancelled', 'rejected')
  ) or exists (
    select 1 from public.bookings x
    where x.provider_id = b.provider_id
      and x.id <> b.id
      and x.proposed_scheduled_at = p_proposed_at
      and x.reschedule_status = 'pending'
  ) then
    raise exception 'That time slot is no longer available';
  end if;

  update public.bookings
  set proposed_scheduled_at = p_proposed_at,
      reschedule_status = 'pending'
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;

-- The client's own PIN, only while the session is active.
create or replace function public.get_my_booking_pin(p_booking_id uuid)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.bookings;
  v_pin text;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into b from public.bookings where id = p_booking_id;
  if not found then raise exception 'Booking not found'; end if;
  if b.client_id <> uid then raise exception 'You do not own this booking'; end if;
  if b.status not in ('confirmed', 'arrived') then
    raise exception 'The verification PIN is only available during an active booking';
  end if;

  select pin into v_pin from public.booking_pins where booking_id = p_booking_id;
  if v_pin is null then raise exception 'No verification PIN is set'; end if;
  return v_pin;
end;
$$;

revoke execute on function public.create_booking(uuid, uuid[], timestamptz, text)
  from public, anon;
revoke execute on function public.provider_respond_booking(uuid, boolean)
  from public, anon;
revoke execute on function public.provider_cancel_booking(uuid)
  from public, anon;
revoke execute on function public.provider_mark_arrived(uuid, double precision, double precision)
  from public, anon;
revoke execute on function public.provider_verify_pin(uuid, text)
  from public, anon;
revoke execute on function public.provider_complete_booking(uuid)
  from public, anon;
revoke execute on function public.provider_update_booking_status(uuid, text)
  from public, anon;
revoke execute on function public.client_cancel_booking(uuid)
  from public, anon;
revoke execute on function public.client_reschedule_booking(uuid, timestamptz)
  from public, anon;
revoke execute on function public.provider_respond_reschedule(uuid, boolean)
  from public, anon;
revoke execute on function public.provider_counter_booking(uuid, timestamptz)
  from public, anon;
revoke execute on function public.get_my_booking_pin(uuid)
  from public, anon;

grant execute on function public.create_booking(uuid, uuid[], timestamptz, text)
  to authenticated;
grant execute on function public.provider_respond_booking(uuid, boolean)
  to authenticated;
grant execute on function public.provider_cancel_booking(uuid)
  to authenticated;
grant execute on function public.provider_mark_arrived(uuid, double precision, double precision)
  to authenticated;
grant execute on function public.provider_verify_pin(uuid, text)
  to authenticated;
grant execute on function public.provider_complete_booking(uuid)
  to authenticated;
grant execute on function public.provider_update_booking_status(uuid, text)
  to authenticated;
grant execute on function public.client_cancel_booking(uuid)
  to authenticated;
grant execute on function public.client_reschedule_booking(uuid, timestamptz)
  to authenticated;
grant execute on function public.provider_respond_reschedule(uuid, boolean)
  to authenticated;
grant execute on function public.provider_counter_booking(uuid, timestamptz)
  to authenticated;
grant execute on function public.get_my_booking_pin(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Favorites, messages, reviews, blocks, analytics
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
  on public.favorites for select to authenticated using (auth.uid() = user_id);
drop policy if exists "users insert their own favorites" on public.favorites;
create policy "users insert their own favorites"
  on public.favorites for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "users update their own favorites" on public.favorites;
create policy "users update their own favorites"
  on public.favorites for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "users delete their own favorites" on public.favorites;
create policy "users delete their own favorites"
  on public.favorites for delete to authenticated using (auth.uid() = user_id);

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

drop policy if exists "thread participants can read messages" on public.messages;
create policy "thread participants can read messages"
  on public.messages for select to authenticated
  using (
    auth.uid() = client_id
    or exists (
      select 1 from public.providers p
      where p.id = messages.provider_id and p.user_id = auth.uid()
    )
  );

drop policy if exists "thread participants can insert messages" on public.messages;
create policy "thread participants can insert messages"
  on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (
      sender_id = client_id
      or exists (
        select 1 from public.providers p
        where p.id = messages.provider_id and p.user_id = auth.uid()
      )
    )
  );

create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null unique references public.bookings (id) on delete cascade,
  provider_id uuid not null references public.providers (id) on delete cascade,
  client_id   uuid not null references auth.users (id) on delete cascade,
  rating      integer not null check (rating between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_reviews_provider on public.reviews (provider_id);
create index if not exists idx_reviews_client on public.reviews (client_id);
alter table public.reviews enable row level security;

drop policy if exists "Public read access to reviews" on public.reviews;
drop policy if exists "Clients can insert reviews" on public.reviews;
drop policy if exists "Authenticated insert reviews" on public.reviews;
drop policy if exists "reviews_select_public" on public.reviews;
drop policy if exists "reviews_insert_auth" on public.reviews;
drop policy if exists "reviews_insert_completed_booking" on public.reviews;

create policy "reviews_select_public"
  on public.reviews for select using (true);

create policy "reviews_insert_completed_booking"
  on public.reviews for insert to authenticated
  with check (
    auth.uid() = client_id
    and exists (
      select 1 from public.bookings b
      where b.id = booking_id
        and b.client_id = auth.uid()
        and b.provider_id = reviews.provider_id
        and b.status = 'completed'
    )
  );

-- Recompute rating on insert/update/delete.
create or replace function public.handle_review_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  target uuid := coalesce(new.provider_id, old.provider_id);
begin
  update public.providers p
  set rating = coalesce((
        select round(avg(r.rating)::numeric, 2)
        from public.reviews r where r.provider_id = target
      ), 0),
      review_count = (
        select count(*)::int from public.reviews r where r.provider_id = target
      )
  where p.id = target;
  return coalesce(new, old);
end;
$$;

drop trigger if exists on_review_insert on public.reviews;
drop trigger if exists on_review_change on public.reviews;
create trigger on_review_change
  after insert or update or delete on public.reviews
  for each row execute procedure public.handle_review_change();

create table if not exists public.blocked_providers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  provider_id uuid not null references public.providers (id) on delete cascade,
  reason      text,
  created_at  timestamptz not null default now(),
  unique (user_id, provider_id)
);
alter table public.blocked_providers enable row level security;

drop policy if exists "Users can view own blocks" on public.blocked_providers;
create policy "Users can view own blocks"
  on public.blocked_providers for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users can block a provider" on public.blocked_providers;
create policy "Users can block a provider"
  on public.blocked_providers for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can unblock a provider" on public.blocked_providers;
create policy "Users can unblock a provider"
  on public.blocked_providers for delete to authenticated using (auth.uid() = user_id);

create table if not exists public.profile_views (
  id          uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers (id) on delete cascade,
  viewer_id   uuid references public.profiles (id) on delete set null,
  viewed_at   timestamptz not null default now(),
  unique (provider_id, viewer_id, viewed_at)
);
create table if not exists public.search_impressions (
  id          uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers (id) on delete cascade,
  query       text,
  city        text,
  category    text,
  shown_at    timestamptz not null default now()
);
create index if not exists idx_profile_views_provider
  on public.profile_views (provider_id, viewed_at);
create index if not exists idx_search_impressions_provider
  on public.search_impressions (provider_id, shown_at);

alter table public.profile_views enable row level security;
alter table public.search_impressions enable row level security;

drop policy if exists "Providers read own profile views" on public.profile_views;
create policy "Providers read own profile views"
  on public.profile_views for select to authenticated
  using (provider_id in (select id from public.providers where user_id = auth.uid()));
drop policy if exists "Providers read own search impressions" on public.search_impressions;
create policy "Providers read own search impressions"
  on public.search_impressions for select to authenticated
  using (provider_id in (select id from public.providers where user_id = auth.uid()));
drop policy if exists "Authenticated insert profile views" on public.profile_views;
create policy "Authenticated insert profile views"
  on public.profile_views for insert to authenticated
  with check (auth.uid() = viewer_id);
drop policy if exists "Authenticated insert search impressions" on public.search_impressions;
create policy "Authenticated insert search impressions"
  on public.search_impressions for insert to authenticated
  with check (auth.uid() is not null);

create or replace function public.get_profile_view_count(
  p_provider_id uuid,
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns integer
language sql stable set search_path = public
as $$
  select count(*)::integer from public.profile_views
  where provider_id = p_provider_id
    and (p_start is null or viewed_at >= p_start)
    and (p_end is null or viewed_at < p_end);
$$;

create or replace function public.get_search_impression_count(
  p_provider_id uuid,
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns integer
language sql stable set search_path = public
as $$
  select count(*)::integer from public.search_impressions
  where provider_id = p_provider_id
    and (p_start is null or shown_at >= p_start)
    and (p_end is null or shown_at < p_end);
$$;

create or replace function public.get_conversion_rate(
  p_provider_id uuid,
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns numeric
language sql stable set search_path = public
as $$
  select case
    when views = 0 then 0
    else round((bookings::numeric / views) * 100, 1)
  end
  from (
    select
      public.get_profile_view_count(p_provider_id, p_start, p_end) as views,
      count(*)::integer as bookings
    from public.bookings
    where provider_id = p_provider_id
      and status = 'completed'
      and (p_start is null or created_at >= p_start)
      and (p_end is null or created_at < p_end)
  ) s;
$$;

create or replace function public.get_daily_views(
  p_provider_id uuid,
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns table(day date, count bigint)
language sql stable set search_path = public
as $$
  select date_trunc('day', viewed_at)::date as day, count(*) as count
  from public.profile_views
  where provider_id = p_provider_id
    and (p_start is null or viewed_at >= p_start)
    and (p_end is null or viewed_at < p_end)
  group by day order by day;
$$;

create or replace function public.get_top_search_queries(
  p_provider_id uuid,
  p_limit integer default 10
)
returns table(query text, count bigint)
language sql stable set search_path = public
as $$
  select coalesce(query, '(direct)') as query, count(*) as count
  from public.search_impressions
  where provider_id = p_provider_id
  group by query order by count desc limit p_limit;
$$;

create or replace function public.get_avg_response_time(
  p_provider_id uuid,
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns numeric
language sql stable set search_path = public
as $$
  select case when count(*) = 0 then 0 else
    round(avg(extract(epoch from (responded_at - created_at)) / 60.0)::numeric, 1)
  end
  from public.bookings
  where provider_id = p_provider_id
    and responded_at is not null
    and created_at is not null
    and (p_start is null or created_at >= p_start)
    and (p_end is null or created_at < p_end);
$$;

create or replace function public.get_response_rate(
  p_provider_id uuid,
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns numeric
language sql stable set search_path = public
as $$
  select case when total = 0 then 0 else round((responded::numeric / total) * 100, 1) end
  from (
    select count(*)::integer as total, count(responded_at)::integer as responded
    from public.bookings
    where provider_id = p_provider_id
      and (p_start is null or created_at >= p_start)
      and (p_end is null or created_at < p_end)
  ) s;
$$;

create or replace function public.get_response_time_range(
  p_provider_id uuid,
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns table(fastest_min numeric, slowest_min numeric)
language sql stable set search_path = public
as $$
  select
    round(min(extract(epoch from (responded_at - created_at)) / 60.0)::numeric, 1),
    round(max(extract(epoch from (responded_at - created_at)) / 60.0)::numeric, 1)
  from public.bookings
  where provider_id = p_provider_id
    and responded_at is not null
    and created_at is not null
    and (p_start is null or created_at >= p_start)
    and (p_end is null or created_at < p_end);
$$;

-- Hidden-shop nudge state (the sweep itself is scheduled separately; see
-- supabase/HIDDEN_SHOP_NUDGE_SETUP.md).
create table if not exists public.hidden_shop_nudges (
  provider_id          uuid primary key references public.providers (id) on delete cascade,
  first_seen_hidden_at timestamptz not null default now(),
  last_nudged_at       timestamptz,
  nudge_count          integer not null default 0
);
alter table public.hidden_shop_nudges enable row level security;
revoke all on public.hidden_shop_nudges from public, anon, authenticated;

create or replace function public.sync_hidden_shop_candidates()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  inserted_count integer;
begin
  insert into public.hidden_shop_nudges (provider_id, first_seen_hidden_at)
  select p.id, now()
  from public.providers p
  where not exists (
    select 1 from public.services s where s.provider_id = p.id and s.is_active
  )
  on conflict (provider_id) do nothing;
  get diagnostics inserted_count = row_count;

  delete from public.hidden_shop_nudges h
  where exists (
    select 1 from public.services s where s.provider_id = h.provider_id and s.is_active
  );
  return inserted_count;
end;
$$;

create or replace function public.mark_hidden_shop_nudged(p_provider_id uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.hidden_shop_nudges
  set last_nudged_at = now(), nudge_count = nudge_count + 1
  where provider_id = p_provider_id;
$$;

revoke execute on function public.sync_hidden_shop_candidates() from public, anon, authenticated;
revoke execute on function public.mark_hidden_shop_nudged(uuid) from public, anon, authenticated;
grant execute on function public.sync_hidden_shop_candidates() to service_role;
grant execute on function public.mark_hidden_shop_nudged(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 5. Realtime publication
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bookings'
  ) then
    alter publication supabase_realtime add table public.bookings;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'favorites'
  ) then
    alter publication supabase_realtime add table public.favorites;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Storage buckets and owner-only writes
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values
  ('provider_assets', 'provider_assets', true),
  ('provider_portfolios', 'provider_portfolios', true),
  ('avatars', 'avatars', true),
  ('covers', 'covers', true)
on conflict (id) do nothing;

drop policy if exists "provider covers are readable" on storage.objects;
create policy "provider covers are readable"
  on storage.objects for select
  using (bucket_id in ('provider_assets', 'provider_portfolios', 'avatars', 'covers'));

drop policy if exists "portfolio images are readable" on storage.objects;
drop policy if exists "users upload their own covers" on storage.objects;
create policy "users upload their own covers"
  on storage.objects for insert to authenticated
  with check (
    (bucket_id = 'provider_assets' and name = 'covers/' || auth.uid()::text || '.jpg')
    or (bucket_id = 'covers' and name = 'cover_' || auth.uid()::text || '.jpg')
  );

drop policy if exists "users update their own covers" on storage.objects;
create policy "users update their own covers"
  on storage.objects for update to authenticated
  using (bucket_id in ('provider_assets', 'covers') and owner = auth.uid())
  with check (
    (bucket_id = 'provider_assets' and name = 'covers/' || auth.uid()::text || '.jpg')
    or (bucket_id = 'covers' and name = 'cover_' || auth.uid()::text || '.jpg')
  );

drop policy if exists "users delete their own covers" on storage.objects;
create policy "users delete their own covers"
  on storage.objects for delete to authenticated
  using (bucket_id in ('provider_assets', 'covers') and owner = auth.uid());

drop policy if exists "providers upload their own portfolio" on storage.objects;
create policy "providers upload their own portfolio"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'provider_portfolios'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "providers update their own portfolio" on storage.objects;
create policy "providers update their own portfolio"
  on storage.objects for update to authenticated
  using (bucket_id = 'provider_portfolios' and owner = auth.uid())
  with check (
    bucket_id = 'provider_portfolios'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "providers delete their own portfolio" on storage.objects;
create policy "providers delete their own portfolio"
  on storage.objects for delete to authenticated
  using (bucket_id = 'provider_portfolios' and owner = auth.uid());

drop policy if exists "users upload their own avatar" on storage.objects;
create policy "users upload their own avatar"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and name = 'avatar_' || auth.uid()::text || '.jpg'
  );

drop policy if exists "users update their own avatar" on storage.objects;
create policy "users update their own avatar"
  on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and owner = auth.uid())
  with check (
    bucket_id = 'avatars'
    and name = 'avatar_' || auth.uid()::text || '.jpg'
  );

drop policy if exists "users delete their own avatar" on storage.objects;
create policy "users delete their own avatar"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and owner = auth.uid());

-- ---------------------------------------------------------------------------
-- 7. Refresh PostgREST
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';
