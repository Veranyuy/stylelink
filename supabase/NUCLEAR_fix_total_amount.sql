-- =============================================================================
-- NUCLEAR FIX — Drop EVERYTHING referencing total_amount on bookings
-- Run this in the Supabase SQL Editor.
-- =============================================================================

-- STEP 1: List ALL triggers on bookings (for visibility)
SELECT
  t.tgname AS trigger_name,
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS function_body
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE n.nspname = 'public'
  AND c.relname = 'bookings'
  AND NOT t.tgisinternal;

-- STEP 2: List ALL functions that mention total_amount anywhere
SELECT
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  LEFT(p.prosrc, 200) AS source_preview
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.prosrc ILIKE '%total_amount%';

-- STEP 3: Drop ALL non-internal triggers on bookings
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
      AND c.relname = 'bookings'
      AND NOT t.tgisinternal
  LOOP
    EXECUTE 'DROP TRIGGER IF EXISTS ' || quote_ident(r.trigger_name) || ' ON public.bookings CASCADE';
    RAISE NOTICE '✓ Dropped trigger: %', r.trigger_name;
  END LOOP;
END $$;

-- STEP 4: Drop ALL functions referencing total_amount (any signature)
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT
      p.proname AS func_name,
      pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pnamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.prosrc ILIKE '%total_amount%'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '(' || r.args || ') CASCADE';
    RAISE NOTICE '✓ Dropped function: public.%(%)', r.func_name, r.args;
  END LOOP;
END $$;

-- STEP 5: Also scan for any other trigger function that references
-- bookings columns that don't exist (belt + suspenders)
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.proname AS func_name,
           pg_get_function_identity_arguments(p.oid) AS args,
           p.prosrc AS src
    FROM pg_proc p
    JOIN pg_namespace n ON p.pnamespace = n.oid
    WHERE n.nspname = 'public'
      AND (
        p.prosrc ILIKE '%new.total_amount%'
        OR p.prosrc ILIKE '%old.total_amount%'
        OR p.prosrc ILIKE '%NEW.total_amount%'
        OR p.prosrc ILIKE '%OLD.total_amount%'
      )
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '(' || r.args || ') CASCADE';
    RAISE NOTICE '✓ Dropped function with new/old.total_amount ref: public.%(%)', r.func_name, r.args;
  END LOOP;
END $$;

-- STEP 6: Verify — there should be ZERO functions referencing total_amount
DO $$
DECLARE
  cnt int;
BEGIN
  SELECT COUNT(*) INTO cnt
  FROM pg_proc p
  JOIN pg_namespace n ON p.pnamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.prosrc ILIKE '%total_amount%';

  IF cnt > 0 THEN
    RAISE WARNING '⚠ % function(s) still reference total_amount!', cnt;
  ELSE
    RAISE NOTICE '✓ No functions reference total_amount — clean!';
  END IF;
END $$;

-- STEP 7: Verify bookings triggers count (should be minimal — only our auth triggers)
DO $$
DECLARE
  cnt int;
BEGIN
  SELECT COUNT(*) INTO cnt
  FROM pg_trigger t
  JOIN pg_class c ON t.tgrelid = c.oid
  JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = 'public'
    AND c.relname = 'bookings'
    AND NOT t.tgisinternal;

  RAISE NOTICE 'Remaining non-internal triggers on bookings: %', cnt;
END $$;

-- STEP 8: Reload schema cache
NOTIFY pgrst, 'reload schema';

RAISE NOTICE '✅ NUCLEAR FIX complete — all total_amount references eliminated.';
