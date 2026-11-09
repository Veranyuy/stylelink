# StyleLink launch readiness

Last updated: 9 November 2026

This document tracks the work needed before inviting real clients and
providers. Code and repository changes are complete for items 1–9 where the
work can be done without production credentials or legal counsel. The
remaining actions require the project owner (deployment, accounts, content,
and legal review).

## Status

| # | Item | Status |
|---|---|---|
| 1 | Profile and booking data access | **Code + migration complete**; apply migration |
| 2 | Server-side booking rules | **Code + migration complete**; apply migration |
| 3 | Real, verifiable account deletion | **Code + Edge Function complete**; deploy function |
| 4 | One controlled database path | **Complete**: `supabase/migrations/20261109000000_launch_readiness.sql` + verification script |
| 5 | Live integration confirmation | **Runbook below**; requires production accounts/devices |
| 6 | Support contacts | **Placeholder phone/live chat removed**; confirm the email is monitored |
| 7 | Legal/privacy claims | **Copy corrected**; professional Cameroon review still required |
| 8 | Release build configuration | **Complete**: CI now fails without real Firebase config |
| 9 | App-flow tests | **Added** for validation, deletion, and lifecycle rules; live E2E still required |
| 10 | Launch operations | **Owner actions below**; provider seeding and support process are not code |

## 1. Apply the database migration

```bash
cd stylelink
supabase link --project-ref mzmumrggvwzwrootgcie
supabase db push
```

Then run `supabase/verify_launch_readiness.sql` in the SQL Editor. It must
print `StyleLink launch readiness: PASS`.

Recommended: apply to a Supabase development branch or staging project first.
Take a backup before running against production. Do not run the legacy
`fix_*.sql` / `NUCLEAR_*.sql` files afterward; the launch migration supersedes
them.

## 2. Deploy the account-deletion function

```bash
supabase functions deploy delete-account
```

No extra secret is needed: Supabase injects `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY`. The function verifies the caller's JWT, removes
the caller's stored images, deletes the auth user, and returns
`{ "deleted": true }` only after success. The app signs out only on that
response.

Also deploy the existing notification functions and set their secrets:

```bash
supabase functions deploy send-booking-notification
supabase functions deploy send-hidden-shop-nudge
```

See `supabase/NOTIFICATION_SETUP.md` for the Firebase service-account values.
Add `RESEND_API_KEY` and `NUDGE_FROM_EMAIL` only if the email fallback is
wanted.

## 3. Configure Auth redirect URLs

Supabase Dashboard → Authentication → URL Configuration:

- Site URL: `https://stylelink-505716.web.app`
- Redirect URLs:
  - `https://stylelink-505716.web.app/**`
  - `http://localhost:3000/**` (local web)
  - `stylelink://open/login-callback` (Android/iOS app)
- Enable the Google provider. For iOS, verify the Google client ID/secret and
  the `GoogleService-Info.plist` are from `stylelink-505716`.

The app's deep-link registration is:

- Android: `stylelink://open/...`
- iOS: URL scheme `stylelink`

A mismatch here produces a successful provider login that never returns to the
app. Test both platforms explicitly.

## 4. Build configuration

- CI release jobs now **fail** unless
  `GOOGLE_SERVICES_JSON_BASE64` and `GOOGLE_SERVICE_INFO_PLIST_BASE64` are set
  and contain the `stylelink-505716` project. Dummy configs are no longer
  generated.
- Set `SENTRY_DSN` as a build-time `--dart-define` (or CI secret) for crash
  reporting. Without it the app logs `Sentry disabled` and production errors
  are not reported.
- Confirm `android/app/google-services.json` and
  `ios/Runner/GoogleService-Info.plist` are the production files. The macOS,
  Windows, and Linux Firebase options in `firebase_options.dart` are still
  placeholders; those platforms are not launch targets.

## 5. End-to-end acceptance test

Use two real accounts and two devices/browsers. Do not launch until every step
passes.

### Client flow

1. Sign up with email; confirm the email; sign in.
2. Sign in with Google on web and on one native platform; confirm the app
   returns from the provider and lands on the correct shell.
3. Forgot password: receive the email, set a new password, sign in.
4. Browse providers in each launch city; open a shop with portfolio photos.
5. Book a service; confirm the price shown matches the sum of active services.
6. Attempt to book the same provider/time from a second account; the second
   attempt must be rejected by the server.
7. Provider accepts; client sees the booking confirmed and a verification PIN.
8. Provider marks arrival; client sees the arrival state.
9. Client shares the PIN; provider starts the session. Test a wrong PIN five
   times: verification must lock for 15 minutes.
