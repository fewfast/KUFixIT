import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyTemporarySession } from "../_shared/credentials.ts";
import { getSupabaseAdminKey } from "../_shared/supabase_admin_key.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = getSupabaseAdminKey();
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Supabase server configuration is missing.");
    return jsonResponse(500, { error: "Profile service is not configured." });
  }

  const authorization = request.headers.get("authorization");
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) {
    return jsonResponse(401, { error: "Please sign in again to update your profile." });
  }

  const claims = await verifyTemporarySession(token, serviceRoleKey);
  if (
    !claims ||
    typeof claims.sub !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(claims.sub) ||
    !["User", "Admin", "SuperAdmin", "Technician"].includes(String(claims.role))
  ) {
    return jsonResponse(401, { error: "Please sign in again to update your profile." });
  }

  let payload: Record<string, unknown>;
  try {
    const value: unknown = await request.json();
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      return jsonResponse(400, { error: "Invalid request body." });
    }
    payload = value as Record<string, unknown>;
  } catch {
    return jsonResponse(400, { error: "Invalid JSON request body." });
  }

  const displayName = typeof payload.displayName === "string"
    ? payload.displayName.trim()
    : [
      typeof payload.firstName === "string" ? payload.firstName.trim() : "",
      typeof payload.lastName === "string" ? payload.lastName.trim() : "",
    ].filter(Boolean).join(" ");
  if (!displayName || displayName.length > 160) {
    return jsonResponse(400, {
      error: "Check the display name.",
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: account, error: accountError } = await supabase
    .from("Users")
    .select("google_auth_user_id, status")
    .eq("google_auth_user_id", claims.sub)
    .maybeSingle();
  if (accountError) {
    console.error("Failed to load account for profile update.", accountError);
    return jsonResponse(500, { error: "Profile could not be updated. Please try again." });
  }
  if (!account) {
    return jsonResponse(404, { error: "User account was not found." });
  }
  if (account.status !== "active") {
    return jsonResponse(403, {
      error: "This account is inactive and cannot update its profile.",
    });
  }

  const profileUpdate = {
    "Display Name": displayName,
  };
  let updateQuery = supabase
    .from("Users")
    .update(profileUpdate)
    .eq("google_auth_user_id", claims.sub);
  const { data, error } = await updateQuery
    .select("google_auth_user_id, \"Display Name\", role")
    .maybeSingle();

  if (error) {
    console.error("Failed to update user profile.", error);
    return jsonResponse(500, { error: "Profile could not be updated. Please try again." });
  }
  if (!data) {
    return jsonResponse(404, { error: "User account was not found." });
  }

  return jsonResponse(200, {
    success: true,
    displayname: data["Display Name"],
  });
});
