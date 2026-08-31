-- ============================================================
-- Response Time Tracking
-- ============================================================
-- Run this in the Supabase SQL Editor to add response time analytics.
-- ============================================================

-- 1. Add responded_at column to bookings.
-- This records when the provider first responded (accepted, rejected, or cancelled)
-- to a pending booking. NULL means the booking hasn't been responded to yet.
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS responded_at TIMESTAMPTZ;

-- 2. Index for fast response time queries.
CREATE INDEX IF NOT EXISTS idx_bookings_responded_at
  ON bookings(provider_id, responded_at)
  WHERE responded_at IS NOT NULL;

-- 3. Average response time for a provider within a date range.
-- Returns the average in MINUTES.
CREATE OR REPLACE FUNCTION get_avg_response_time(
  p_provider_id UUID,
  p_start TIMESTAMPTZ DEFAULT NULL,
  p_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS NUMERIC AS $$
  SELECT
    CASE
      WHEN COUNT(*) = 0 THEN 0
      ELSE ROUND(
        AVG(EXTRACT(EPOCH FROM (responded_at - created_at)) / 60.0)::NUMERIC,
        1
      )
    END
  FROM bookings
  WHERE provider_id = p_provider_id
    AND responded_at IS NOT NULL
    AND created_at IS NOT NULL
    AND (p_start IS NULL OR created_at >= p_start)
    AND (p_end IS NULL OR created_at < p_end);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 4. Response rate: percentage of pending bookings that got a response.
CREATE OR REPLACE FUNCTION get_response_rate(
  p_provider_id UUID,
  p_start TIMESTAMPTZ DEFAULT NULL,
  p_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS NUMERIC AS $$
  SELECT
    CASE
      WHEN total = 0 THEN 0
      ELSE ROUND((responded::NUMERIC / total) * 100, 1)
    END
  FROM (
    SELECT
      COUNT(*)::INTEGER AS total,
      COUNT(responded_at)::INTEGER AS responded
    FROM bookings
    WHERE provider_id = p_provider_id
      AND (p_start IS NULL OR created_at >= p_start)
      AND (p_end IS NULL OR created_at < p_end)
  ) sub;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 5. Fastest and slowest response times for context.
CREATE OR REPLACE FUNCTION get_response_time_range(
  p_provider_id UUID,
  p_start TIMESTAMPTZ DEFAULT NULL,
  p_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE(fastest_min NUMERIC, slowest_min NUMERIC) AS $$
  SELECT
    ROUND(MIN(EXTRACT(EPOCH FROM (responded_at - created_at)) / 60.0)::NUMERIC, 1),
    ROUND(MAX(EXTRACT(EPOCH FROM (responded_at - created_at)) / 60.0)::NUMERIC, 1)
  FROM bookings
  WHERE provider_id = p_provider_id
    AND responded_at IS NOT NULL
    AND created_at IS NOT NULL
    AND (p_start IS NULL OR created_at >= p_start)
    AND (p_end IS NULL OR created_at < p_end);
$$ LANGUAGE sql STABLE SECURITY DEFINER;
