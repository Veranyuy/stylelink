-- ============================================================================
-- StyleLink — Fix: role selection failures (23502 + 23503)
-- ============================================================================
-- Run this in the Supabase SQL editor. Idempotent and safe to re-run.
--
-- TWO issues this addresses:
--
-- 1) profiles.id FK references a legacy public.users table (23503)
--    → Drop the wrong FK, add the correct one (auth.users).
--
-- 2) A stale trigger or function tries to INSERT into providers with
--    user_id = null when the profile role is set to 'provider' (23502).
--    → Drop ALL triggers on profiles that aren't ours, and ensure
--      set_user_role only touches profiles.
-- ============================================================================

-- -------------------------------------------------------------------------
-- PART A: Drop every trigger on public.profiles that isn't ours.
-- Our only trigger is on_auth_user_created (on auth.users, not profiles).
-- Any trigger on profiles that touches providers is rogue.
-- -------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname AS trigger_name,
           c.relname AS table_name
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = 'profiles'
      AND NOT t.tgisinternal
  LOOP
    EXECUTE 'DROP TRIGGER IF EXISTS ' || quote_ident(r.trigger_name) || ' ON public.profiles';
    RAISE NOTICE 'Dropped trigger % on public.profiles', r.trigger_name;
  END LOOP;
END $$;

-- Also drop any trigger functions that reference providers (rogue).
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.proname AS func_name
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.prosrc ILIKE '%providers%'
      AND p.proname NOT IN ('handle_new_user')
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '() CASCADE';
    RAISE NOTICE 'Dropped rogue function: public.%', r.func_name;
  END LOOP;
END $$;

-- -------------------------------------------------------------------------
-- PART B: Fix the profiles.id FK constraint (references auth.users, not
--         the legacy public.users).
-- -------------------------------------------------------------------------
DO $$
DECLARE
  conname text;
BEGIN
  FOR conname IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class r ON c.conrelid = r.oid
    JOIN pg_namespace n ON r.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND r.relname = 'profiles'
      AND c.contype = 'f'
      AND EXISTS (
        SELECT 1
        FROM pg_class ref
        JOIN pg_namespace rn ON ref.relnamespace = rn.oid
        WHERE ref.oid = c.confrelid
          AND ref.relname = 'users'
          AND rn.nspname = 'auth'
      ) = FALSE
      AND EXISTS (
        SELECT 1
        FROM pg_class ref
        JOIN pg_namespace rn ON ref.relnamespace = rn.oid
        WHERE ref.oid = c.confrelid
          AND ref.relname = 'users'
      )
  LOOP
    EXECUTE 'ALTER TABLE public.profiles DROP CONSTRAINT ' || quote_ident(conname);
    RAISE NOTICE 'Dropped wrong FK: %', conname;
  END LOOP;
END $$;

-- Add the correct FK if missing.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class r ON c.conrelid = r.oid
    JOIN pg_namespace n ON r.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND r.relname = 'profiles'
      AND c.contype = 'f'
      AND EXISTS (
        SELECT 1
        FROM pg_class ref
        JOIN pg_namespace rn ON ref.relnamespace = rn.oid
        WHERE ref.oid = c.confrelid
          AND ref.relname = 'users'
          AND rn.nspname = 'auth'
      )
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_id_fkey
      FOREIGN KEY (id) REFERENCES auth.users (id) ON DELETE CASCADE;
    RAISE NOTICE 'Added FK: profiles.id → auth.users(id)';
  ELSE
    RAISE NOTICE 'Correct FK already exists.';
  END IF;
END $$;

-- -------------------------------------------------------------------------
-- PART C: Ensure the set_user_role function is correct.
-- Drop all overloads and recreate with target_role parameter.
-- -------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON p.oid = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'set_user_role'
  LOOP
    EXECUTE 'DROP FUNCTION ' || r.sig;
    RAISE NOTICE 'Dropped: %', r.sig;
  END LOOP;
END $$;

-- Also drop any overloaded variants by scanning pg_proc directly.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'set_user_role'
  LOOP
    EXECUTE 'DROP FUNCTION ' || r.sig;
    RAISE NOTICE 'Dropped overload: %', r.sig;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.set_user_role(target_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  meta jsonb := auth.jwt() -> 'user_metadata';
  full_name text := coalesce(
    nullif(meta ->> 'full_name', ''),
    nullif(meta ->> 'name', ''),
    ''
  );
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF target_role IS NULL OR target_role NOT IN ('client', 'provider') THEN
    RAISE EXCEPTION 'Invalid role: %', coalesce(target_role, 'null');
  END IF;
  -- Only write to profiles; never touch providers here.
  IF EXISTS (
    SELECT 1 FROM pg_type t
    WHERE t.typname = 'user_role' AND t.typtype = 'e'
  ) THEN
    EXECUTE
      'INSERT INTO public.profiles (id, full_name, role)
       VALUES ($1, $2, $3::user_role)
       ON CONFLICT (id) DO UPDATE SET role = excluded.role'
    USING uid, full_name, target_role;
  ELSE
    INSERT INTO public.profiles (id, full_name, role)
    VALUES (uid, full_name, target_role)
    ON CONFLICT (id) DO UPDATE SET role = excluded.role;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_user_role(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.set_user_role(text) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- -------------------------------------------------------------------------
-- PART D: Clean up the legacy public.users table if it exists and is
--         empty (safety check).
-- -------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = 'public' AND tablename = 'users'
  ) THEN
    IF (SELECT count(*) FROM public.users) = 0 THEN
      DROP TABLE public.users CASCADE;
      RAISE NOTICE 'Dropped empty public.users table.';
    ELSE
      RAISE NOTICE 'public.users has rows — leaving it.';
    END IF;
  END IF;
END $$;

-- -------------------------------------------------------------------------
-- PART E: Ensure the RLS policies are correct.
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "users can insert their own profile" ON public.profiles;
CREATE POLICY "users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "users can update their own profile" ON public.profiles;
CREATE POLICY "users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);
