-- =============================================================================
-- Webhook trigger: send FCM push notifications on booking status changes.
--
-- This creates a Supabase webhook that fires on INSERT and UPDATE to the
-- `public.bookings` table. It sends the changed row to the
-- `send-booking-notification` Edge Function, which resolves FCM tokens
-- and dispatches push notifications.
--
-- Prerequisites:
--   1. The Edge Function is deployed:
--        supabase functions deploy send-booking-notification
--   2. Firebase secrets are set:
--        supabase secrets set FIREBASE_PROJECT_ID=... \
--          FIREBASE_CLIENT_EMAIL=... FIREBASE_PRIVATE_KEY=...
--   3. The `fcm_token` column exists on `profiles`:
--        Run supabase/add_fcm_token_column.sql first.
--
-- Run this in the Supabase SQL Editor.
-- =============================================================================

-- 1. Create the webhook (fires on INSERT and UPDATE to bookings).
--    Uses the Supabase Management API webhook endpoint.
--    The webhook body includes the full record payload.

-- NOTE: Supabase webhooks are configured via the Dashboard or the
-- Management API, not via SQL. Use one of these methods:

-- ── Method A: Supabase Dashboard ─────────────────────────────────────────────
-- Go to Database → Webhooks → Create a new webhook:
--   Name:          booking-status-notifications
--   Table:         bookings
--   Events:        INSERT, UPDATE
--   Type:          HTTP Request
--   Method:        POST
--   URL:           https://<PROJECT_REF>.supabase.co/functions/v1/send-booking-notification
--   Timeout:       5000 ms
--   Headers:       Authorization: Bearer <ANON_KEY>
--                  Content-Type: application/json
--
-- ── Method B: Supabase CLI (supabase/config.toml) ────────────────────────────
-- Add to supabase/config.toml:
--
-- [db.webhooks]
-- enabled = true
--
-- Then create a webhook migration in supabase/migrations/.

-- ── Method C: Direct SQL (Supabase internal pg_net) ─────────────────────────
-- This uses the pg_net extension to make HTTP requests from PL/pgSQL.
-- Note: This requires the pg_net extension to be enabled.

-- Enable pg_net if not already enabled.
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Create the trigger function that calls the Edge Function.
CREATE OR REPLACE FUNCTION public.notify_booking_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  endpoint_url text;
  payload jsonb;
BEGIN
  -- Only fire on status-relevant events.
  -- Skip if status hasn't changed (for UPDATE).
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Skip initial 'pending' status (client just created the booking).
  IF NEW.status = 'pending' THEN
    RETURN NEW;
  END IF;

  -- Build the webhook payload matching Supabase's webhook format.
  endpoint_url := current_setting('app.settings.edge_function_url', true);

  -- Fallback: construct URL from Supabase project settings.
  IF endpoint_url IS NULL OR endpoint_url = '' THEN
    -- This will be replaced at deployment time with the actual project URL.
    RAISE NOTICE 'Edge function URL not configured. Set app.settings.edge_function_url.';
    RETURN NEW;
  END IF;

  payload := jsonb_build_object(
    'type', TG_OP,
    'table', TG_TABLE_NAME,
    'schema', TG_TABLE_SCHEMA,
    'record', to_jsonb(NEW),
    'old_record', CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END
  );

  -- Call the Edge Function asynchronously via pg_net.
  PERFORM net.http_post(
    url     := endpoint_url,
    body    := payload::text,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.anon_key', true)
    )
  );

  RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists.
DROP TRIGGER IF EXISTS on_booking_status_change ON public.bookings;

-- Create the trigger for INSERT and UPDATE.
CREATE TRIGGER on_booking_status_change
  AFTER INSERT OR UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE PROCEDURE public.notify_booking_status_change();

-- ── Configuration helper ─────────────────────────────────────────────────────
-- Run these once to set the Edge Function URL and anon key:
--
-- ALTER DATABASE postgres SET "app.settings.edge_function_url"
--   TO 'https://<PROJECT_REF>.supabase.co/functions/v1/send-booking-notification';
--
-- ALTER DATABASE postgres SET "app.settings.anon_key"
--   TO '<YOUR_ANON_KEY>';
