-- ============================================================================
-- StyleLink — Fix: drop the rogue trigger that auto-inserts into providers
-- ============================================================================
-- The previous fix (fix_role_selection.sql) dropped triggers on profiles,
-- but the rogue trigger is on auth.users (fires on UPDATE of user metadata).
-- When set_user_role updates the profile, or updateUser changes auth metadata,
-- this trigger tries to INSERT INTO providers with null business details.
--
-- Run this in the Supabase SQL editor. Idempotent.
-- ============================================================================

-- -------------------------------------------------------------------------
-- 1) Drop ALL triggers on auth.users that aren't ours.
--    Our only trigger is on_auth_user_created (calls handle_new_user).
-- -------------------------------------------------------------------------
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

-- -------------------------------------------------------------------------
-- 2) Also drop ALL triggers on public.profiles (belt and suspenders).
-- -------------------------------------------------------------------------
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

-- -------------------------------------------------------------------------
-- 3) Drop ALL trigger FUNCTIONS that reference the providers table.
--    These are the culprits — they fire on profile/auth changes and try
--    to INSERT INTO providers with incomplete data.
-- -------------------------------------------------------------------------
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
      AND p.prosrc ILIKE '%insert%into%providers%'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '() CASCADE';
    RAISE NOTICE 'Dropped rogue function: public.%', r.func_name;
  END LOOP;
END $$;

-- Also catch functions that reference providers in any way (not just INSERT).
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
      AND p.proname NOT IN ('handle_new_user', 'set_user_role')
  LOOP
    -- Only drop if it's not one of our known functions.
    -- Check if it's a trigger function (prokind = 'f' and has TG_ variables).
    IF EXISTS (
      SELECT 1 FROM pg_description d
      WHERE d.objoid = r.func_oid
        AND d.description LIKE '%trigger%'
    ) THEN
      EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '() CASCADE';
      RAISE NOTICE 'Dropped rogue trigger function: public.%', r.func_name;
    END IF;
  END LOOP;
END $$;

-- -------------------------------------------------------------------------
-- 4) Nuclear option: drop ANY function that isn't ours and references
--    providers. Safer than leaving a rogue trigger.
-- -------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.proname AS func_name,
           pg_get_function_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.prosrc ILIKE '%providers%'
      AND p.proname NOT IN ('handle_new_user', 'set_user_role')
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '(' || r.args || ') CASCADE';
    RAISE NOTICE 'Dropped: public.%(%)', r.func_name, r.args;
  END LOOP;
END $$;

-- -------------------------------------------------------------------------
-- 5) Also scan for event triggers or rules on providers.
-- -------------------------------------------------------------------------
-- Drop any rules on the providers table that might auto-insert.
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

NOTIFY pgrst, 'reload schema';
