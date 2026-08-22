-- ============================================================================
-- StyleLink — Fix: profiles.id FK must reference auth.users(id), not public.users(id)
-- ============================================================================
-- Symptom: PostgresException 23503 "Key (id) is not present in table
-- 'users' when updating roles in public.profiles"
--
-- Cause: The live database's profiles table has a foreign-key constraint
-- that references a legacy `public.users` table (which either does not
-- exist or does not contain the auth user rows). The repo's schema.sql
-- defines the correct FK (references auth.users), but the live DB was
-- provisioned with an older migration.
--
-- Fix: Drop every FK constraint on profiles.id that targets a `users`
-- table, then add the single correct constraint targeting auth.users.
--
-- Idempotent: safe to run multiple times.
-- ============================================================================

-- 1) Drop every existing FK on profiles.id that references ANY "users"
--    table (public.users or auth.users — we recreate the correct one
--    regardless).
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
      AND c.contype = 'f'                          -- foreign-key only
      AND EXISTS (                                 -- targets some "users" table
        SELECT 1
        FROM pg_class ref
        JOIN pg_namespace rn ON ref.relnamespace = rn.oid
        WHERE ref.oid = c.confrelid
          AND ref.relname = 'users'
      )
  LOOP
    EXECUTE 'ALTER TABLE public.profiles DROP CONSTRAINT ' || quote_ident(conname);
    RAISE NOTICE 'Dropped FK constraint: %', conname;
  END LOOP;
END $$;

-- 2) Ensure profiles.id is a uuid primary key (it should already be).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.profiles'::regclass
      AND contype = 'p'
  ) THEN
    ALTER TABLE public.profiles ADD PRIMARY KEY (id);
  END IF;
END $$;

-- 3) Add the correct FK: profiles.id → auth.users(id).
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
    RAISE NOTICE 'Correct FK already exists — no change.';
  END IF;
END $$;

-- 4) Clean up: if a public.users table exists and is empty / unused, drop
--    it. (Skipped automatically if the table does not exist.)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = 'public' AND tablename = 'users'
  ) THEN
    -- Only drop if the table has no rows (safety check).
    IF (SELECT count(*) FROM public.users) = 0 THEN
      DROP TABLE public.users CASCADE;
      RAISE NOTICE 'Dropped empty public.users table.';
    ELSE
      RAISE NOTICE 'public.users has rows — leaving it in place.';
    END IF;
  END IF;
END $$;

-- 5) Make sure the INSERT RLS policy exists so the app can upsert profiles.
DROP POLICY IF EXISTS "users can insert their own profile" ON public.profiles;
CREATE POLICY "users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Done. After running this, the set_user_role RPC and the auth trigger
-- should work without 23503 errors.
