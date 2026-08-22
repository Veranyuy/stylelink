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
- **In-App Account Deletion** — GDPR/App Store compliant account removal
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
│   ├── supabase_service.dart           # All Supabase API calls
│   └── notification_service.dart       # FCM + local notifications
├── utils/
│   └── formatters.dart                 # Currency, date, phone formatting
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
├── schema.sql                           # Full database schema
├── auth_trigger.sql                     # Profile auto-creation trigger
├── set_user_role.sql                    # Role assignment RPC
├── upgrade_to_provider.sql              # Client → Provider upgrade RPC
└── fix_*.sql                            # Migration & fix scripts
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
git clone https://github.com/YOUR_USERNAME/stylelink.git
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
Run the SQL files in `supabase/` through the Supabase SQL Editor in order:
1. `schema.sql` — creates all tables, RLS policies, and indexes
2. `auth_trigger.sql` — profile auto-creation on signup
3. `set_user_role.sql` — role assignment RPC
4. `upgrade_to_provider.sql` — client-to-provider upgrade RPC
5. Any `fix_*.sql` files as needed

---

## Deployment

### Firebase Hosting
```bash
flutter build web --release --base-href=/
firebase deploy --only hosting
```

### Mobile (Android / iOS)
```bash
# Configure Firebase for mobile
flutterfire configure

# Build
flutter build apk    # Android
flutter build ios    # iOS
```

---

## Architecture Notes

### Booking State Machine
Bookings progress through a strict state machine enforced both client-side and via database constraints:

```
confirmed → arrived → in_progress → completed
```

- **confirmed** — Provider accepted; client sees tracking card with PIN
- **arrived** — Provider logged GPS arrival; client gets arrival notification
- **in_progress** — PIN verified; session timer starts
- **completed** — Service finished; review prompt appears for client

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
| `bookings` | Client bookings with status, timestamps, GPS, and PIN |
| `reviews` | Client reviews with star ratings and comments |
| `favorites` | Saved stylists per client |
| `messages` | Chat messages between clients and providers |

---

## Localization

All user-facing strings use `context.t('key')` from the `LanguageProvider`. Toggle between English and French from the profile settings screen. The default language is English.

---

## License

Proprietary — All rights reserved.

---

Built with ❤️ for Cameroon's beauty community.
