-- ═══════════════════════════════════════════════════════════════════════════
-- Blocked Providers — lets clients block / report providers.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Table
CREATE TABLE IF NOT EXISTS public.blocked_providers (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES public.providers(id) ON DELETE CASCADE,
  reason     TEXT,               -- e.g. 'inappropriate', 'spam', 'other'
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, provider_id)
);

-- 2. RLS — users can only see / insert / delete their own blocks.
ALTER TABLE public.blocked_providers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own blocks"
  ON public.blocked_providers FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can block a provider"
  ON public.blocked_providers FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can unblock a provider"
  ON public.blocked_providers FOR DELETE
  USING (auth.uid() = user_id);

-- 3. Index for fast lookups.
CREATE INDEX IF NOT EXISTS idx_blocked_providers_user
  ON public.blocked_providers (user_id);

CREATE INDEX IF NOT EXISTS idx_blocked_providers_provider
  ON public.blocked_providers (provider_id);
