-- =============================================================================
-- StyleLink — Add is_available column to providers
-- =============================================================================
-- Run this in the Supabase SQL editor. Idempotent.
-- =============================================================================

-- Add the column (default true = available).
ALTER TABLE public.providers
  ADD COLUMN IF NOT EXISTS is_available boolean NOT NULL DEFAULT true;

-- Reload PostgREST schema cache.
NOTIFY pgrst, 'reload schema';

-- Verify.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'providers'
      AND column_name = 'is_available'
  ) THEN
    RAISE NOTICE '✓ providers.is_available exists';
  ELSE
    RAISE WARNING '✗ providers.is_available MISSING';
  END IF;
END $$;
