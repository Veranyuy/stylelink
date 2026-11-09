-- ============================================================================
-- StyleLink — Hidden-shop visibility gate
-- ============================================================================
-- Run this in the Supabase SQL editor. Idempotent; safe to re-run.
--
-- WHY
--   A provider whose shop has 0 active services is "hidden": the Flutter app
--   already refuses to show it (onboarding banner + provider onboarding
--   wizard), but the rule lived only in client code. Any bypass (curl with
--   the anon key, an old app build, direct PostgREST queries) could still
--   list every `providers` row.
--
-- WHAT
--   1. Ensures `services.is_active` exists (some deployed databases drifted
--      from schema.sql and lack the column — see the 42703 fallback in
--      fetchServicesForProvider).
--   2. Adds public.provider_is_visible(provider_id): a SECURITY DEFINER
--      helper that reports whether the shop has >= 1 active service.
--   3. Replaces the `providers` SELECT policy: only the owner, or shops with
--      at least one active service, are readable.
--   4. Replaces the `services` SELECT policy the same way, so a hidden shop
--      leaks nothing at all (not even its service menu).
--
-- RECURSION NOTE (important)
--   A `providers` policy that subqueries `services` — while the `services`
--   "manage own" policy subqueries `providers` — would recurse infinitely
--   (Postgres error 42P17). Wrapping the services check in a SECURITY
--   DEFINER function bypasses RLS inside the function and breaks the cycle.
--   This is the standard Supabase pattern for cross-table RLS.
--
-- PERFORMANCE
--   EXISTS + LIMIT 1 against services_provider_idx: constant-time per row.
--   The function is STABLE so Postgres can cache it per statement.
--
-- TRADE-OFFS (accepted)
--   * Enrichment lookups (booking detail sheets, message threads, favorites)
--    for a shop that went hidden after a booking was made return no row;
--     the UI already falls back to placeholder names.
--   * The provider's own app always sees their row via the owner branch.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Drift guard: the deployed `services` table may predate `is_active`.
--    schema.sql defines it NOT NULL DEFAULT true, so mirror that exactly.
-- ---------------------------------------------------------------------------
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

-- ---------------------------------------------------------------------------
-- 1. Visibility helper. TRUE once the shop lists >= 1 active service.
--    SECURITY DEFINER => reads services without RLS, so calling it from
--    policies on either table cannot recurse.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.provider_is_visible(p_provider_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.services s
    WHERE s.provider_id = p_provider_id
      AND s.is_active
    LIMIT 1
  );
$$;

-- RLS policy evaluation runs as the querying role, so that role needs
-- EXECUTE. The function exposes only a boolean — no service data leaks.
REVOKE EXECUTE ON FUNCTION public.provider_is_visible(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.provider_is_visible(uuid) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Providers: owner always readable; everyone else only when the shop
--    has at least one active service (a "hidden" shop never appears).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "providers are readable by everyone" ON public.providers;
CREATE POLICY "providers are readable by everyone"
  ON public.providers FOR SELECT
  USING (
    auth.uid() = user_id
    OR public.provider_is_visible(id)
  );

-- ---------------------------------------------------------------------------
-- 3. Services: same gate, so a hidden shop's menu is not enumerable either.
--    (The separate "providers can manage their own services" FOR ALL policy
--    is untouched — providers keep full CRUD on their own catalog.)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "services are readable by everyone" ON public.services;
CREATE POLICY "services are readable by everyone"
  ON public.services FOR SELECT
  USING (
    public.provider_is_visible(provider_id)
    OR EXISTS (
      SELECT 1 FROM public.providers p
      WHERE p.id = services.provider_id
        AND p.user_id = auth.uid()
    )
  );

-- Reload PostgREST schema cache.
NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  total   int;
  hidden  int;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'services'
      AND column_name = 'is_active'
  ) THEN
    RAISE WARNING '✗ services.is_active MISSING — visibility gate cannot work';
  ELSE
    RAISE NOTICE '✓ services.is_active exists';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'providers'
      AND policyname = 'providers are readable by everyone'
  ) THEN
    RAISE NOTICE '✓ providers SELECT policy is visibility-gated';
  ELSE
    RAISE WARNING '✗ providers SELECT policy missing';
  END IF;

  SELECT COUNT(*) INTO total  FROM public.providers;
  SELECT COUNT(*) INTO hidden FROM public.providers p
    WHERE NOT public.provider_is_visible(p.id);
  RAISE NOTICE '✓ shops: % total, % hidden (0 active services)', total, hidden;
END $$;
