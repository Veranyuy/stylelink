-- =============================================================================
-- StyleLink — Fix: add arrived and in_progress to bookings.status constraint
-- =============================================================================
-- The original schema only allows: pending, confirmed, completed, cancelled, rejected
-- The service tracker needs: arrived, in_progress
--
-- Run this in the Supabase SQL editor. Idempotent.
-- =============================================================================

-- Drop the old constraint and recreate with the full set of valid statuses.
ALTER TABLE public.bookings
  DROP CONSTRAINT IF EXISTS bookings_status_check;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_status_check
  CHECK (status IN (
    'pending',
    'confirmed',
    'arrived',
    'in_progress',
    'completed',
    'cancelled',
    'rejected'
  ));

-- Also ensure arrived_at, started_at, completed_at, arrival_lat, arrival_lng,
-- and verification_pin columns exist (the service tracker writes these).
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS arrived_at        timestamptz,
  ADD COLUMN IF NOT EXISTS started_at        timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at      timestamptz,
  ADD COLUMN IF NOT EXISTS arrival_lat       double precision,
  ADD COLUMN IF NOT EXISTS arrival_lng       double precision,
  ADD COLUMN IF NOT EXISTS verification_pin  text;

-- Generate a default verification_pin for confirmed bookings that don't have one.
-- (Lpad with zeros to ensure 4 digits.)
UPDATE public.bookings
SET verification_pin = lpad(floor(random() * 10000)::int::text, 4, '0')
WHERE status IN ('confirmed', 'arrived', 'in_progress')
  AND (verification_pin IS NULL OR verification_pin = '');

-- Reload PostgREST schema cache.
NOTIFY pgrst, 'reload schema';

RAISE NOTICE 'bookings.status CHECK constraint updated with arrived + in_progress';
