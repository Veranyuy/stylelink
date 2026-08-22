-- ============================================================================
-- StyleLink — one-time fix for the role-completion sheet failing with
-- PostgresException 42501 "new row violates row-level security policy".
--
-- The app now saves the chosen role with an UPDATE (falling back to INSERT),
-- but the INSERT fallback and the `on_auth_user_created` trigger that
-- auto-creates profile rows require objects this database is missing.
--
-- Idempotent: safe to run in the Supabase SQL editor, and safe to re-run.
-- ============================================================================

-- 1) Columns the trigger and the app write (idempotent).
alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists phone_number text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists language_preference text not null default 'en';
alter table public.profiles add column if not exists city text;

-- 2) Allow a signed-in user to create their own profile row. Needed by the
--    app's insert fallback when no row exists yet (e.g. an account created
--    before this migration added the trigger below).
drop policy if exists "users can insert their own profile" on public.profiles;
create policy "users can insert their own profile"
  on public.profiles for insert with check (auth.uid() = id);

-- 3) Auto-create a profile row on signup so role resolution works even
--    before the user picks a role. Mirrors supabase/schema.sql /
--    supabase/auth_trigger.sql.
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
