-- ============================================================================
-- StyleLink — Hidden-shop nudge (scheduled re-engagement)
-- ============================================================================
-- Run this in the Supabase SQL editor. Idempotent; safe to re-run.
--
-- WHAT
--   A provider whose shop has 0 active services is hidden from clients (see
--   add_hidden_shop_visibility_gate.sql). This migration adds a scheduled
--   sweep that nudges providers whose shop has been hidden for over 24
--   hours: an FCM push when their device token is known, otherwise an
--   email via the Resend API (FIREBASE_*-style secrets, see
--   send-hidden-shop-nudge/index.ts).
--
-- HOW
--   1. `hidden_shop_nudges` tracks per-provider nudge state:
--      first_seen_hidden_at (for the 24h clock) and last_nudged_at (for
--      re-nudging every 3 days while the shop stays hidden).
--   2. sync_hidden_shop_candidates() refreshes that table from live data:
--        * shops with 0 active services                -> row present
--        * shops that gained an active service         -> row deleted
--      so the nudge stops the moment the shop goes live.
--   3. nudge_hidden_shops() enforces the throttles and dispatches the
--      payload to the `send-hidden-shop-nudge` edge function via pg_net.
--   4. pg_cron runs the sweep hourly (job 'stylelink-hidden-shop-nudge').
--
-- PREREQUISITES
--   * add_hidden_shop_visibility_gate.sql (services.is_active column)
--   * pg_cron enabled (Dashboard → Database → Extensions)
--   * Deploy supabase/functions/send-hidden-shop-nudge and set the DB
--     settings app.settings.edge_function_url / anon_key (the same pair
--     booking_notification_webhook.sql already uses — see
--     NOTIFICATION_SETUP.md step 4).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Prerequisites: services.is_active must exist (visibility gate migration)
--    and pg_net is used to call the edge function from the sweep.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'services'
      AND column_name = 'is_active'
  ) THEN
    ALTER TABLE public.services
      ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
    RAISE WARNING 'services.is_active was missing — created with default true';
  END IF;
END $$;

CREATE EXTENSION IF NOT EXISTS pg_net;

-- ---------------------------------------------------------------------------
-- 1. Nudge state table. One row per hidden shop.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hidden_shop_nudges (
  provider_id           uuid PRIMARY KEY
                          REFERENCES public.providers (id) ON DELETE CASCADE,
  first_seen_hidden_at  timestamptz NOT NULL DEFAULT now(),
  last_nudged_at        timestamptz,
  nudge_count           integer NOT NULL DEFAULT 0
);

ALTER TABLE public.hidden_shop_nudges ENABLE ROW LEVEL SECURITY;

-- Service-role only (the sweep runs as the service role; the app never
-- touches this table). No policies -> no client access at all.
REVOKE ALL ON public.hidden_shop_nudges FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Candidate sync — the single source of truth for "who is hidden".
--    Called at the start of every sweep, so state can never drift from the
--    live services table for more than one cron tick.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_hidden_shop_candidates()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  inserted_count integer;
BEGIN
  -- Hidden shops -> upsert a candidate row, preserving the original
  -- first_seen_hidden_at across re-runs.
  INSERT INTO public.hidden_shop_nudges (provider_id, first_seen_hidden_at)
  SELECT p.id, now()
  FROM public.providers p
  WHERE NOT EXISTS (
    SELECT 1 FROM public.services s
    WHERE s.provider_id = p.id AND s.is_active
  )
  ON CONFLICT (provider_id) DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;

  -- Shops that now have an active service -> forget them entirely.
  DELETE FROM public.hidden_shop_nudges h
  WHERE EXISTS (
    SELECT 1 FROM public.services s
    WHERE s.provider_id = h.provider_id AND s.is_active
  );

  RETURN inserted_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Sweep: nudge every hidden shop that is due.
--      * first nudge: hidden for > 24 hours
--      * repeat nudge: every 3 days after that
--    Sends to the edge function asynchronously via pg_net; the function
--    itself chooses push vs email and updates last_nudged_at/nudge_count
--    (see mark_hidden_shop_nudged RPC below).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.nudge_hidden_shops()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  endpoint_url text;
  anon_key     text;
  sent         integer := 0;
  r            record;
