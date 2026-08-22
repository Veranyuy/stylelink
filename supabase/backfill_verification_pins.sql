-- =============================================================================
-- StyleLink — Backfill verification PINs for confirmed/arrived/in_progress bookings
-- =============================================================================
-- Generates a random 4-digit PIN (0000–9999) for any booking in an active
-- status that doesn't already have one.  Safe to re-run (skips rows that
-- already have a PIN).
-- =============================================================================

UPDATE public.bookings
SET verification_pin = lpad(floor(random() * 10000)::int::text, 4, '0')
WHERE status IN ('confirmed', 'arrived', 'in_progress')
  AND (verification_pin IS NULL OR verification_pin = '');

-- Show what was updated.
DO $$
DECLARE
  cnt int;
BEGIN
  SELECT count(*) INTO cnt
  FROM public.bookings
  WHERE status IN ('confirmed', 'arrived', 'in_progress')
    AND verification_pin IS NOT NULL
    AND verification_pin != '';

  RAISE NOTICE 'Active bookings with PINs: %', cnt;
END $$;

NOTIFY pgrst, 'reload schema';
