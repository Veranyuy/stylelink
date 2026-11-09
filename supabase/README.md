# Supabase database

## Authoritative path

`migrations/20261109000000_launch_readiness.sql` is the single ordered schema
path for StyleLink. It is idempotent: it creates a fresh database and repairs
the existing one (missing columns/tables, old permissive policies, legacy PIN
column).

```bash
# From the stylelink project root
supabase link --project-ref mzmumrggvwzwrootgcie
supabase db push
```

Then run [`verify_launch_readiness.sql`](./verify_launch_readiness.sql) in the
Supabase SQL Editor. It raises an exception listing every failed check. Do not
invite users until it prints:

```
StyleLink launch readiness: PASS
```

For production, apply the migration to a Supabase development branch or a
staging project first, run the verification script and the acceptance tests in
`docs/LAUNCH_READINESS.md`, then apply to production. Take a database backup
before the first production run.

## What the migration changes

- `profiles` is owner-only. Other users read `public.public_profiles`, which
  exposes only display fields (no email, phone, or FCM token).
- Columns that clients may not write (`role`, `rating`, `review_count`,
  `is_verified`, `email`) are protected with column-level grants.
- `bookings` has no client INSERT/UPDATE/DELETE grants. Every mutation goes
  through validated SECURITY DEFINER RPCs:
  `create_booking`, `provider_respond_booking`, `provider_mark_arrived`,
  `provider_verify_pin`, `provider_complete_booking`,
  `provider_update_booking_status`, `provider_cancel_booking`,
  `client_cancel_booking`, `client_reschedule_booking`,
  `provider_respond_reschedule`, `provider_counter_booking`.
- `create_booking` computes the price from active services, checks that every
  service belongs to the provider, serializes slot checks per provider, and
  generates the 4-digit PIN.
- PINs live in `booking_pins` with no client grants. The client reads its own
  through `get_my_booking_pin`; providers verify through `provider_verify_pin`
  (five failed attempts lock verification for 15 minutes).
- Reviews require the reviewer's own completed booking and the matching
  provider. Provider rating/review counts are maintained by a trigger.
- Storage buckets and owner-only write policies are created/updated.
- Realtime publication and analytics functions are ensured.

## Edge Functions

Deploy after the migration:

```bash
supabase functions deploy send-booking-notification
supabase functions deploy send-hidden-shop-nudge
supabase functions deploy delete-account
```

Set the Firebase service-account secrets described in
[`NOTIFICATION_SETUP.md`](./NOTIFICATION_SETUP.md). `delete-account` uses the
automatically injected service-role key and needs no extra secret.

## Legacy files

Every other `*.sql` file in this directory is historical. Some were hotfixes
for the pre-migration database and contain permissive policies that are
deliberately removed by the launch migration. Do not run them on a fresh
database, and do not run them after the launch migration.
