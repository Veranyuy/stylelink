# StyleLink

Premium beauty & barber booking platform for Cameroon. Clients discover top-rated stylists, book services in real time, track arrivals with GPS, verify sessions with PIN codes, and leave reviews — all in English and French.

**Live:** https://stylelink-505716.web.app

---

## Features

### Client Experience
- **Discover Stylists** — browse top-rated providers by city (Douala, Yaoundé, Limbe, Bafoussam, Kribi) with cover photos, ratings, and portfolio galleries
- **Book Services** — select services, pick a date/time, add notes, and receive instant confirmation
- **Real-Time Tracking** — watch your provider's status live (confirmed → arrived → in progress → completed)
- **Verification PIN** — a 4-digit code displayed on-screen to confirm the provider's identity at arrival
- **Post-Service Reviews** — rate providers 1–5 stars with optional written feedback
- **Favorites** — save stylists for quick rebooking
- **Push Notifications** — FCM-powered alerts for booking status changes, new reviews, and more

### Provider Experience
- **Provider Dashboard** — earnings overview, booking stats, and quick actions
- **Calendar View** — month grid with dot indicators for booked days; tap a day to see its bookings
- **Booking Tracker** — advance bookings through stages (confirmed → arrived → in-progress → completed) with GPS arrival logging and PIN verification
- **Service Manager** — add, edit, or remove services with pricing and duration
- **Portfolio Gallery** — upload up to 7 work photos to showcase skills
- **Availability Toggle** — go online/offline with a single tap
- **Workspace Switcher** — seamlessly toggle between Client Mode and Provider Dashboard

### Platform
- **Bilingual** — full English/French localization with in-app language toggle
- **Dark Mode** — light, dark, and system-follow theme support
- **In-App Account Deletion** — server-confirmed removal of the account, related rows, and stored images
- **Forgot Password** — email-based password reset with deep-link redirect
- **OAuth** — Google Sign-In for one-tap authentication

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter 3.x (Dart) — web, iOS, Android |
| Backend | Supabase (PostgreSQL, Auth, Realtime, Storage, Edge Functions) |
| Hosting | Firebase Hosting |
| Push Notifications | Firebase Cloud Messaging + flutter_local_notifications |
| Maps / Navigation | Geolocator + url_launcher (Google Maps) |
| State Management | Provider (theme, language) + ChangeNotifier controllers |

---

## Project Structure

```
lib/
├── main.dart                          # App entry point, auth routing
├── firebase_options.dart              # Firebase project config (auto-generated)
├── controllers/
│   └── service_tracker_controller.dart  # Booking state machine & GPS
├── models/
│   ├── booking.dart
│   ├── message.dart
│   ├── profile.dart
│   ├── provider.dart
│   └── service.dart
├── providers/
│   ├── language_provider.dart          # EN/FR localization
│   └── theme_provider.dart             # Light/Dark/System themes
├── services/
│   ├── supabase_service.dart           # Supabase API/RPC calls
│   ├── account_deletion_service.dart   # Server-confirmed account deletion
│   └── notification_service.dart       # FCM + local notifications
├── utils/
│   ├── formatters.dart                 # Currency, date, phone formatting
│   ├── legal_text.dart                 # In-app terms and privacy copy
│   └── validators.dart                 # Sign-in and onboarding validation
├── views/
│   ├── auth/
│   │   └── auth_screen.dart            # Sign up / Sign in / Forgot password
│   ├── client/
│   │   ├── client_shell.dart           # Bottom nav + workspace switcher
│   │   ├── home_screen.dart            # Provider feed + search
│   │   ├── bookings_screen.dart        # Client booking list + cancel
│   │   ├── messages_screen.dart        # Chat / messaging
│   │   ├── provider_detail_screen.dart # Provider profile, portfolio, reviews, booking
│   │   ├── profile_screen.dart         # Client settings, favorites, theme, delete
│   │   └── widgets/
│   │       └── active_booking_tracker_card.dart
│   └── provider/
│       ├── provider_shell.dart          # Provider bottom nav
│       ├── dashboard_screen.dart        # Earnings + stats
│       ├── calendar_screen.dart         # Monthly calendar with bookings
│       ├── earnings_screen.dart         # Revenue breakdown
│       ├── service_manager_screen.dart  # CRUD services
│       ├── business_screen.dart         # Business info
│       └── profile_screen.dart          # Provider settings, portfolio, theme
├── widgets/
│   ├── booking_tracker_card.dart        # Provider-side booking state card
│   ├── custom_avatar.dart               # Smart avatar with initials fallback
│   └── review_modal.dart               # Post-service review bottom sheet
supabase/
├── migrations/
│   └── 20261109000000_launch_readiness.sql  # Authoritative schema + security
├── functions/
│   ├── delete-account/                  # Trusted account deletion
│   ├── send-booking-notification/       # FCM booking pushes
│   └── send-hidden-shop-nudge/          # Provider re-engagement
├── verify_launch_readiness.sql          # Fail-fast post-deploy checks
├── README.md                            # Database setup rules
└── schema.sql, fix_*.sql                 # Historical only — do not run
```

