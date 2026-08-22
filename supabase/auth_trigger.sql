-- ============================================================================
-- StyleLink — Auth trigger: profile auto-creation & sync
-- ----------------------------------------------------------------------------
-- Run this in the Supabase SQL editor (it is idempotent and safe to re-run).
-- It replaces the `handle_new_user()` function from `supabase/schema.sql`
-- with a version that:
--
--   * extracts full_name   from metadata  ('full_name' or 'name')
--   * extracts avatar_url  from metadata  ('avatar_url')
--   * extracts phone       from new.phone or metadata ('phone_number')
--   * extracts role        from metadata  ('role'), defaulting to 'client'
--   * extracts language    from metadata  ('language_preference'), 'en'
--
-- and UPSERTs into `public.profiles` so re-running never loses data and a
-- late-arriving OAuth callback can fill in fields the first insert missed.
-- ============================================================================

-- Ensure the column the trigger writes exists (idempotent).
alter table public.profiles
  add column if not exists language_preference text not null default 'en';

-- ---------------------------------------------------------------------------
-- Trigger function
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  meta jsonb := new.raw_user_meta_data;
begin
  insert into public.profiles (
    id,
    full_name,
    email,
    phone_number,
    role,
    avatar_url,
    language_preference
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

-- ---------------------------------------------------------------------------
-- RLS: allow a signed-in user to create their own profile row.
-- ---------------------------------------------------------------------------
-- The app's role-completion flow upserts the chosen role into
-- `public.profiles` from the client (e.g. a first-time Google/Apple user).
-- Without an INSERT policy that upsert would be rejected by RLS even though
-- `users can update their own profile` exists.
drop policy if exists "users can insert their own profile" on public.profiles;
create policy "users can insert their own profile"
  on public.profiles for insert with check (auth.uid() = id);
