// =============================================================================
// send-booking-notification
//
// Supabase Edge Function triggered by a database webhook on `public.bookings`.
// When a booking's status changes, sends FCM push notifications to the
// affected client and/or provider.
//
// Environment variables (set via `supabase secrets set`):
//   FIREBASE_PROJECT_ID  — Firebase project ID
//   FIREBASE_CLIENT_EMAIL — Firebase service account email
//   FIREBASE_PRIVATE_KEY  — Firebase service account private key (escaped \n)
//
// The Supabase service-role key is available via Deno.env.get('SUPABASE_URL')
// and the request's Authorization header (service_role key).
// =============================================================================

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Firebase Admin SDK (lightweight — no full SDK, just the HTTP API)
// ---------------------------------------------------------------------------

interface FirebaseToken {
  access_token: string;
  expires_in: number;
}

let cachedToken: { token: string; expiresAt: number } | null = null;

async function getFirebaseAccessToken(): Promise<string> {
  if (cachedToken && Date.now() < cachedToken.expiresAt) {
    return cachedToken.token;
  }

  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")!.replace(
    /\\n/g,
    "\n"
  );

  // Create a JWT signed with the service account's private key.
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encodedHeader = btoa(JSON.stringify(header)).replace(/=/g, "");
  const encodedPayload = btoa(JSON.stringify(payload)).replace(/=/g, "");
  const signatureInput = `${encodedHeader}.${encodedPayload}`;

  // Sign with RSASSA-PKCS1-v1_5 using the Web Crypto API.
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signatureInput)
  );
  const encodedSignature = btoa(
    String.fromCharCode(...new Uint8Array(signature))
  )
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");

  const jwt = `${signatureInput}.${encodedSignature}`;

  // Exchange JWT for an access token.
  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const data: FirebaseToken = await resp.json();

  cachedToken = {
    token: data.access_token,
    expiresAt: Date.now() + (data.expires_in - 60) * 1000,
  };
  return cachedToken.token;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

// ---------------------------------------------------------------------------
// FCM send helper
// ---------------------------------------------------------------------------

interface FcmMessage {
  message: {
    token: string;
    notification?: { title: string; body: string };
    data?: Record<string, string>;
    android?: {
      priority: "high";
      notification?: { channel_id: string; sound: "default" };
    };
    apns?: {
      payload: {
        aps: { alert: { title: string; body: string }; sound: "default" };
      };
    };
  };
}

async function sendFcmNotification(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
  channelId: string
): Promise<boolean> {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  const accessToken = await getFirebaseAccessToken();

  const message: FcmMessage = {
    message: {
      token,
      notification: { title, body },
      data,
      android: {
        priority: "high",
        notification: { channel_id: channelId, sound: "default" },
      },
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: "default",
          },
        },
      },
    },
  };

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
    }
  );

  if (!resp.ok) {
    const err = await resp.text();
    console.error(`FCM send failed (${resp.status}): ${err}`);
    // Token may be invalid — clear it from the database.
    if (resp.status === 404 || err.includes("UNREGISTERED")) {
      return false; // signal to caller to delete the token
    }
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Notification content per status transition (bilingual)
// ---------------------------------------------------------------------------

interface NotificationContent {
  clientTitle: string;
  clientBody: string;
  providerTitle: string;
  providerBody: string;
}

function getNotificationContent(
  status: string,
  providerName: string,
  clientName: string
): NotificationContent {
  switch (status) {
    case "confirmed":
      return {
        clientTitle: "Booking Confirmed! ✅",
        clientBody: `${providerName} accepted your request.`,
        providerTitle: "New Booking 📅",
        providerBody: `${clientName} booked a service with you.`,
      };
    case "arrived":
      return {
        clientTitle: "Stylist Arrived 📍",
        clientBody: `${providerName} has logged their arrival.`,
        providerTitle: "Arrival Logged 📍",
        providerBody: "Your arrival has been recorded.",
      };
    case "in_progress":
      return {
        clientTitle: "Session Started 💈",
        clientBody: "Your PIN was verified. Enjoy your service!",
        providerTitle: "Session Started 💈",
        providerBody: "The session has begun.",
      };
    case "completed":
      return {
        clientTitle: "Service Complete! ⭐",
        clientBody: "Tap to rate your experience.",
        providerTitle: "Service Complete! ✅",
        providerBody: `Session with ${clientName} is finished.`,
      };
    case "cancelled":
      return {
        clientTitle: "Booking Cancelled",
        clientBody: "Your appointment has been cancelled.",
        providerTitle: "Booking Cancelled",
        providerBody: `${clientName} cancelled their appointment.`,
      };
    case "rejected":
      return {
        clientTitle: "Booking Declined",
        clientBody: `${providerName} could not take this booking.`,
        providerTitle: "Booking Declined",
        providerBody: "You declined a booking request.",
      };
    default:
      return {
        clientTitle: "Booking Updated",
        clientBody: `Status: ${status}`,
        providerTitle: "Booking Updated",
        providerBody: `Status: ${status}`,
      };
  }
}

// ---------------------------------------------------------------------------
// Webhook payload types
// ---------------------------------------------------------------------------

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  old_record?: Record<string, unknown>;
  record: Record<string, unknown>;
}

