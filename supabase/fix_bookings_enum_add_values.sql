-- =============================================================================
-- StyleLink — Add missing values to booking_status enum
-- =============================================================================
-- This is the nuclear option: directly ALTER TYPE to add every value
-- the app needs, regardless of what's already there.
-- =============================================================================

-- Add each value only if it doesn't already exist.
DO $$
BEGIN
  -- arrived
  BEGIN
    ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'arrived';
    RAISE NOTICE 'Added: arrived';
  EXCEPTION
    WHEN duplicate_object THEN RAISE NOTICE 'Already exists: arrived';
  END;

  -- in_progress
  BEGIN
    ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'in_progress';
    RAISE NOTICE 'Added: in_progress';
  EXCEPTION
    WHEN duplicate_object THEN RAISE NOTICE 'Already exists: in_progress';
  END;

  -- rejected
  BEGIN
    ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'rejected';
    RAISE NOTICE 'Added: rejected';
  EXCEPTION
    WHEN duplicate_object THEN RAISE NOTICE 'Already exists: rejected';
  END;
END $$;

-- Reload PostgREST schema cache.
NOTIFY pgrst, 'reload schema';

-- Verify what values the enum now has.
DO $$
DECLARE
  val text;
BEGIN
  RAISE NOTICE 'Current booking_status enum values:';
  FOR val IN
    SELECT e.enumlabel
    FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    WHERE t.typname = 'booking_status'
    ORDER BY e.enumsortorder
  LOOP
    RAISE NOTICE '  - %', val;
  END LOOP;
END $$;
