-- =============================================================================
-- StyleLink — Convert bookings.status from ENUM to TEXT
-- =============================================================================
-- The live database uses a PostgreSQL ENUM type `booking_status` which only
-- contains the original values (pending, confirmed, completed, cancelled).
-- Our app needs: arrived, in_progress, rejected.
--
-- Rather than ALTER TYPE for every new value, convert to TEXT so future
-- statuses work without migration. Idempotent.
-- =============================================================================

-- 1) If the column is already TEXT, this is a no-op.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'bookings'
      AND column_name = 'status'
      AND udt_name = 'booking_status'
  ) THEN
    -- Convert ENUM → TEXT.
    ALTER TABLE public.bookings
      ALTER COLUMN status TYPE text USING status::text;

    RAISE NOTICE 'Converted bookings.status from enum to text.';
  ELSE
    RAISE NOTICE 'bookings.status is already text — no conversion needed.';
  END IF;
END $$;

-- 2) Drop the old enum type if it exists and is no longer referenced.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON t.typnamespace = n.oid
    WHERE n.nspname = 'public'
      AND t.typname = 'booking_status'
  ) THEN
    -- Only drop if no other columns use it.
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE udt_name = 'booking_status'
        AND table_schema = 'public'
    ) THEN
      DROP TYPE public.booking_status;
      RAISE NOTICE 'Dropped enum type public.booking_status.';
    ELSE
      RAISE NOTICE 'Enum type still in use — leaving it.';
    END IF;
  END IF;
END $$;

-- 3) Ensure the CHECK constraint allows all our statuses.
ALTER TABLE public.bookings
  DROP CONSTRAINT IF EXISTS bookings_status_check;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_status_check
  CHECK (status IN (
    'pending', 'confirmed', 'arrived', 'in_progress',
    'completed', 'cancelled', 'rejected'
  ));

-- 4) Reload PostgREST schema cache.
NOTIFY pgrst, 'reload schema';

RAISE NOTICE 'bookings.status is now TEXT with full CHECK constraint.';
