// =============================================================================
// send-hidden-shop-nudge
//
// Scheduled re-engagement nudge for providers whose shop is hidden (0 active
// services -> invisible to clients; see add_hidden_shop_visibility_gate.sql).
//
// Called hourly by the pg_cron job 'stylelink-hidden-shop-nudge' (see
// add_hidden_shop_nudge.sql) via pg_net with the anon key.
//
// For each due provider it sends:
//   1. FCM push notification to profiles.fcm_token (channel
//      stylelink_provider_alerts) when a device token is known, else
//   2. A transactional email via the Resend API when an email is known.
//
// After a successful dispatch it calls the mark_hidden_shop_nudged RPC so
// the sweep records last_nudged_at (failed sends are retried next sweep).
//
// Environment variables (supabase secrets set):
//   FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY
//     — same service account the booking notification function uses.
//   RESEND_API_KEY (optional) — enables the email fallback.
//   NUDGE_FROM_EMAIL (optional, default nudge@resend.dev) — From header.
// =============================================================================

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Firebase Admin (identical lightweight JWT flow as send-booking-notification)
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
// Delivery helpers
// ---------------------------------------------------------------------------

async function sendPush(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<boolean> {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  const accessToken = await getFirebaseAccessToken();

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: {
              channel_id: "stylelink_provider_alerts",
              sound: "default",
            },
          },
          apns: {
            payload: {
              aps: { alert: { title, body }, sound: "default" },
            },
          },
        },
      }),
    }
  );

  if (!resp.ok) {
    console.error(`FCM send failed (${resp.status}): ${await resp.text()}`);
    return false;
  }
  return true;
}

async function sendEmail(
  to: string,
  subject: string,
  html: string
): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.log("RESEND_API_KEY not set — skipping email fallback");
    return false;
  }

  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: Deno.env.get("NUDGE_FROM_EMAIL") ?? "StyleLink <onboarding@resend.dev>",
      to,
      subject,
      html,
    }),
  });

  if (!resp.ok) {
    console.error(`Resend send failed (${resp.status}): ${await resp.text()}`);
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Bilingual nudge copy (matches the app's EN/FR voice)
// ---------------------------------------------------------------------------

interface NudgeCopy {
  title: string;
  body: string;
  emailSubject: string;
  emailHtml: string;
}

function buildNudgeCopy(
  businessName: string,
  firstName: string,
  isFrench: boolean,
  hiddenSinceDays: number,
  repeat: boolean
): NudgeCopy {
  const name = firstName || "there";
  if (isFrench) {
    const body = repeat
      ? "Votre salon reste invisible — ajoutez une prestation pour être réservable."
      : "Votre salon est masqué ! Ajoutez au moins 1 prestation pour commencer à recevoir des réservations.";
    return {
      title: "Votre salon est masqué 🙈",
      body,
      emailSubject: `${businessName} est encore invisible sur StyleLink`,
      emailHtml: `
        <p>Bonjour ${name},</p>
        <p>Votre salon <strong>${businessName}</strong> n'a aucune prestation
        active depuis ${hiddenSinceDays} jour(s) : les clients ne peuvent pas
        le trouver ni réserver.</p>
        <p><strong>Ajoutez au moins 1 prestation</strong> (nom, durée, prix) —
        votre salon sera en ligne immédiatement.</p>
        <p>À très vite,<br/>L'équipe StyleLink</p>`,
    };
  }
  const body = repeat
    ? "Your shop is still hidden — add a service to start accepting bookings."
    : "Your shop is hidden! Add at least 1 service to start accepting bookings.";
  return {
    title: "Your shop is hidden 🙈",
    body,
    emailSubject: `${businessName} is still invisible on StyleLink`,
    emailHtml: `
      <p>Hi ${name},</p>
      <p>Your shop <strong>${businessName}</strong> has had no active services
      for ${hiddenSinceDays} day(s), so clients can't find or book you.</p>
      <p><strong>Add at least 1 service</strong> (name, duration, price) —
      your shop goes live instantly.</p>
      <p>Cheers,<br/>The StyleLink team</p>`,
  };
}

// ---------------------------------------------------------------------------
// Payload (sent by nudge_hidden_shops() in add_hidden_shop_nudge.sql)
// ---------------------------------------------------------------------------

interface NudgePayload {
  provider_id: string;
  owner_profile_id: string; // profiles.id — needed to clear a stale fcm_token
  business_name: string;
  fcm_token: string | null;
  email: string | null;
  owner_name: string | null;
  language_preference: string | null;
  first_seen_hidden_at: string;
  nudge_count: number;
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const payload = (await req.json()) as NudgePayload;
    if (!payload?.provider_id) {
      return new Response("OK", { status: 200 });
    }

    const supabase = createServiceClient();
    const isFrench = payload.language_preference === "fr";
    const firstName = payload.owner_name?.split(/\s+/)[0] ?? "";
    const hiddenSinceDays = Math.max(
      1,
      Math.floor(
        (Date.now() - new Date(payload.first_seen_hidden_at).getTime()) /
          86_400_000
      )
    );
    const repeat = (payload.nudge_count ?? 0) > 0;

    const copy = buildNudgeCopy(
      payload.business_name || "Your shop",
      firstName,
      isFrench,
      hiddenSinceDays,
      repeat
    );

    let delivered = false;
    let channel = "none";

    // 1. Push (preferred — the provider has the app installed).
    if (payload.fcm_token) {
      delivered = await sendPush(
        payload.fcm_token,
        copy.title,
        copy.body,
        {
          type: "hidden_shop_nudge",
          provider_id: payload.provider_id,
        }
      );

      // Stale token: clear it and fall back to email in the same run.
      if (!delivered) {
        await supabase
          .from("profiles")
          .update({ fcm_token: null })
          .eq("id", payload.owner_profile_id);
      } else {
        channel = "push";
      }
    }

    // 2. Email fallback.
    if (!delivered && payload.email) {
      delivered = await sendEmail(
        payload.email,
        copy.emailSubject,
        copy.emailHtml
      );
      if (delivered) channel = "email";
    }

    if (!delivered) {
      console.log(
        `No delivery channel for provider ${payload.provider_id} — will retry next sweep`
      );
      return new Response("OK", { status: 200 });
    }

    // Record success so the sweep's throttle actually applies.
    const { error: rpcError } = await supabase.rpc("mark_hidden_shop_nudged", {
      p_provider_id: payload.provider_id,
    });
    if (rpcError) {
      console.error("mark_hidden_shop_nudged failed:", rpcError);
    }

    console.log(
      `Hidden-shop nudge sent to provider ${payload.provider_id} via ${channel}`
    );
    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error("send-hidden-shop-nudge error:", err);
    return new Response("OK", { status: 200 });
  }
});

// ---------------------------------------------------------------------------
// Supabase service client (service_role key is injected by the runtime)
// ---------------------------------------------------------------------------

function createServiceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );
}