10. Provider completes; client receives the review prompt and submits a review.
11. Client reschedules a pending/confirmed booking; provider accepts/declines.
12. Client cancels before the session; confirm the provider sees the
    cancellation and that cancellation after `arrived` is rejected.
13. Send a message from both sides; confirm realtime delivery.
14. Upload an avatar, cover, and portfolio image; confirm they render after a
    reload.
15. Delete the client account. Confirm sign-in no longer works and the
    profile, bookings, messages, review, avatar, and portfolio objects are
    gone.

### Provider flow

1. Sign up choosing “Service Provider”; complete the four-step wizard.
2. Confirm the shop stays hidden until at least one active service exists.
3. Confirm a provider cannot self-verify (`is_verified` is not client-writable)
   or change another provider's services/bookings.
4. Accept, reject, cancel, mark arrived, verify PIN, and complete bookings from
   the dashboard/calendar.
5. Upload and delete portfolio images; toggle availability.
6. Delete the provider account; confirm bookings, services, cover, avatar,
   portfolio, and provider row are removed, and that the client's booking
   history no longer references the deleted shop.

### Push and notifications

1. Grant notification permission on a real device (the web test session used
   for the initial audit had permission blocked).
2. Confirm `profiles.fcm_token` is populated for the device user.
3. Trigger each status change and confirm the correct party receives a push.
4. Reinstall/clear the token and confirm a stale token is cleared and the next
   launch registers a new one.

### Negative authorization checks

Use a second account and the REST API/PostgREST with its access token, not the
app UI:

- `select * from profiles` must return only the caller's row.
- `select email, phone_number, fcm_token from public_profiles` must fail.
- `select * from booking_pins` must fail.
- `insert/update/delete` on `bookings` must fail; RPC calls must enforce ownership.
- A provider must not be able to read another provider's bookings.
- A client must not be able to read another client's messages or bookings.
- A review insert for an incomplete booking or another user's booking must fail.

## 6. Support operations

The in-app phone number and “Live chat coming soon” option were removed because
they were placeholders. The remaining support address is
`support@stylelink.app` (also used in the privacy policy and terms).

**Owner action:** confirm this mailbox is monitored, with a named owner and a
response target. If it is not, replace it in
`lib/utils/legal_text.dart`, `privacy.html`, `terms.html`, and the support
screen before launch. Publish a real escalation path for booking disputes,
safety issues, and account deletion problems.

## 7. Legal review

The policies now describe the actual data flows and no longer claim
end-to-end encryption. They cover account data, bookings, messages, location,
push tokens, Firebase Analytics, optional Sentry, Supabase, Resend, retention,
deletion, and user rights.

**Owner action:** have Cameroon-qualified counsel review both documents, the
marketplace/intermediary position, provider obligations, consumer cancellation
rules, tax/payment language, and data-protection registration/notice
requirements. The text is an accurate product description, not legal advice.

## 8. Launch content and operations

- Seed at least 10–20 real, verified providers per launch city, each with an
  active service, working hours, a cover photo, and correct pricing.
- Define the provider verification process (ID, business details, portfolio
  review) and who performs it.
- Publish cancellation, no-show, refund, and dispute rules that match what the
  app actually enforces.
- Decide how clients reach a human when a provider cancels, arrives late, or
  behaves unsafely.
- Seed the city/category lists consistently (the app currently offers Douala,
  Yaoundé, Limbe, Bafoussam, Kribi, Buea, and Bamenda).
- Run the acceptance test in section 5 on production-like data before opening
  registration.

## 9. What changed in this pass

- `supabase/migrations/20261109000000_launch_readiness.sql` — authoritative,
  idempotent schema/security/booking migration.
- `supabase/verify_launch_readiness.sql` — fail-fast post-deploy checks.
- `supabase/functions/delete-account/index.ts` — trusted deletion endpoint.
- `lib/services/account_deletion_service.dart` — verifies server confirmation
  before signing out.
- `lib/utils/validators.dart`, `lib/utils/legal_text.dart` — tested validation
  and accurate legal copy.
- `lib/services/supabase_service.dart` — RPC booking calls, public-profile
  reads, review author hydration, consistent OAuth redirect.
- `lib/controllers/service_tracker_controller.dart` — RPC transitions and
  server-side PIN verification.
- `lib/views/client/widgets/active_booking_tracker_card.dart` — PIN via RPC,
  working chat button.
- `.github/workflows/ci.yml` — release builds require real Firebase config.
- `privacy.html`, `terms.html` — corrected data and payment claims.
- `test/utils/validators_test.dart`, `test/services/account_deletion_test.dart`,
  `test/models/booking_lifecycle_test.dart` — focused flow tests.
