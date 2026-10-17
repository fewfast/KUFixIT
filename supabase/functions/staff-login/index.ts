import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createTemporarySession,
  type TemporaryUser,
} from "../_shared/credentials.ts";
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

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse(400, { error: "Invalid JSON request body." });
  }
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    return jsonResponse(400, { error: "Invalid request body." });
  }

  const values = payload as Record<string, unknown>;
  const username = typeof values.username === "string"
    ? values.username.trim()
    : "";
  const password = typeof values.password === "string" ? values.password : "";
  if (
    !username ||
    username.length > 128 ||
    !password ||
    new TextEncoder().encode(password).length > 72
  ) {
    return jsonResponse(400, { error: "กรุณาตรวจสอบชื่อผู้ใช้และรหัสผ่าน" });
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
  const { data, error } = await supabase.rpc("authenticate_system_user", {
    p_username: username,
    p_password: password,
  });
  if (error) {
    console.error("Failed to authenticate system user.", error);
    return jsonResponse(500, { error: "Sign-in could not be completed." });
  }

  const account = Array.isArray(data) ? data[0] : null;
  if (
    typeof account !== "object" ||
    account === null ||
    typeof account.username !== "string" ||
    !["Technician", "Admin", "SuperAdmin"].includes(account.role)
  ) {
    return jsonResponse(401, {
      error: "ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง หรือบัญชีหมดอายุแล้ว",
    });
  }

  const user: TemporaryUser = {
    id: account.username,
    username: account.username,
    firstname: account.username,
    lastname: "",
    role: account.role,
  };
  const endtime = account.endtime;
  if (endtime !== null && typeof endtime !== "string") {
    console.error("System user authentication returned an invalid end time.");
    return jsonResponse(500, { error: "Sign-in could not be completed." });
  }
  const endtimeMilliseconds = endtime === null ? null : Date.parse(endtime);
  if (
    endtimeMilliseconds !== null &&
    (!Number.isFinite(endtimeMilliseconds) ||
      endtimeMilliseconds <= Date.now())
  ) {
    return jsonResponse(401, {
      error: "ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง หรือบัญชีหมดอายุแล้ว",
    });
  }
  const expiresAt = endtimeMilliseconds === null
    ? undefined
    : Math.floor(endtimeMilliseconds / 1000);
  const session = await createTemporarySession(
    user,
    serviceRoleKey,
    expiresAt,
  );
  let uid: string | undefined;
  if (account.role === "Technician") {
    const { data: technician, error: technicianError } = await supabase
      .from("Maintenance_Users")
      .select("uid")
      .eq("username", account.username)
      .maybeSingle();
    if (technicianError) {
      console.error("Failed to load technician UID for sign-in.", technicianError);
      return jsonResponse(500, { error: "Sign-in could not be completed." });
    }
    if (
      !technician ||
      typeof technician.uid !== "string" ||
      !/^t_[0-9]{10}$/.test(technician.uid)
    ) {
      console.error("Technician account is missing a valid UID.");
      return jsonResponse(500, { error: "Sign-in could not be completed." });
    }
    uid = technician.uid;
  }
  return jsonResponse(200, {
    ...user,
    ...(uid ? { uid } : {}),
    hasNationalId: false,
    isSystemAccount: true,
    ...session,
  });
});
