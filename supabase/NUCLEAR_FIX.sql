-- =============================================================================
-- StyleLink — NUCLEAR SQL FIX
-- =============================================================================
-- This single script fixes EVERYTHING:
--   1. Drops ALL rogue triggers/functions that auto-insert into providers
--   2. Fixes profiles.id FK to reference auth.users (not public.users)
--   3. Creates upgrade_to_provider RPC for the "Become a Provider" flow
--   4. Makes providers columns nullable so rogue inserts don't crash
--   5. Ensures RLS policies are correct
--
-- Run this in the Supabase SQL editor. It is idempotent and safe to re-run.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PART A: Drop ALL rogue triggers and trigger functions
-- ─────────────────────────────────────────────────────────────────────────────

-- A1: Drop all triggers on auth.users that aren't ours
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname AS trigger_name
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'auth'
      AND c.relname = 'users'
      AND NOT t.tgisinternal
      AND t.tgname != 'on_auth_user_created'
  LOOP
    EXECUTE 'DROP TRIGGER IF EXISTS ' || quote_ident(r.trigger_name) || ' ON auth.users CASCADE';
    RAISE NOTICE 'Dropped rogue trigger on auth.users: %', r.trigger_name;
  END LOOP;
END $$;

-- A2: Drop all triggers on public.profiles
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname AS trigger_name
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = 'profiles'
      AND NOT t.tgisinternal
  LOOP
    EXECUTE 'DROP TRIGGER IF EXISTS ' || quote_ident(r.trigger_name) || ' ON public.profiles CASCADE';
    RAISE NOTICE 'Dropped trigger on public.profiles: %', r.trigger_name;
  END LOOP;
END $$;

-- A3: Drop ALL trigger functions that reference the providers table
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.proname AS func_name,
           p.oid AS func_oid
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.prosrc ILIKE '%providers%'
      AND p.proname NOT IN ('handle_new_user', 'set_user_role', 'set_provider_defaults')
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '() CASCADE';
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '(text) CASCADE';
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '(uuid) CASCADE';
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '(text, text, text) CASCADE';
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '(uuid, text, text, text) CASCADE';
    RAISE NOTICE 'Dropped function: public.%', r.func_name;
  END LOOP;
END $$;

-- A4: Drop any rules on the providers table
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT rulename
    FROM pg_rules
    WHERE schemaname = 'public'
      AND tablename = 'providers'
  LOOP
    EXECUTE 'DROP RULE ' || quote_ident(r.rulename) || ' ON public.providers';
    RAISE NOTICE 'Dropped rule on providers: %', r.rulename;
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- PART B: Fix profiles.id FK constraint (must reference auth.users)
-- ─────────────────────────────────────────────────────────────────────────────

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
      AND NOT EXISTS (
        SELECT 1
        FROM pg_class ref
        JOIN pg_namespace rn ON ref.relnamespace = rn.oid
        WHERE ref.oid = c.confrelid
          AND ref.relname = 'users'
          AND rn.nspname = 'auth'
      )
  LOOP
    EXECUTE 'ALTER TABLE public.profiles DROP CONSTRAINT ' || quote_ident(conname);
    RAISE NOTICE 'Dropped wrong FK: %', conname;
  END LOOP;
END $$;

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
    RAISE NOTICE 'Added FK: profiles.id -> auth.users(id)';
  ELSE
    RAISE NOTICE 'Correct FK already exists.';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- PART C: Make providers columns nullable (belt and suspenders)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.providers
  ALTER COLUMN business_name DROP NOT NULL,
  ALTER COLUMN category      DROP NOT NULL,
  ALTER COLUMN city          DROP NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- PART D: Create BEFORE INSERT trigger to fill provider defaults
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_provider_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  NEW.business_name := COALESCE(NEW.business_name, '');
  NEW.category      := COALESCE(NEW.category, '');
  NEW.city          := COALESCE(NEW.city, '');
  NEW.rating        := COALESCE(NEW.rating, 0);
  NEW.review_count  := COALESCE(NEW.review_count, 0);
  NEW.price_from    := COALESCE(NEW.price_from, 0);
  NEW.service_type  := COALESCE(NEW.service_type, 'studio');
  NEW.quarter       := COALESCE(NEW.quarter, '');
  NEW.is_verified   := COALESCE(NEW.is_verified, false);
  NEW.working_hours := COALESCE(NEW.working_hours, '{}'::jsonb);
  NEW.created_at    := COALESCE(NEW.created_at, now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_provider_defaults ON public.providers;
CREATE TRIGGER set_provider_defaults
  BEFORE INSERT ON public.providers
  FOR EACH ROW
  EXECUTE FUNCTION public.set_provider_defaults();

-- ─────────────────────────────────────────────────────────────────────────────
-- PART E: Create upgrade_to_provider RPC
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.upgrade_to_provider(
  p_business_name text,
  p_category text,
  p_city text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Validate inputs.
  IF p_business_name IS NULL OR length(trim(p_business_name)) = 0 THEN
    RAISE EXCEPTION 'Business name is required';
  END IF;
  IF p_category IS NULL OR length(trim(p_category)) = 0 THEN
    RAISE EXCEPTION 'Category is required';
  END IF;
  IF p_city IS NULL OR length(trim(p_city)) = 0 THEN
    RAISE EXCEPTION 'City is required';
  END IF;

  -- Upsert into providers.
  INSERT INTO public.providers (
    id, user_id, business_name, category, city
  ) VALUES (
    uid, uid, trim(p_business_name), trim(p_category), trim(p_city)
  )
  ON CONFLICT (id) DO UPDATE SET
    business_name = EXCLUDED.business_name,
    category      = EXCLUDED.category,
    city          = EXCLUDED.city;

  -- Update profile role to provider.
  UPDATE public.profiles SET role = 'provider' WHERE id = uid;

  -- Stamp auth metadata.
  UPDATE auth.users
  SET raw_user_meta_data = raw_user_meta_data || '{"role": "provider"}'::jsonb
  WHERE id = uid;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.upgrade_to_provider(text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.upgrade_to_provider(text, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- PART F: Recreate set_user_role (clean version, no providers touch)
-- ─────────────────────────────────────────────────────────────────────────────

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
    RAISE NOTICE 'Dropped: %', r.sig;
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

-- ─────────────────────────────────────────────────────────────────────────────
-- PART G: Ensure RLS policies for profiles
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "users can insert their own profile" ON public.profiles;
CREATE POLICY "users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "users can update their own profile" ON public.profiles;
CREATE POLICY "users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- ─────────────────────────────────────────────────────────────────────────────
-- PART H: Clean up legacy public.users table if empty
-- ─────────────────────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────────────────────
-- PART I: Reload PostgREST schema cache
-- ─────────────────────────────────────────────────────────────────────────────

NOTIFY pgrst, 'reload schema';

RAISE NOTICE '=== StyleLink nuclear fix complete ===';
