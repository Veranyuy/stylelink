-- =============================================================================
-- StyleLink — Force-convert bookings.status from ENUM to TEXT (v2)
-- =============================================================================
-- ALTER TYPE ADD VALUE doesn't work inside transactions (Supabase SQL Editor).
-- This script swaps the column to TEXT using a safe rename approach.
-- =============================================================================

-- Step 1: Add a new TEXT column.
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS status_text text;

-- Step 2: Copy existing status values (cast enum → text).
UPDATE public.bookings SET status_text = status::text;

-- Step 3: Set NOT NULL and default on the new column.
ALTER TABLE public.bookings
  ALTER COLUMN status_text SET DEFAULT 'pending',
  ALTER COLUMN status_text SET NOT NULL;

-- Step 4: Drop the old enum column.
ALTER TABLE public.bookings DROP COLUMN status;

-- Step 5: Rename the new column to 'status'.
ALTER TABLE public.bookings RENAME COLUMN status_text TO status;

-- Step 6: Add CHECK constraint.
ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_status_check
  CHECK (status IN (
    'pending', 'confirmed', 'arrived', 'in_progress',
    'completed', 'cancelled', 'rejected'
  ));

-- Step 7: Reload PostgREST schema cache.
NOTIFY pgrst, 'reload schema';

-- Step 8: Verify.
DO $$
DECLARE
  cnt int;
  sample text;
BEGIN
  SELECT count(*), (array_agg(status))[1]
  INTO cnt, sample
  FROM public.bookings;

  RAISE NOTICE 'bookings table has % rows. Sample status: %', cnt, sample;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'bookings'
      AND column_name = 'status'
      AND udt_name = 'text'
  ) THEN
    RAISE NOTICE '✓ bookings.status is now TEXT';
  ELSE
    RAISE WARNING '✗ bookings.status is NOT text yet';
  END IF;
END $$;
