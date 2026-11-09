// =============================================================================
// delete-account
//
// Trusted account deletion endpoint. The Flutter client invokes this function
// with its user access token; the function:
//   1. verifies the caller with the auth server,
//   2. removes the caller's stored images,
//   3. deletes the auth user (profile/provider/bookings/messages/reviews/
//      favorites cascade through foreign keys),
//   4. returns { deleted: true } only after the auth deletion succeeded.
//
// The service-role key is injected by Supabase and never reaches the browser.
//
// Deploy:
//   supabase functions deploy delete-account
// =============================================================================

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function isMissingBucketError(message: string): boolean {
  const m = message.toLowerCase();
  return m.includes("bucket not found") || m.includes("not found");
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return json({ error: "Missing bearer token" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Server is not configured for account deletion" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Verify the caller from their access token. Never trust a user id from the
  // request body.
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "Not authenticated" }, 401);
  }
  const uid = user.id;

  const removed: string[] = [];

  async function removeObjects(bucket: string, paths: string[]) {
    if (paths.length === 0) return;
    const { error } = await admin.storage.from(bucket).remove(paths);
    if (error) {
      if (isMissingBucketError(error.message)) return;
      throw new Error(`${bucket}: ${error.message}`);
    }
    removed.push(...paths.map((p) => `${bucket}/${p}`));
  }

  try {
    // Fixed-name objects used by the app.
    await removeObjects("avatars", [`avatar_${uid}.jpg`]);
    await removeObjects("provider_assets", [`covers/${uid}.jpg`]);
    await removeObjects("covers", [`cover_${uid}.jpg`]);

    // Portfolio images live under a per-user folder; list then remove.
    const { data: portfolioObjects, error: listError } = await admin.storage
      .from("provider_portfolios")
      .list(uid, { limit: 1000 });

    if (listError) {
      if (!isMissingBucketError(listError.message)) {
        throw new Error(`provider_portfolios: ${listError.message}`);
      }
    } else {
      const paths = (portfolioObjects ?? [])
        .map((object) => object.name)
        .filter((name): name is string => Boolean(name))
        .map((name) => `${uid}/${name}`);
      await removeObjects("provider_portfolios", paths);
    }
  } catch (error) {
    // Keep the account intact so the user can retry. Storage removal is
    // idempotent, so a partial cleanup is safe to repeat.
    console.error("delete-account storage cleanup failed:", errorMessage(error));
    return json(
      { error: `Could not remove stored images: ${errorMessage(error)}` },
      500,
    );
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    console.error("delete-account auth deletion failed:", deleteError.message);
    return json(
      {
        error:
          "The account could not be deleted. No data was removed from the auth " +
          "system; please try again or contact support.",
      },
      500,
    );
  }

  // Best-effort audit line. The auth user is gone at this point.
  console.log(`delete-account: deleted user ${uid}, files=${removed.length}`);

  return json({ deleted: true, files_removed: removed.length });
});
