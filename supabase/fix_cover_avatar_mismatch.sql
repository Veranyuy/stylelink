-- ============================================================================
-- Fix cover_url / avatar_url mismatch
--
-- If previous testing saved the user's face photo into providers.cover_url,
-- this resets those rows so cover_url only holds business showcase images.
--
-- Run this in the Supabase SQL Editor.
-- ============================================================================

-- 1. Reset cover_url where it duplicates avatar_url (face photo leak).
UPDATE providers
SET cover_url = NULL
WHERE cover_url IS NOT NULL
  AND avatar_url IS NOT NULL
  AND cover_url = avatar_url;

-- 2. Also reset cover_url where it matches the profiles.avatar_url directly.
UPDATE providers p
SET cover_url = NULL
FROM profiles pr
WHERE p.user_id = pr.id
  AND p.cover_url IS NOT NULL
  AND pr.avatar_url IS NOT NULL
  AND p.cover_url = pr.avatar_url;

-- 3. Verify the cleanup.
SELECT
  p.id,
  p.business_name,
  p.cover_url,
  p.avatar_url,
  pr.avatar_url AS profile_avatar_url
FROM providers p
LEFT JOIN profiles pr ON p.user_id = pr.id
WHERE p.cover_url IS NOT NULL
ORDER BY p.created_at DESC
LIMIT 20;
