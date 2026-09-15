-- =============================================================================
-- StyleLink — Reschedule proposals + provider accept/decline
-- Run this in the Supabase SQL editor. Idempotent; safe to re-run.
--
-- Model: a client reschedule is a PROPOSAL. The original `scheduled_at`,
-- `status` and price stay untouched until the provider accepts. The proposed
-- slot lives in `proposed_scheduled_at` with `reschedule_status`
-- ('pending' | 'accepted' | 'rejected'). NULL columns = ordinary booking.
--
-- 1. Schema: `proposed_scheduled_at` timestamptz + `reschedule_status` text
--    (replaces the earlier `reschedule_from_*` columns if those were applied).
-- 2. Sanity trigger: never lose the original slot (scheduled_at must not
--    change while a proposal is pending), and clean the proposal on terminal
--    transitions.
-- 3. RLS: clients may create/cancel their own proposal (see notes); providers
--    already can respond via "providers can update their schedule".
-- 4. Webhook trigger: fire the `send-booking-notification` Edge Function on
--    proposal creation AND on acceptance/decline so both sides get pushes.
-- =============================================================================

-- ── 1. Schema ────────────────────────────────────────────────────────────────
alter table public.bookings add column if not exists proposed_scheduled_at timestamptz;
alter table public.bookings add column if not exists reschedule_status text;

-- Repair stray defaults (e.g. the columns were added manually in the
-- dashboard with DEFAULT 'none' / 'pending'): no default is ever valid
-- here — a fresh booking must be (NULL, NULL), otherwise every plain
-- insert violates bookings_reschedule_pairing_check.
alter table public.bookings alter column proposed_scheduled_at drop default;
alter table public.bookings alter column reschedule_status drop default;

-- Constraint keeps reschedule_status consistent with proposed_scheduled_at:
--   (null, null)                          -> not a reschedule
--   (slot, 'pending')                     -> open proposal awaiting provider
--   (null, 'accepted' | 'rejected')       -> resolved; slot lives in scheduled_at
-- Repair: drop ANY check constraint on bookings that references
-- reschedule_status (covers hand-made variants with stricter definitions
-- or different names — e.g. one that rejects the legal (NULL, NULL) shape
-- of a fresh booking), then re-add the canonical constraint.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.bookings'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%reschedule_status%'
      AND conname <> 'bookings_reschedule_pairing_check'
  LOOP
    EXECUTE format('alter table public.bookings drop constraint %I', r.conname);
  END LOOP;
END $$;

alter table public.bookings drop constraint if exists bookings_reschedule_pairing_check;
alter table public.bookings add constraint bookings_reschedule_pairing_check check (
  (proposed_scheduled_at is null and reschedule_status is null)
  or
  (proposed_scheduled_at is not null and reschedule_status = 'pending')
  or
  (proposed_scheduled_at is null and reschedule_status in ('accepted', 'rejected'))
);

-- Replace the earlier (aborted) reschedule_from_* columns if they exist.
alter table public.bookings drop column if exists reschedule_from_at;
alter table public.bookings drop column if exists reschedule_from_status;

-- Drop the superseded tracking trigger from the earlier migration draft.
drop trigger if exists on_reschedule_tracking on public.bookings;
drop function if exists public.sync_reschedule_tracking();

-- ── 2. Sanity trigger ────────────────────────────────────────────────────────
-- Guarantees, regardless of which client writes the row:
--   * While a proposal is pending, the ORIGINAL slot cannot be overwritten.
--   * Any status change to a terminal state clears the proposal.
--   * Acceptance (reschedule_status -> 'accepted') is what MOVES the slot:
--     scheduled_at is set to proposed_scheduled_at, then the proposal is
--     cleared by the service layer in the same write (accepted writes
--     proposed_scheduled_at = null), so here we only guard pending rows.
CREATE OR REPLACE FUNCTION public.guard_reschedule_proposal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    -- Original slot is frozen while a proposal is pending.
    IF NEW.reschedule_status = 'pending'
       AND NEW.proposed_scheduled_at IS NOT NULL
       AND OLD.scheduled_at IS DISTINCT FROM NEW.scheduled_at THEN
      RAISE EXCEPTION 'Cannot move scheduled_at while a reschedule proposal is pending';
    END IF;

    -- Terminal transitions clear any open proposal.
    IF NEW.status IN ('completed', 'cancelled', 'rejected')
       AND (NEW.reschedule_status IS NOT NULL
            OR NEW.proposed_scheduled_at IS NOT NULL) THEN
      NEW.reschedule_status := NULL;
      NEW.proposed_scheduled_at := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_guard_reschedule_proposal ON public.bookings;
