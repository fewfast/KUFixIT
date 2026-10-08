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

function metadataValue(user: { user_metadata?: Record<string, unknown> }, keys: string[]) {
  for (const key of keys) {
    const value = user.user_metadata?.[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return null;
}

function googleDisplayName(user: { user_metadata?: Record<string, unknown> }, email: string) {
  const fullName = metadataValue(user, ["full_name", "name", "display_name"]);
  const givenName = metadataValue(user, ["given_name", "first_name"]);
  const familyName = metadataValue(user, ["family_name", "last_name"]);
  const name = fullName || [givenName, familyName].filter(Boolean).join(" ");
  return (name || email.split("@")[0]).trim().slice(0, 160) ||
    email.split("@")[0];
}

function usernameForGoogleUser(email: string, googleUserId: string) {
  let prefix = email
    .split("@")[0]
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "")
    .slice(0, 19);
  if (prefix.length < 3) prefix = `usr${prefix}`;
  const suffix = googleUserId.replaceAll("-", "").slice(0, 10).toLowerCase();
  return `${prefix}_${suffix}`;
}

function registrationResponse(
  account: {
    google_auth_user_id: string;
    uid: number;
    status: string;
    "Display Name": string;
    role: string;
  },
  username: string,
  firstName: string,
  lastName: string,
  serviceRoleKey: string,
) {
  const user: TemporaryUser = {
    id: account.google_auth_user_id,
    username,
    firstname: firstName.slice(0, 80),
    lastname: lastName.slice(0, 80),
    role: account.role,
  };
  return createTemporarySession(user, serviceRoleKey).then((session) =>
    jsonResponse(201, {
      ...user,
      uid: account.uid,
      status: account.status,
      displayname: account["Display Name"],
      hasNationalId: false,
      ...session,
    })
  );
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
    return jsonResponse(500, { error: "Registration service is not configured." });
  }

  const token = bearerToken(request);
  if (!token) {
    return jsonResponse(401, { error: "Sign in with Google before registering." });
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const googleUser = await verifyGoogleUser(supabase, token);
  const email = googleUser?.email?.trim().toLowerCase();
  if (!googleUser || !email) {
    return jsonResponse(401, { error: "A valid Google account is required." });
  }

  const displayname = googleDisplayName(googleUser, email);
  const nameParts = displayname.split(/\s+/);
  const firstName =
    metadataValue(googleUser, ["given_name", "first_name"]) ??
    nameParts.shift() ??
    displayname;
  const lastName =
    metadataValue(googleUser, ["family_name", "last_name"]) ??
    nameParts.join(" ");
  const username = usernameForGoogleUser(email, googleUser.id);
  const { data: existingAccount, error: lookupError } = await supabase
    .from("Users")
    .select("google_auth_user_id, uid, status, \"Display Name\", role")
    .eq("google_auth_user_id", googleUser.id)
    .maybeSingle();
  if (lookupError) {
    console.error("Failed to check for an existing Google account.", lookupError);
    return jsonResponse(500, {
      error: "Registration could not be completed. Please try again.",
    });
  }
  if (existingAccount) {
    return await registrationResponse(
      existingAccount,
      username,
      firstName,
      lastName,
      serviceRoleKey,
    );
  }

  const { data, error: profileError } = await supabase
    .from("Users")
    .insert({
      google_auth_user_id: googleUser.id,
      "Display Name": displayname,
      role: "User",
      created_at: new Date().toISOString(),
      status: "active",
    })
    .select("google_auth_user_id, uid, status, \"Display Name\", role")
    .single();

  if (profileError) {
    console.error("Failed to insert registration data into Users table.", profileError);
    if (profileError.code === "23505") {
      const { data: accountAfterConflict, error: conflictLookupError } =
        await supabase
          .from("Users")
          .select("google_auth_user_id, uid, status, \"Display Name\", role")
          .eq("google_auth_user_id", googleUser.id)
          .maybeSingle();
      if (conflictLookupError) {
        console.error(
          "Failed to reload the account after a registration conflict.",
          conflictLookupError,
        );
        return jsonResponse(500, {
          error: "Registration could not be completed. Please try again.",
        });
      }
      if (accountAfterConflict) {
        return await registrationResponse(
          accountAfterConflict,
          username,
          firstName,
          lastName,
          serviceRoleKey,
        );
      }
    }
    const uniquenessConflict = profileError.code === "23505";
    return jsonResponse(uniquenessConflict ? 409 : 500, {
      error: uniquenessConflict
        ? "This Google email or generated username is already registered."
        : "Registration could not be completed. Please try again.",
    });
  }

  return await registrationResponse(
    data,
    username,
    firstName,
    lastName,
    serviceRoleKey,
  );
});
