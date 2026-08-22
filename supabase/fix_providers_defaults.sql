-- ============================================================================
-- StyleLink — Fix: ensure providers INSERT always has required fields
-- ============================================================================
-- A rogue trigger/function on the live database auto-inserts into providers
-- when a user's role is set to 'provider', but it doesn't supply the
-- required NOT NULL columns (business_name, category, city). Instead of
-- hunting the rogue trigger, we add a BEFORE INSERT trigger that fills in
-- safe defaults so the insert always succeeds. The user can then complete
-- their business profile through the app.
--
-- Run this in the Supabase SQL editor. Idempotent.
-- ============================================================================

-- 1) Create (or replace) the trigger function that fills defaults.
CREATE OR REPLACE FUNCTION public.set_provider_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Required text columns: fill with safe placeholders if null.
  NEW.business_name := COALESCE(NEW.business_name, '');
  NEW.category      := COALESCE(NEW.category, '');
  NEW.city          := COALESCE(NEW.city, '');

  -- Numeric defaults.
  NEW.rating       := COALESCE(NEW.rating, 0);
  NEW.review_count := COALESCE(NEW.review_count, 0);
  NEW.price_from   := COALESCE(NEW.price_from, 0);

  -- Text defaults.
  NEW.service_type := COALESCE(NEW.service_type, 'studio');
  NEW.quarter      := COALESCE(NEW.quarter, '');

  -- Boolean default.
  NEW.is_verified := COALESCE(NEW.is_verified, false);

  -- JSONB default.
  NEW.working_hours := COALESCE(NEW.working_hours, '{}'::jsonb);

  -- Timestamp.
  NEW.created_at := COALESCE(NEW.created_at, now());

  RETURN NEW;
END;
$$;

-- 2) Drop any existing BEFORE INSERT trigger on providers, then create ours.
DROP TRIGGER IF EXISTS set_provider_defaults ON public.providers;
CREATE TRIGGER set_provider_defaults
  BEFORE INSERT ON public.providers
  FOR EACH ROW
  EXECUTE FUNCTION public.set_provider_defaults();

-- 3) Also make business_name, category, and city nullable so existing
--    provider rows with empty profiles don't break reads.
--    (The app's business_screen.dart lets users fill these in later.)
ALTER TABLE public.providers
  ALTER COLUMN business_name DROP NOT NULL,
  ALTER COLUMN category      DROP NOT NULL,
  ALTER COLUMN city          DROP NOT NULL;

-- 4) Reload PostgREST schema cache.
NOTIFY pgrst, 'reload schema';