CREATE TRIGGER on_guard_reschedule_proposal
  BEFORE UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE PROCEDURE public.guard_reschedule_proposal();

-- ── 3. RLS ───────────────────────────────────────────────────────────────────
-- Clients: propose a reschedule on their own upcoming bookings (any status
-- among pending/confirmed), or withdraw one by clearing the proposal —
-- but never move scheduled_at/status themselves (accept/decline is the
-- provider's call).
drop policy if exists "clients can reschedule their own bookings" on public.bookings;
create policy "clients can reschedule their own bookings"
  on public.bookings for update
  using (
    auth.uid() = client_id
    and status in ('pending', 'confirmed')
  )
  with check (
    auth.uid() = client_id
    and status in ('pending', 'confirmed')
    and (
      -- Creating/updating a proposal: keep row otherwise unchanged.
      (reschedule_status = 'pending' and proposed_scheduled_at is not null)
      or
      -- Withdrawing the proposal.
      (reschedule_status is null and proposed_scheduled_at is null)
    )
  );

-- Providers: "providers can update their schedule" (fix_bookings_rls.sql)
-- already permits them to update their own rows — that covers Accept
-- (scheduled_at := proposed, status := 'confirmed', clear proposal) and
-- Decline (keep row, mark reschedule_status = 'rejected', clear proposal).
-- Permissive policies OR-combine; a narrower one would only loosen RLS.

-- ── 4. Webhook trigger: reschedule-aware notifications ─────────────────────
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.notify_booking_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  endpoint_url text;
  payload jsonb;
  reschedule_event boolean;
BEGIN
  reschedule_event :=
    TG_OP = 'UPDATE'
    AND (
      -- Proposal created or answered.
      OLD.reschedule_status IS DISTINCT FROM NEW.reschedule_status
      -- Proposal slot edited (client withdrew + re-proposed).
      OR (NEW.reschedule_status = 'pending'
          AND OLD.proposed_scheduled_at IS DISTINCT FROM NEW.proposed_scheduled_at)
    );

  -- Only fire on status-relevant events.
  IF TG_OP = 'UPDATE'
     AND OLD.status = NEW.status
     AND NOT reschedule_event THEN
    RETURN NEW;
  END IF;

  -- Skip plain INSERT 'pending' (new booking fires via the webhook below
  -- only if you want it to; keep parity with previous behavior and fire),
  -- and flips back to 'pending' that are NOT reschedule events.
  IF TG_OP = 'UPDATE'
     AND NEW.status = 'pending'
     AND NEW.reschedule_status IS NULL
     AND NOT reschedule_event THEN
    RETURN NEW;
  END IF;

  -- Build the webhook payload matching Supabase's webhook format.
  endpoint_url := current_setting('app.settings.edge_function_url', true);

  IF endpoint_url IS NULL OR endpoint_url = '' THEN
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

DROP TRIGGER IF EXISTS on_booking_status_change ON public.bookings;

CREATE TRIGGER on_booking_status_change
  AFTER INSERT OR UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE PROCEDURE public.notify_booking_status_change();

-- Sanity checks:
--   * Client: UPDATE own confirmed booking SET proposed_scheduled_at = X,
--     reschedule_status = 'pending' -> succeeds; scheduled_at untouched;
--     webhook fires "Reschedule Request" to the provider.
--   * Provider accept: UPDATE ... SET scheduled_at = proposed, status =
--     'confirmed', reschedule_status = 'accepted', proposed_scheduled_at =
--     null -> guard passes (pending check is on OLD), webhook fires
--     "Reschedule Confirmed" to the client.
--   * Provider decline: UPDATE ... SET reschedule_status = 'rejected',
--     proposed_scheduled_at = null -> webhook fires "Reschedule Declined".
--   * Any attempt to move scheduled_at while a proposal is pending (by
--     either side) now raises an exception.
