import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createTemporarySession,
  verifyPassword,
  type TemporaryUser,
} from "../_shared/credentials.ts";

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
    return jsonResponse(500, { error: "Sign-in service is not configured." });
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

  const username =
    typeof payload.username === "string" ? payload.username.trim() : "";
  const password =
    typeof payload.password === "string" ? payload.password : "";
  if (!username || !password) {
    return jsonResponse(400, { error: "Username and password are required." });
  }
  if (!/^[a-zA-Z0-9_-]{3,30}$/.test(username) || password.length > 128) {
    return jsonResponse(401, { error: "Username or password is incorrect." });
  }

  const clientIp =
    request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim();
  if (!clientIp) {
    console.error("Unable to determine client IP for sign-in rate limiting.");
    return jsonResponse(503, { error: "Sign-in service is temporarily unavailable." });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const ipKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(serviceRoleKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const ipDigest = await crypto.subtle.sign(
    "HMAC",
    ipKey,
    new TextEncoder().encode(`login:${clientIp}`),
  );
  const ipHash = Array.from(new Uint8Array(ipDigest), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const { data: isWithinRateLimit, error: rateLimitError } = await supabase.rpc(
    "consume_registration_rate_limit",
    { p_ip_hash: ipHash, p_limit: 20, p_window_seconds: 3600 },
  );
  if (rateLimitError) {
    console.error("Sign-in rate-limit check failed.", rateLimitError);
    return jsonResponse(503, { error: "Sign-in service is temporarily unavailable." });
  }
  if (isWithinRateLimit !== true) {
    return jsonResponse(429, { error: "Too many sign-in attempts. Try again later." });
  }

  const normalizedUsername = username.toLowerCase();
  const { data, error } = await supabase
    .from("Users")
    .select("id, username, firstname, lastname, role, password")
    .eq("username", normalizedUsername)
    .limit(20);
  if (error) {
    console.error("Failed to load account for sign-in.", error);
    return jsonResponse(500, { error: "Sign-in could not be completed." });
  }
  if (!data || data.length === 0) {
    return jsonResponse(401, { error: "Username or password is incorrect." });
  }

  const matchingUsers = [];
  for (const candidate of data) {
    if (typeof candidate.password !== "string") continue;

    if (await verifyPassword(password, candidate.password)) {
      matchingUsers.push(candidate);
      continue;
    }

    if (
      !candidate.password.startsWith("pbkdf2-sha256$") &&
      candidate.password === password
    ) {
      const upgradedHash = await hashPassword(password);
      const { data: upgradedAccount, error: upgradeError } = await supabase
        .from("Users")
        .update({ password: upgradedHash })
        .eq("id", candidate.id)
        .eq("password", candidate.password)
        .select("id")
        .maybeSingle();

      if (upgradeError) {
        console.error("Failed to upgrade legacy account password hash.", upgradeError);
        return jsonResponse(500, { error: "Sign-in could not be completed." });
      }
      if (upgradedAccount) {
        matchingUsers.push(candidate);
      }
    }
  }
  if (matchingUsers.length === 0) {
    return jsonResponse(401, { error: "Username or password is incorrect." });
  }
  if (matchingUsers.length > 1 || data.length === 20) {
    return jsonResponse(409, {
      error: "Multiple accounts use this username. Contact an administrator.",
    });
  }

  const account = matchingUsers[0];
  const user: TemporaryUser = {
    id: String(account.id),
    username: account.username,
    firstname: account.firstname,
    lastname: account.lastname,
    role: account.role,
  };
  const session = await createTemporarySession(user, serviceRoleKey);
  return jsonResponse(200, { ...user, ...session });
});
