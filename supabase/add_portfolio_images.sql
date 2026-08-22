-- ============================================================================
-- StyleLink — Add portfolio images support
-- ============================================================================
-- Adds a `portfolio_images` text array column to `public.providers` and
-- creates a `provider_portfolios` storage bucket for work-sample photos.
--
-- Run this in the Supabase SQL editor. Idempotent.
-- ============================================================================

-- 1) Add the portfolio_images column (array of image URLs, max 7 enforced in app).
ALTER TABLE public.providers
  ADD COLUMN IF NOT EXISTS portfolio_images text[] NOT NULL DEFAULT '{}';

-- 2) Create the storage bucket for portfolio photos.
INSERT INTO storage.buckets (id, name, public)
VALUES ('provider_portfolios', 'provider_portfolios', true)
ON CONFLICT (id) DO NOTHING;

-- 3) Storage policies: providers can manage their own portfolio images.
--    Anyone can read (public bucket).

-- Public read access.
DROP POLICY IF EXISTS "portfolio images are readable" ON storage.objects;
CREATE POLICY "portfolio images are readable"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'provider_portfolios');

-- Providers can upload their own images.
DROP POLICY IF EXISTS "providers upload their own portfolio" ON storage.objects;
CREATE POLICY "providers upload their own portfolio"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'provider_portfolios'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Providers can update their own images.
DROP POLICY IF EXISTS "providers update their own portfolio" ON storage.objects;
CREATE POLICY "providers update their own portfolio"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'provider_portfolios' AND owner = auth.uid())
  WITH CHECK (
    bucket_id = 'provider_portfolios'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Providers can delete their own images.
DROP POLICY IF EXISTS "providers delete their own portfolio" ON storage.objects;
CREATE POLICY "providers delete their own portfolio"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'provider_portfolios' AND owner = auth.uid());

NOTIFY pgrst, 'reload schema';
