-- ============================================================
-- Provider Analytics Tables
-- ============================================================
-- Run this in the Supabase SQL Editor to add analytics tracking.
-- ============================================================

-- 1. Profile views — one row per unique client viewing a provider per day.
CREATE TABLE IF NOT EXISTS profile_views (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_id UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  viewer_id   UUID REFERENCES profiles(id) ON DELETE SET NULL,
  viewed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Deduplicate: one view per client per provider per day.
  UNIQUE(provider_id, viewer_id, date_trunc('day', viewed_at))
);

-- 2. Search impressions — one row each time a provider appears in search results.
CREATE TABLE IF NOT EXISTS search_impressions (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_id UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  query       TEXT,
  city        TEXT,
  category    TEXT,
  shown_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Indexes for fast analytics queries.
CREATE INDEX IF NOT EXISTS idx_profile_views_provider
  ON profile_views(provider_id, viewed_at);
CREATE INDEX IF NOT EXISTS idx_search_impressions_provider
  ON search_impressions(provider_id, shown_at);

-- ============================================================
-- RLS Policies
-- ============================================================

ALTER TABLE profile_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE search_impressions ENABLE ROW LEVEL SECURITY;

-- Providers can read their own analytics.
CREATE POLICY "Providers read own profile views"
  ON profile_views FOR SELECT
  USING (
    provider_id IN (SELECT id FROM providers WHERE user_id = auth.uid())
  );

CREATE POLICY "Providers read own search impressions"
  ON search_impressions FOR SELECT
  USING (
    provider_id IN (SELECT id FROM providers WHERE user_id = auth.uid())
  );

-- Any authenticated user can insert (for recording views/impressions).
CREATE POLICY "Authenticated insert profile views"
  ON profile_views FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated insert search impressions"
  ON search_impressions FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- ============================================================
-- Helper Functions
-- ============================================================

-- Count profile views for a provider within a date range.
CREATE OR REPLACE FUNCTION get_profile_view_count(
  p_provider_id UUID,
  p_start TIMESTAMPTZ DEFAULT NULL,
  p_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS INTEGER AS $$
  SELECT COUNT(*)::INTEGER
  FROM profile_views
  WHERE provider_id = p_provider_id
    AND (p_start IS NULL OR viewed_at >= p_start)
    AND (p_end IS NULL OR viewed_at < p_end);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Count search impressions for a provider within a date range.
CREATE OR REPLACE FUNCTION get_search_impression_count(
  p_provider_id UUID,
  p_start TIMESTAMPTZ DEFAULT NULL,
  p_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS INTEGER AS $$
  SELECT COUNT(*)::INTEGER
  FROM search_impressions
  WHERE provider_id = p_provider_id
    AND (p_start IS NULL OR shown_at >= p_start)
    AND (p_end IS NULL OR shown_at < p_end);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Booking conversion rate: completed bookings / profile views within a range.
CREATE OR REPLACE FUNCTION get_conversion_rate(
  p_provider_id UUID,
  p_start TIMESTAMPTZ DEFAULT NULL,
  p_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS NUMERIC AS $$
  SELECT
    CASE
      WHEN view_count = 0 THEN 0
      ELSE ROUND((booking_count::NUMERIC / view_count) * 100, 1)
    END
  FROM (
    SELECT
      get_profile_view_count(p_provider_id, p_start, p_end) AS view_count,
      COUNT(*)::INTEGER AS booking_count
    FROM bookings
    WHERE provider_id = p_provider_id
      AND status = 'completed'
      AND (p_start IS NULL OR created_at >= p_start)
      AND (p_end IS NULL OR created_at < p_end)
  ) sub;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Daily profile views for chart data within a range.
CREATE OR REPLACE FUNCTION get_daily_views(
  p_provider_id UUID,
  p_start TIMESTAMPTZ DEFAULT NULL,
  p_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE(day DATE, count BIGINT) AS $$
  SELECT
    date_trunc('day', viewed_at)::DATE AS day,
    COUNT(*) AS count
  FROM profile_views
  WHERE provider_id = p_provider_id
    AND (p_start IS NULL OR viewed_at >= p_start)
    AND (p_end IS NULL OR viewed_at < p_end)
  GROUP BY day
  ORDER BY day;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Top search queries that led to impressions for a provider.
CREATE OR REPLACE FUNCTION get_top_search_queries(
  p_provider_id UUID,
  p_limit INTEGER DEFAULT 10
)
RETURNS TABLE(query TEXT, count BIGINT) AS $$
  SELECT
    COALESCE(query, '(direct)') AS query,
    COUNT(*) AS count
  FROM search_impressions
  WHERE provider_id = p_provider_id
  GROUP BY query
  ORDER BY count DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