---

## Getting Started

### Prerequisites
- Flutter SDK ≥ 3.3.0
- Node.js (for local preview server)
- Supabase project (already configured)
- Firebase project (already configured for `stylelink-505716`)

### 1. Clone & Install
```bash
git clone <repository-url> stylelink
cd stylelink
flutter pub get
```

### 2. Configure Environment
The Supabase URL and anon key are in `lib/main.dart`. Firebase config is in `lib/firebase_options.dart`. Both are committed because the anon key is protected by Row-Level Security and the Firebase web config is public.

### 3. Run Locally
```bash
# Flutter web with hot reload
flutter run -d chrome --web-port=3000

# Or build & serve the release
flutter build web --release --base-href=/
node server.js
# → http://localhost:3000
```

### 4. Database Setup
Use the single authoritative migration. Do **not** run the legacy `fix_*.sql`
files or `schema.sql` on a new database.

```bash
supabase link --project-ref mzmumrggvwzwrootgcie
supabase db push
```

Then run `supabase/verify_launch_readiness.sql` in the SQL Editor. It must
print `StyleLink launch readiness: PASS`.

Details, including the security model and the Edge Function deploy steps, are
in [`supabase/README.md`](supabase/README.md). The full pre-launch checklist is
[`docs/LAUNCH_READINESS.md`](docs/LAUNCH_READINESS.md).

---

## Deployment

### Edge Functions
```bash
supabase functions deploy delete-account
supabase functions deploy send-booking-notification
supabase functions deploy send-hidden-shop-nudge
```

Set the Firebase service-account secrets before deploying the notification
functions (`supabase/NOTIFICATION_SETUP.md`). `delete-account` needs no extra
secret.

### Firebase Hosting
```bash
flutter build web --release --base-href=/
firebase deploy --only hosting
```

### Mobile (Android / iOS)
Release builds require the real Firebase project files. CI fails if
`GOOGLE_SERVICES_JSON_BASE64` or `GOOGLE_SERVICE_INFO_PLIST_BASE64` is missing,
or if the decoded file is not for `stylelink-505716`.

```bash
flutterfire configure
flutter build apk --release
flutter build ios --release
```

Set `SENTRY_DSN` as a `--dart-define` for crash reporting; without it Sentry
stays disabled.

---

## Architecture Notes

### Booking State Machine
All booking writes go through validated RPCs; clients and providers have no
direct INSERT/UPDATE/DELETE grant on `bookings`.

```
pending → confirmed → arrived → in_progress → completed
        ↘ rejected / cancelled
```

- **pending** — Client requested a slot; price and slot are computed server-side
- **confirmed** — Provider accepted; client sees tracking card with a PIN
- **arrived** — Provider logged GPS arrival; client gets arrival notification
- **in_progress** — Provider verified the client's PIN; session timer starts
- **completed** — Service finished; review prompt appears for client

The PIN lives in `booking_pins` (no client grants) and is verified by an RPC
with attempt throttling. Providers never receive it.

### Role System
- All new users default to `client` role
- Providers upgrade via the in-app "Become a Provider" flow
- Providers can switch between Client Mode and Provider Dashboard
- The `set_user_role` RPC is a security-definer function that bypasses RLS

### Real-Time Updates
Supabase Realtime channels power live booking status updates, message delivery, and provider availability changes without polling.

---

## Database Schema (Key Tables)

| Table | Purpose |
|---|---|
| `profiles` | User accounts (id, name, email, role, avatar, language) |
| `providers` | Provider details (business name, category, city, rating, portfolio) |
| `services` | Service offerings per provider (name, price, duration) |
| `bookings` | Client bookings with status, timestamps, GPS, and price |
| `booking_pins` | Private verification PINs (no client grants) |
| `reviews` | Client reviews with star ratings and comments |
| `favorites` | Saved stylists per client |
| `messages` | Chat messages between clients and providers |

---

## Localization

All user-facing strings use `context.t('key')` from the `LanguageProvider`. Toggle between English and French from the profile settings screen. The default language is English.

---

## Launch checklist

Before inviting real users, complete [`docs/LAUNCH_READINESS.md`](docs/LAUNCH_READINESS.md):
the database migration, Edge Function deploys, OAuth redirects, push/device
tests, support contact confirmation, legal review, and provider seeding.

---

## License

Proprietary — All rights reserved.

---

Built with ❤️ for Cameroon's beauty community.