interface BookingRow {
  id: string;
  client_id: string;
  provider_id: string;
  status: string;
  scheduled_at: string;
  total_price_fcfa: number;
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

serve(async (req: Request) => {
  // Only accept POST requests.
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const payload: WebhookPayload = await req.json();

    // Only process bookings table updates.
    if (payload.table !== "bookings" || payload.schema !== "public") {
      return new Response("OK", { status: 200 });
    }

    // We only care about INSERT (new booking) and UPDATE (status change).
    if (payload.type !== "INSERT" && payload.type !== "UPDATE") {
      return new Response("OK", { status: 200 });
    }

    const booking = payload.record as BookingRow;
    const oldBooking = payload.old_record as BookingRow | undefined;

    // For UPDATE, only notify if the status actually changed.
    if (
      payload.type === "UPDATE" &&
      oldBooking &&
      oldBooking.status === booking.status
    ) {
      return new Response("OK", { status: 200 });
    }

    // Don't notify for 'pending' status (the initial state).
    if (booking.status === "pending") {
      return new Response("OK", { status: 200 });
    }

    // ── Resolve Supabase client ────────────────────────────────────────
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ── Look up client and provider info ───────────────────────────────
    const [clientResult, providerResult] = await Promise.all([
      supabase
        .from("profiles")
        .select("full_name, fcm_token, language_preference")
        .eq("id", booking.client_id)
        .single(),
      supabase
        .from("providers")
        .select("user_id, business_name")
        .eq("id", booking.provider_id)
        .single(),
    ]);

    if (clientResult.error || providerResult.error) {
      console.error(
        "Failed to resolve users:",
        clientResult.error,
        providerResult.error
      );
      return new Response("OK", { status: 200 }); // don't block webhook
    }

    const clientName = clientResult.data.full_name || "Client";
    const clientFcmToken = clientResult.data.fcm_token;
    const providerName = providerResult.data.business_name || "Your stylist";
    const providerUserId = providerResult.data.user_id;

    // Look up provider's FCM token from their profile.
    let providerFcmToken: string | null = null;
    if (providerUserId) {
      const { data: providerProfile } = await supabase
        .from("profiles")
        .select("fcm_token")
        .eq("id", providerUserId)
        .single();
      providerFcmToken = providerProfile?.fcm_token;
    }

    // ── Get notification content ───────────────────────────────────────
    const content = getNotificationContent(
      booking.status,
      providerName,
      clientName
    );

    // ── Send notifications ─────────────────────────────────────────────
    const notifications: Promise<{ target: string; ok: boolean }>[] = [];

    // Notify the client (for all status changes except new booking).
    if (clientFcmToken && payload.type === "UPDATE") {
      notifications.push(
        sendFcmNotification(
          clientFcmToken,
          content.clientTitle,
          content.clientBody,
          {
            booking_id: booking.id,
            status: booking.status,
            type: "booking_update",
          },
          "stylelink_booking_updates"
        ).then((ok) => ({ target: "client", ok }))
      );
    }

    // Notify the provider (for new bookings and client-initiated cancellations).
    if (providerFcmToken) {
      const shouldNotifyProvider =
        payload.type === "INSERT" || // new booking
        booking.status === "cancelled" || // client cancelled
        booking.status === "completed"; // session done

      if (shouldNotifyProvider) {
        notifications.push(
          sendFcmNotification(
            providerFcmToken,
            content.providerTitle,
            content.providerBody,
            {
              booking_id: booking.id,
              status: booking.status,
              type: "booking_update",
            },
            "stylelink_provider_alerts"
          ).then((ok) => ({ target: "provider", ok }))
        );
      }
    }

    const results = await Promise.all(notifications);

    // ── Clean up invalid tokens ────────────────────────────────────────
    for (const result of results) {
      if (!result.ok) {
        if (result.target === "client" && clientFcmToken) {
          await supabase
            .from("profiles")
            .update({ fcm_token: null })
            .eq("id", booking.client_id);
        }
        if (result.target === "provider" && providerFcmToken) {
          await supabase
            .from("profiles")
            .update({ fcm_token: null })
            .eq("id", providerUserId);
        }
      }
    }

    console.log(
      `Sent notifications for booking ${booking.id} (${booking.status}): ` +
        `${results.map((r) => `${r.target}=${r.ok ? "ok" : "failed"}`).join(", ")}`
    );

    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error("send-booking-notification error:", err);
    // Always return 200 to prevent webhook retries.
    return new Response("OK", { status: 200 });
  }
});
