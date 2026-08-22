-- =============================================================================
-- StyleLink — Drop rogue trigger referencing total_amount on bookings
-- =============================================================================
-- A trigger/function on the live database references new.total_amount which
-- doesn't exist (the column is total_price_fcfa). Drop it.
-- =============================================================================

-- 1) Drop ALL triggers on bookings that aren't ours.
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
    RAISE NOTICE 'Dropped trigger on bookings: %', r.trigger_name;
  END LOOP;
END $$;

-- 2) Drop ALL trigger functions that reference total_amount.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.proname AS func_name
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.prosrc ILIKE '%total_amount%'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '() CASCADE';
    RAISE NOTICE 'Dropped function referencing total_amount: public.%', r.func_name;
  END LOOP;
END $$;

-- 3) Also drop functions referencing total_amount with any signature.
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
      AND p.prosrc ILIKE '%total_amount%'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.func_name) || '(' || r.args || ') CASCADE';
    RAISE NOTICE 'Dropped: public.%(%)', r.func_name, r.args;
  END LOOP;
END $$;

-- 4) Reload schema cache.
NOTIFY pgrst, 'reload schema';

RAISE NOTICE 'All triggers/functions referencing total_amount have been dropped.';
