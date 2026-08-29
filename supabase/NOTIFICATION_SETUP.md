# Booking Notification Setup Guide

This guide walks through deploying the FCM push notification system for booking status changes.

## Architecture

```
Booking status changes in Supabase DB
    ↓ (pg_net trigger)
send-booking-notification Edge Function
    ↓ (FCM HTTP v1 API)
Client devices / Provider devices receive push notifications
```

## Prerequisites

1. **Supabase project** with Edge Functions enabled
2. **Firebase project** with Cloud Messaging enabled
3. **FCM tokens** stored in `profiles.fcm_token` (run `add_fcm_token_column.sql` first)

## Step 1: Firebase Service Account

1. Go to [Firebase Console](https://console.firebase.google.com) → Project Settings → Service Accounts
2. Click "Generate new private key" → download the JSON file
3. Extract these values:
   - `project_id` → `FIREBASE_PROJECT_ID`
   - `client_email` → `FIREBASE_CLIENT_EMAIL`
   - `private_key` → `FIREBASE_PRIVATE_KEY`

## Step 2: Set Supabase Secrets

```bash
# Install Supabase CLI if not installed
npm install -g supabase

# Login to Supabase
supabase login

# Link to your project
supabase link --project-ref <YOUR_PROJECT_REF>

# Set Firebase secrets
supabase secrets set \
  FIREBASE_PROJECT_ID=your-project-id \
  FIREBASE_CLIENT_EMAIL=your-service-account@project.iam.gserviceaccount.com \
  FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...your...key...\n-----END PRIVATE KEY-----"
```

## Step 3: Deploy the Edge Function

```bash
# From the project root
cd stylelink

# Deploy the function
supabase functions deploy send-booking-notification
```

## Step 4: Set Up the Database Trigger

Run `booking_notification_webhook.sql` in the Supabase SQL Editor:

1. Go to Supabase Dashboard → SQL Editor
2. Paste the contents of `supabase/booking_notification_webhook.sql`
3. Click "Run"

Then configure the Edge Function URL:

```sql
-- Replace <PROJECT_REF> with your Supabase project reference
ALTER DATABASE postgres SET "app.settings.edge_function_url"
  TO 'https://<PROJECT_REF>.supabase.co/functions/v1/send-booking-notification';

-- Replace <ANON_KEY> with your Supabase anon key
ALTER DATABASE postgres SET "app.settings.anon_key"
  TO 'your-anon-key-here';
```

> **Note:** If `pg_net` is not available on your plan, use the
> Supabase Dashboard → Database → Webhooks instead (see Method A in the SQL file).

## Step 5: Test

1. Sign in as a **client** on one device
2. Sign in as a **provider** on another device
3. As the client, book a service with the provider
4. As the provider, accept the booking → client should receive a push notification
5. Complete the service → both should receive notifications

## Notification Map

| Status Change | Notifies | Channel |
|---|---|---|
| `pending → confirmed` | Client | `stylelink_booking_updates` |
| `confirmed → arrived` | Client | `stylelink_booking_updates` |
| `arrived → in_progress` | Client | `stylelink_booking_updates` |
| `in_progress → completed` | Client + Provider | Both channels |
| `* → cancelled` | Client + Provider | Both channels |
| `* → rejected` | Client | `stylelink_booking_updates` |
| `INSERT (new booking)` | Provider | `stylelink_provider_alerts` |

## Troubleshooting

### Notifications not received?
1. Check `profiles.fcm_token` is populated: `SELECT id, fcm_token FROM profiles WHERE fcm_token IS NOT NULL;`
2. Check Edge Function logs: `supabase functions logs send-booking-notification`
3. Verify Firebase project ID matches the one used in the app
4. Ensure the FCM token is for the correct Firebase project

### "UNREGISTERED" errors?
The device token is stale. The function auto-clears invalid tokens from the database. The app's `NotificationService` will regenerate a fresh token on next launch.

### pg_net not available?
Use the Supabase Dashboard Webhook UI instead:
- Go to Database → Webhooks → Create webhook
- Set table: `bookings`, events: `INSERT, UPDATE`
- Set type: HTTP Request, URL: your Edge Function URL
- The dashboard handles the HTTP call internally
