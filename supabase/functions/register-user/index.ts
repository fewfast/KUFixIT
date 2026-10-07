import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createTemporarySession,
  hashPassword,
  type TemporaryUser,
} from "../_shared/credentials.ts";
import {
  hashThaiNationalId,
} from "../_shared/thai_national_id.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const validRoles = new Set(["User", "Admin", "SuperAdmin"]);

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
    console.error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not configured.");
    return jsonResponse(500, { error: "Registration service is not configured." });
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
  const nationalId =
    typeof payload.nationalId === "string" ? payload.nationalId : "";
  const username =
    typeof payload.username === "string" ? payload.username.trim() : "";
  const password =
    typeof payload.password === "string" ? payload.password : "";
  const role = typeof payload.role === "string" ? payload.role : "";

  if (!firstName || !lastName || !nationalId || !username || !password || !role) {
    return jsonResponse(400, { error: "All registration fields are required." });
  }
  if (!/^\d{13}$/.test(nationalId)) {
    return jsonResponse(400, { error: "Citizen ID must be exactly 13 digits." });
  }
  if (firstName.length > 80 || lastName.length > 80) {
    return jsonResponse(400, { error: "Names must be 80 characters or fewer." });
  }
  if (!/^[a-zA-Z0-9_-]{3,30}$/.test(username)) {
    return jsonResponse(400, { error: "Username must be 3-30 valid characters." });
  }
  if (
    password.length < 8 ||
    password.length > 128 ||
    !/[a-z]/.test(password) ||
    !/[A-Z]/.test(password) ||
    !/[0-9]/.test(password) ||
    !/[^a-zA-Z0-9]/.test(password)
  ) {
    return jsonResponse(400, { error: "Password does not meet the security requirements." });
  }
  if (!validRoles.has(role)) {
    return jsonResponse(400, { error: "Invalid role." });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const clientIp =
    request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim();
  if (!clientIp) {
    console.error("Unable to determine client IP for registration rate limiting.");
    return jsonResponse(503, { error: "Registration service is temporarily unavailable." });
  }

  const hmacKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(serviceRoleKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const ipDigest = await crypto.subtle.sign(
    "HMAC",
    hmacKey,
    new TextEncoder().encode(clientIp),
  );
  const ipHash = Array.from(new Uint8Array(ipDigest), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const { data: isWithinRateLimit, error: rateLimitError } = await supabase.rpc(
    "consume_registration_rate_limit",
    { p_ip_hash: ipHash, p_limit: 5, p_window_seconds: 3600 },
  );
  if (rateLimitError) {
    console.error("Registration rate-limit check failed.", rateLimitError);
    return jsonResponse(503, { error: "Registration service is temporarily unavailable." });
  }
  if (isWithinRateLimit !== true) {
    return jsonResponse(429, { error: "Too many registration attempts. Try again later." });
  }

  const normalizedUsername = username.toLowerCase();
  const passwordHash = await hashPassword(password);
  const realIdSecret = Deno.env.get("REALID_HMAC_SECRET");
  if (!realIdSecret) {
    console.error("REALID_HMAC_SECRET is not configured.");
    return jsonResponse(500, { error: "Registration service is not configured." });
  }
  let realIdHash: string;
  try {
    realIdHash = await hashThaiNationalId(nationalId, realIdSecret);
  } catch (error) {
    console.error("Failed to protect the citizen ID.", error);
    return jsonResponse(500, { error: "Registration service is not configured." });
  }
  const { data, error: profileError } = await supabase
    .from("Users")
    .insert({
      firstname: firstName,
      lastname: lastName,
      username: normalizedUsername,
      role,
      password: passwordHash,
      realid: realIdHash,
    })
    .select("id, username, firstname, lastname, role")
    .single();

  if (profileError) {
    console.error("Failed to insert registration data into Users table.", profileError);
    const uniquenessConflict = profileError.code === "23505";
    return jsonResponse(uniquenessConflict ? 409 : 500, {
      error: uniquenessConflict
        ? "Username or citizen ID is already registered."
        : "Registration could not be completed. Please try again.",
    });
  }

  const user: TemporaryUser = {
    id: String(data.id),
    username: data.username,
    firstname: data.firstname,
    lastname: data.lastname,
    role: data.role,
  };
  const session = await createTemporarySession(user, serviceRoleKey);
  return jsonResponse(201, { ...user, ...session });
});
