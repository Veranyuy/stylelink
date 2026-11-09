# Hidden-Shop Nudge Setup Guide

Providers whose shop has **0 active services** are hidden from clients (see
`add_hidden_shop_visibility_gate.sql`). This guide wires up the scheduled
nudge that re-engages them: a **push notification** when the provider's device
token is known, otherwise an **email** via [Resend](https://resend.com).

```
pg_cron (hourly, '7 * * * *')
    ↓
nudge_hidden_shops()  — shops hidden > 24h, throttled to 1 nudge / 3 days
    ↓ (pg_net POST with the anon key)
send-hidden-shop-nudge Edge Function
    ↓
FCM push (stylelink_provider_alerts)  →  or  →  Resend email fallback
    ↓ (on success)
mark_hidden_shop_nudged() RPC — stamps last_nudged_at
```

## Prerequisites

1. `add_hidden_shop_visibility_gate.sql` applied (provides
   `services.is_active` + the hidden-shop rule)
2. `pg_cron` enabled — Dashboard → Database → Extensions → `pg_cron`
3. The booking-notification secrets already set (same Firebase service
   account is reused): `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`,
   `FIREBASE_PRIVATE_KEY`

## Step 1: Email fallback secret (optional but recommended)

```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxx
supabase secrets set NUDGE_FROM_EMAIL="StyleLink <noreply@yourdomain.com>"
```

Without `RESEND_API_KEY`, providers without an FCM token are simply retried
on a later sweep — nothing breaks.

## Step 2: Deploy the Edge Function

```bash
cd stylelink
supabase functions deploy send-hidden-shop-nudge
```

## Step 3: Run the SQL sweep

Paste `supabase/add_hidden_shop_nudge.sql` into the SQL editor and run it. It
creates `hidden_shop_nudges` (service-role only), the candidate-sync +
dispatch functions, the `mark_hidden_shop_nudged` RPC, and the hourly
`pg_cron` job.

## Step 4: Point the sweep at the Edge Function

If step 4 of `NOTIFICATION_SETUP.md` was done, **nothing to do** — the sweep
derives the nudge URL from `app.settings.edge_function_url`. Otherwise:

```sql
ALTER DATABASE postgres SET "app.settings.edge_function_url"
  TO 'https://<PROJECT_REF>.supabase.co/functions/v1/send-booking-notification';

ALTER DATABASE postgres SET "app.settings.anon_key"
  TO '<YOUR_ANON_KEY>';
```

(Optional explicit override: `app.settings.nudge_function_url` → the
`send-hidden-shop-nudge` URL.)

## Step 5: Verify

```sql
-- Current hidden shops being tracked (state syncs every hourly tick):
SELECT * FROM public.hidden_shop_nudges;

-- Dry-run the sweep manually (dispatches immediately for due shops):
SELECT public.nudge_hidden_shops();

-- Force-qualify a shop for testing (drops its 24h wait):
UPDATE public.hidden_shop_nudges
SET first_seen_hidden_at = now() - interval '2 days'
WHERE provider_id = '<PROVIDER_ID>';
```

Then check the function logs:

```bash
supabase functions logs send-hidden-shop-nudge
```

## Throttling summary

| Condition | Action |
|---|---|
| Hidden < 24 h | No nudge |
| Hidden > 24 h, never nudged | Push (or email fallback) |
| Nudged, still hidden | Repeat every 3 days |
| Shop gains an active service | Candidate row deleted; nudging stops |
| Push fails with a stale token | Token cleared; email sent in the same run |
| No token and no email | Retried next sweep (no state recorded) |
