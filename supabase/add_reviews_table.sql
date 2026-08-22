-- =============================================================================
-- reviews table + provider rating trigger
-- Run this in the Supabase SQL Editor.
-- =============================================================================

-- 1. Create the reviews table
CREATE TABLE IF NOT EXISTS public.reviews (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id  uuid NOT NULL UNIQUE REFERENCES public.bookings(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL REFERENCES public.providers(id) ON DELETE CASCADE,
  client_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rating      integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 2. Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_reviews_provider  ON public.reviews(provider_id);
CREATE INDEX IF NOT EXISTS idx_reviews_booking   ON public.reviews(booking_id);
CREATE INDEX IF NOT EXISTS idx_reviews_client    ON public.reviews(client_id);

-- 3. RLS policies
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- Anyone can read reviews (public profiles).
CREATE POLICY "Public read access to reviews"
  ON public.reviews FOR SELECT
  USING (true);

-- Clients can insert reviews for their own completed bookings.
CREATE POLICY "Clients can insert reviews"
  ON public.reviews FOR INSERT
  WITH CHECK (
    auth.uid() = client_id
    AND EXISTS (
      SELECT 1 FROM public.bookings b
      WHERE b.id = booking_id
        AND b.client_id = auth.uid()
        AND b.status = 'completed'
    )
  );

-- 4. Trigger function: auto-update provider rating & review_count
-- Uses a RUNNING average so each new review adjusts the rating smoothly.
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

-- 5. Attach trigger (IF NOT EXISTS not supported for triggers, so drop first).
DROP TRIGGER IF EXISTS on_review_insert ON public.reviews;
CREATE TRIGGER on_review_insert
  AFTER INSERT ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_review_insert();

-- 6. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
