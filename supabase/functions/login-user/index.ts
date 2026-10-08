import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createTemporarySession,
  type TemporaryUser,
} from "../_shared/credentials.ts";
import { bearerToken, verifyGoogleUser } from "../_shared/google_auth.ts";
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
    return jsonResponse(500, { error: "Sign-in service is not configured." });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const token = bearerToken(request);
  if (!token) {
    return jsonResponse(401, { error: "Sign in with Google to continue." });
  }
  const googleUser = await verifyGoogleUser(supabase, token);
  if (!googleUser) {
    return jsonResponse(401, { error: "A valid Google account is required." });
  }

  const { data: account, error } = await supabase
    .from("Users")
    .select("google_auth_user_id, uid, status, \"Display Name\", role")
    .eq("google_auth_user_id", googleUser.id)
    .maybeSingle();
  if (error) {
    console.error("Failed to load account for sign-in.", error);
    return jsonResponse(500, { error: "Sign-in could not be completed." });
  }
  if (!account) {
    return jsonResponse(404, {
      error: "No KUFixIT account is registered with this Google account. Please register first.",
      code: "google_account_not_registered",
    });
  }

  const displayNameParts = account["Display Name"].trim().split(/\s+/);
  const user: TemporaryUser = {
    id: account.google_auth_user_id,
    username: `u_${account.google_auth_user_id.replaceAll("-", "").slice(0, 26)}`,
    firstname: displayNameParts.shift() ?? account["Display Name"],
    lastname: displayNameParts.join(" "),
    role: account.role,
  };
  const session = await createTemporarySession(user, serviceRoleKey);
  return jsonResponse(200, {
    ...user,
    uid: account.uid,
    status: account.status,
    displayname: account["Display Name"],
    hasNationalId: false,
    ...session,
  });
});