BEGIN
  PERFORM public.sync_hidden_shop_candidates();

  endpoint_url := current_setting('app.settings.nudge_function_url', true);
  IF endpoint_url IS NULL OR endpoint_url = '' THEN
    -- Fallback: derive it from the booking webhook URL (same project,
    -- different function name) so only one URL setting is required.
    endpoint_url := replace(
      COALESCE(current_setting('app.settings.edge_function_url', true), ''),
      'send-booking-notification',
      'send-hidden-shop-nudge'
    );
  END IF;
  anon_key := current_setting('app.settings.anon_key', true);
  IF endpoint_url IS NULL OR endpoint_url = '' THEN
    RAISE NOTICE 'nudge_hidden_shops: edge function URL not configured — skipping';
    RETURN 0;
  END IF;

  FOR r IN
    SELECT h.provider_id,
           h.first_seen_hidden_at,
           h.last_nudged_at,
           h.nudge_count,
           p.business_name,
           pr.fcm_token,
           pr.email,
           pr.full_name,
           pr.id             AS owner_profile_id,
           pr.language_preference
    FROM public.hidden_shop_nudges h
    JOIN public.providers   p  ON p.id  = h.provider_id
    JOIN public.profiles    pr ON pr.id = p.user_id
    WHERE h.first_seen_hidden_at < now() - interval '24 hours'
      AND (h.last_nudged_at IS NULL
           OR h.last_nudged_at < now() - interval '3 days')
  LOOP
    PERFORM net.http_post(
      url     := endpoint_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || anon_key
      ),
      body    := jsonb_build_object(
        'provider_id',          r.provider_id,
        'owner_profile_id',     r.owner_profile_id,
        'business_name',        r.business_name,
        'fcm_token',            r.fcm_token,
        'email',                r.email,
        'owner_name',           r.full_name,
        'language_preference',  r.language_preference,
        'first_seen_hidden_at', r.first_seen_hidden_at,
        'nudge_count',          r.nudge_count
      )::text
    );

    sent := sent + 1;
  END LOOP;

  RAISE NOTICE 'nudge_hidden_shops: dispatched % nudge request(s)', sent;
  RETURN sent;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Acknowledgement RPC. The edge function calls this AFTER a successful
--    dispatch so a failed push/email is retried on the next sweep instead
--    of being silently swallowed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_hidden_shop_nudged(p_provider_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.hidden_shop_nudges
  SET last_nudged_at = now(),
      nudge_count    = nudge_count + 1
  WHERE provider_id = p_provider_id;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_hidden_shop_nudged(uuid)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mark_hidden_shop_nudged(uuid)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 5. Hourly schedule via pg_cron. (The 24h threshold makes an hourly tick
--    more than precise enough, and it self-heals missed runs.)
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- cron.unschedule is idempotent-safe: a duplicate schedule would stack
-- duplicate sweeps, so always replace the existing job.
SELECT cron.unschedule('stylelink-hidden-shop-nudge')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'stylelink-hidden-shop-nudge'
);

SELECT cron.schedule(
  'stylelink-hidden-shop-nudge',
  '7 * * * *', -- 07 minutes past every hour (avoids top-of-hour thundering herd)
  $$SELECT public.nudge_hidden_shops();$$
);

-- ---------------------------------------------------------------------------
-- Verify.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  candidates integer;
  jobs       integer;
BEGIN
  SELECT COUNT(*) INTO candidates FROM public.hidden_shop_nudges;
  SELECT COUNT(*) INTO jobs FROM cron.job
    WHERE jobname = 'stylelink-hidden-shop-nudge';

  RAISE NOTICE '✓ hidden_shop_nudges table ready (% candidate(s) tracked)', candidates;
  IF jobs > 0 THEN
    RAISE NOTICE '✓ pg_cron job stylelink-hidden-shop-nudge scheduled hourly';
  ELSE
    RAISE WARNING '✗ pg_cron job NOT scheduled — is pg_cron enabled?';
  END IF;
END $$;
