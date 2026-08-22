-- =============================================================================
-- reviews table + provider rating trigger (v2 — more forgiving)
-- Run this in the Supabase SQL Editor.
-- =============================================================================

-- 1. Create the reviews table (safe to re-run)
CREATE TABLE IF NOT EXISTS public.reviews (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id  uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL REFERENCES public.providers(id) ON DELETE CASCADE,
  client_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rating      integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Add UNIQUE constraint separately (safe to re-run).
DO $$
BEGIN
  ALTER TABLE public.reviews ADD CONSTRAINT reviews_booking_id_unique UNIQUE (booking_id);
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

-- 2. Indexes for fast lookups (safe to re-run).
CREATE INDEX IF NOT EXISTS idx_reviews_provider ON public.reviews(provider_id);
CREATE INDEX IF NOT EXISTS idx_reviews_booking  ON public.reviews(booking_id);
CREATE INDEX IF NOT EXISTS idx_reviews_client   ON public.reviews(client_id);

-- 3. RLS — drop and recreate to guarantee clean state.
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read access to reviews" ON public.reviews;
DROP POLICY IF EXISTS "Clients can insert reviews" ON public.reviews;
DROP POLICY IF EXISTS "Authenticated insert reviews" ON public.reviews;
DROP POLICY IF EXISTS "reviews_select_public" ON public.reviews;
DROP POLICY IF EXISTS "reviews_insert_auth" ON public.reviews;

-- Anyone can read reviews.
CREATE POLICY "reviews_select_public"
  ON public.reviews FOR SELECT
  USING (true);

-- Any authenticated user can insert (we validate client_id in the app code).
-- This avoids brittle subquery RLS that may fail on enum remnants.
CREATE POLICY "reviews_insert_auth"
  ON public.reviews FOR INSERT
  WITH CHECK (auth.uid() = client_id);

-- 4. Trigger function: auto-update provider rating & review_count.
CREATE OR REPLACE FUNCTION public.handle_review_insert()
RETURNS trigger AS $$
BEGIN
  UPDATE public.providers
  SET
    rating = (
      SELECT COALESCE(AVG(r.rating), 0)::numeric(3,1)
      FROM public.reviews r
      WHERE r.provider_id = NEW.provider_id
    ),
    review_count = (
      SELECT COUNT(*)::int
      FROM public.reviews r
      WHERE r.provider_id = NEW.provider_id
    )
  WHERE id = NEW.provider_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Attach trigger.
DROP TRIGGER IF EXISTS on_review_insert ON public.reviews;
CREATE TRIGGER on_review_insert
  AFTER INSERT ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_review_insert();

-- 6. Reload PostgREST schema cache.
NOTIFY pgrst, 'reload schema';

-- 7. Verify: count existing reviews (should be 0).
SELECT COUNT(*) AS review_count FROM public.reviews;
