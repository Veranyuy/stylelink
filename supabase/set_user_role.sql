-- ============================================================================
-- StyleLink — `set_user_role` RPC (definitive version)
-- ----------------------------------------------------------------------------
-- The app's role-completion sheet saves the chosen role through this function
-- instead of writing `public.profiles` directly. `security definer` lets it
-- write the table regardless of RLS policies, so the client only needs
-- EXECUTE on the function — never INSERT/UPDATE on `profiles`.
--
-- Run this WHOLE file in the Supabase SQL editor (Dashboard -> SQL Editor).
-- It is idempotent and safe to re-run.
--
-- Deployment quirks this handles:
--  * Stale `set_user_role` overloads (e.g. a `jsonb` parameter) are dropped.
--  * `profiles.role` is a `user_role` enum on some deployments and plain
--    `text` on others — the function detects which and casts accordingly.
--  * `profiles.full_name` is NOT NULL on some deployments — the function
--    fills it from the signed-in user's JWT metadata (fallback '').
-- ============================================================================

-- 1) Drop every existing overload of set_user_role regardless of signature.
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

-- 2) Create the single, correct version.
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

-- 3) Only signed-in users may call it.
revoke execute on function public.set_user_role(text) from public, anon;
grant execute on function public.set_user_role(text) to authenticated;

-- 4) Force PostgREST to reload its schema cache so the old signature is gone.
notify pgrst, 'reload schema';
