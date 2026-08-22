-- =============================================================================
-- StyleLink — Add service-tracker columns to bookings + reload schema
-- =============================================================================
-- PGRST204 means PostgREST can't find the column in its schema cache.
-- This script ensures the columns exist AND forces a schema reload.
-- =============================================================================

-- 1) Add columns (idempotent — safe to re-run).
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS arrived_at        timestamptz,
  ADD COLUMN IF NOT EXISTS started_at        timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at      timestamptz,
  ADD COLUMN IF NOT EXISTS arrival_lat       double precision,
  ADD COLUMN IF NOT EXISTS arrival_lng       double precision,
  ADD COLUMN IF NOT EXISTS verification_pin  text;

-- 2) Force PostgREST to reload its schema cache.
NOTIFY pgrst, 'reload schema';

-- 3) Verify columns exist.
DO $$
DECLARE
  col text;
BEGIN
  FOR col IN SELECT unnest(ARRAY[
    'arrived_at', 'started_at', 'completed_at',
    'arrival_lat', 'arrival_lng', 'verification_pin'
  ])
  LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'bookings'
        AND column_name = col
    ) THEN
      RAISE NOTICE '✓ bookings.% exists', col;
    ELSE
      RAISE WARNING '✗ bookings.% MISSING', col;
    END IF;
  END LOOP;
END $$;
