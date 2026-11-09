-- ============================================================================
-- StyleLink — launch readiness verification
-- ============================================================================
-- Run AFTER supabase/migrations/20261109000000_launch_readiness.sql, against
-- the same project. It fails with a single exception listing every failed
-- check, so CI or an operator cannot mistake a partial deployment for success.
--
-- Supabase Dashboard → SQL Editor → paste this file → Run.
-- Expected final notice: "All StyleLink launch readiness checks passed."
-- ============================================================================

do $$
declare
  failures text[] := '{}';
begin
  -- 1. Public profile projection exists and contains no contact fields.
  if to_regclass('public.public_profiles') is null then
    failures := array_append(failures, 'public.public_profiles view is missing');
  else
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'public_profiles'
        and column_name in ('email', 'phone_number', 'fcm_token')
    ) then
      failures := array_append(failures,
        'public.public_profiles exposes email/phone/fcm_token');
    end if;
  end if;

  -- 2. The old permissive profile policy is gone and profiles are owner-only.
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles'
      and policyname = 'profiles are readable by everyone'
  ) then
    failures := array_append(failures,
      'permissive "profiles are readable by everyone" policy still exists');
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles'
      and policyname = 'users can read their own profile'
  ) then
    failures := array_append(failures,
      'owner-only profile SELECT policy is missing');
  end if;

  -- 3. PIN storage moved out of bookings.
  if to_regclass('public.booking_pins') is null then
    failures := array_append(failures, 'public.booking_pins table is missing');
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings'
      and column_name = 'verification_pin'
  ) then
    failures := array_append(failures,
      'bookings.verification_pin still exists (providers can read it)');
  end if;
  if has_table_privilege('authenticated', 'public.booking_pins', 'SELECT') then
    failures := array_append(failures,
      'authenticated role can SELECT booking_pins directly');
  end if;

  -- 4. Booking writes are RPC-only.
  if has_table_privilege('authenticated', 'public.bookings', 'INSERT') then
    failures := array_append(failures,
      'authenticated role can INSERT bookings directly');
  end if;
  if has_table_privilege('authenticated', 'public.bookings', 'UPDATE') then
    failures := array_append(failures,
      'authenticated role can UPDATE bookings directly');
  end if;
  if has_table_privilege('authenticated', 'public.bookings', 'DELETE') then
    failures := array_append(failures,
      'authenticated role can DELETE bookings directly');
  end if;
  if has_table_privilege('authenticated', 'public.profiles', 'UPDATE') then
    failures := array_append(failures,
      'authenticated role has table-wide UPDATE on profiles (role escalation risk)');
  end if;

  -- 5. Required RPCs exist and are callable only by signed-in users.
  if to_regprocedure('public.create_booking(uuid,uuid[],timestamptz,text)') is null then
    failures := array_append(failures, 'create_booking RPC is missing');
  end if;
  if to_regprocedure('public.provider_verify_pin(uuid,text)') is null then
    failures := array_append(failures, 'provider_verify_pin RPC is missing');
  end if;
  if to_regprocedure('public.get_my_booking_pin(uuid)') is null then
    failures := array_append(failures, 'get_my_booking_pin RPC is missing');
  end if;
  if to_regprocedure('public.provider_update_booking_status(uuid,text)') is null then
    failures := array_append(failures, 'provider_update_booking_status RPC is missing');
  end if;
  if to_regprocedure('public.client_cancel_booking(uuid)') is null then
    failures := array_append(failures, 'client_cancel_booking RPC is missing');
  end if;
  if has_function_privilege(
    'anon',
    'public.create_booking(uuid,uuid[],timestamptz,text)',
    'EXECUTE'
  ) then
    failures := array_append(failures,
      'anon can execute create_booking');
  end if;

  -- 6. RLS is enabled on every user-data table.
  if exists (
    select 1
    from (values
      ('public', 'profiles'),
      ('public', 'providers'),
      ('public', 'services'),
      ('public', 'bookings'),
      ('public', 'booking_pins'),
      ('public', 'favorites'),
      ('public', 'messages'),
      ('public', 'reviews'),
      ('public', 'blocked_providers'),
      ('public', 'profile_views'),
      ('public', 'search_impressions')
    ) as t(schema_name, table_name)
    join pg_class c on c.relname = t.table_name
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = t.schema_name
    where c.relkind = 'r' and not c.relrowsecurity
  ) then
    failures := array_append(failures, 'one or more user-data tables have RLS disabled');
  end if;

  -- 7. Reviews can only be created for the reviewer's completed booking.
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'reviews'
      and policyname = 'reviews_insert_auth'
  ) then
    failures := array_append(failures,
      'legacy permissive reviews_insert_auth policy still exists');
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'reviews'
      and policyname = 'reviews_insert_completed_booking'
  ) then
    failures := array_append(failures,
      'completed-booking review policy is missing');
  end if;

  -- 8. Storage buckets used by the app exist.
  if (
    select count(*) from storage.buckets
    where id in ('provider_assets', 'provider_portfolios', 'avatars', 'covers')
  ) <> 4 then
    failures := array_append(failures,
      'one or more storage buckets are missing (provider_assets, provider_portfolios, avatars, covers)');
  end if;

  if cardinality(failures) > 0 then
    raise exception E'StyleLink launch readiness FAILED:\n- %',
      array_to_string(failures, E'\n- ');
  end if;

  raise notice 'All StyleLink launch readiness checks passed.';
end $$;

select 'StyleLink launch readiness: PASS' as result;
