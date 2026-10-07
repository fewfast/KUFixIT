import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  hashPassword,
  verifyTemporarySession,
} from "../_shared/credentials.ts";
import {
  constantTimeEqual,
  hashThaiNationalId,
} from "../_shared/thai_national_id.ts";

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
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
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
    !/^\d{1,19}$/.test(claims.sub) ||
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

  const firstName =
    typeof payload.firstName === "string" ? payload.firstName.trim() : "";
  const lastName =
    typeof payload.lastName === "string" ? payload.lastName.trim() : "";
  const username =
    typeof payload.username === "string" ? payload.username.trim() : "";
  const nationalId =
    typeof payload.nationalId === "string" ? payload.nationalId : "";
  const newPassword =
    typeof payload.newPassword === "string" ? payload.newPassword : "";
  const passwordProvided = payload.newPassword != null &&
    payload.newPassword !== "";
  const normalizedUsername = username.toLowerCase();
  if (
    !firstName ||
    !lastName ||
    !/^[a-zA-Z0-9_-]{3,30}$/.test(username) ||
    firstName.length > 80 ||
    lastName.length > 80 ||
    (passwordProvided &&
      (newPassword.length < 8 ||
        newPassword.length > 128 ||
        !/[a-z]/.test(newPassword) ||
        !/[A-Z]/.test(newPassword) ||
        !/[0-9]/.test(newPassword) ||
        !/[^a-zA-Z0-9]/.test(newPassword)))
  ) {
    return jsonResponse(400, {
      error: "Check the profile fields, citizen ID, and password requirements.",
    });
  }

  const clientIp =
    request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim();
  if (!clientIp) {
    console.error("Unable to determine client IP for profile-update rate limiting.");
    return jsonResponse(503, { error: "Profile service is temporarily unavailable." });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const rateLimitKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(serviceRoleKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const rateLimitDigest = await crypto.subtle.sign(
    "HMAC",
    rateLimitKey,
    new TextEncoder().encode(`profile-update:${claims.sub}:${clientIp}`),
  );
  const rateLimitHash = Array.from(new Uint8Array(rateLimitDigest), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const { data: allowed, error: rateLimitError } = await supabase.rpc(
    "consume_registration_rate_limit",
    { p_ip_hash: rateLimitHash, p_limit: 10, p_window_seconds: 3600 },
  );
  if (rateLimitError) {
    console.error("Profile-update rate-limit check failed.", rateLimitError);
    return jsonResponse(503, { error: "Profile service is temporarily unavailable." });
  }
  if (allowed !== true) {
    return jsonResponse(429, { error: "Too many profile changes. Try again later." });
  }

  const { data: account, error: accountError } = await supabase
    .from("Users")
    .select("id, username, realid")
    .eq("id", claims.sub)
    .maybeSingle();
  if (accountError) {
    console.error("Failed to load account for profile update.", accountError);
    return jsonResponse(500, { error: "Profile could not be updated. Please try again." });
  }
  if (!account) {
    return jsonResponse(404, { error: "User account was not found." });
  }

  const usernameChanged =
    normalizedUsername !== account.username.toLowerCase();
  const identityVerificationRequired = passwordProvided || usernameChanged;
  if (identityVerificationRequired && !/^\d{13}$/.test(nationalId)) {
    return jsonResponse(400, {
      error: "Enter the 13-digit citizen ID to change your username or password.",
    });
  }

  let verifiedRealId: string | null = null;
  if (identityVerificationRequired) {
    const realIdSecret = Deno.env.get("REALID_HMAC_SECRET");
    if (!realIdSecret) {
      console.error("REALID_HMAC_SECRET is not configured.");
      return jsonResponse(500, { error: "Profile service is not configured." });
    }

    let submittedRealIdHash: string;
    try {
      submittedRealIdHash = await hashThaiNationalId(nationalId, realIdSecret);
    } catch (error) {
      console.error("Failed to protect the submitted citizen ID.", error);
      return jsonResponse(500, { error: "Profile service is not configured." });
    }

    if (typeof account.realid !== "string") {
      return jsonResponse(409, {
        error: "This account has no citizen ID on file. Please create a new account.",
      });
    }
    if (!constantTimeEqual(account.realid, submittedRealIdHash)) {
      return jsonResponse(403, { error: "Citizen ID does not match this account." });
    }
    verifiedRealId = account.realid;
  }

  const profileUpdate: {
    firstname: string;
    lastname: string;
    username: string;
    password?: string;
  } = {
    firstname: firstName,
    lastname: lastName,
    username: normalizedUsername,
  };
  if (passwordProvided) {
    profileUpdate.password = await hashPassword(newPassword);
  }
  let updateQuery = supabase
    .from("Users")
    .update(profileUpdate)
    .eq("id", claims.sub)
    .eq("username", account.username);
  if (verifiedRealId !== null) {
    updateQuery = updateQuery.eq("realid", verifiedRealId);
  }
  const { data, error } = await updateQuery
    .select("id, username, firstname, lastname, role")
    .maybeSingle();

  if (error) {
    console.error("Failed to update user profile.", error);
    if (error.code === "23505") {
      return jsonResponse(409, { error: "This username is already registered." });
    }
    return jsonResponse(500, { error: "Profile could not be updated. Please try again." });
  }
  if (!data) {
    return jsonResponse(404, { error: "User account was not found." });
  }

  return jsonResponse(200, {
    success: true,
    username: data.username,
  });
});
