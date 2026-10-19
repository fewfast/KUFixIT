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

function bangkokDate(value: string): string | null {
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) return null;
  return new Date(milliseconds + 7 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function dateNumber(value: string): number {
  const [year, month, day] = value.split("-").map(Number);
  return Date.UTC(year, month - 1, day) / (24 * 60 * 60 * 1000);
}

function endOfBangkokDate(value: string): number {
  const [year, month, day] = value.split("-").map(Number);
  return Date.UTC(year, month - 1, day + 1) - 7 * 60 * 60 * 1000;
}

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
  if (
    typeof payload !== "object" ||
    payload === null ||
    Array.isArray(payload)
  ) {
    return jsonResponse(400, { error: "Invalid request body." });
  }

  const values = payload as Record<string, unknown>;
  const username =
    typeof values.username === "string" ? values.username.trim() : "";
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
    (!Number.isFinite(endtimeMilliseconds) || endtimeMilliseconds <= Date.now())
  ) {
    return jsonResponse(401, {
      error: "ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง หรือบัญชีหมดอายุแล้ว",
    });
  }
  const expiresAt =
    endtimeMilliseconds === null
      ? undefined
      : Math.floor(endtimeMilliseconds / 1000);
  const session = await createTemporarySession(user, serviceRoleKey, expiresAt);
  let uid: string | undefined;
  let accessUntil: number | undefined;
  let accessRangeStart: string | undefined;
  let accessRangeEnd: string | undefined;
  if (account.role === "Technician") {
    const { data: technician, error: technicianError } = await supabase
      .from("Maintenance_Users")
      .select("uid, start_time, end_time")
      .eq("username", account.username)
      .maybeSingle();
    if (technicianError) {
      console.error(
        "Failed to load technician UID for sign-in.",
        technicianError,
      );
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
    if (
      !Array.isArray(technician.start_time) ||
      !Array.isArray(technician.end_time) ||
      technician.start_time.length !== technician.end_time.length
    ) {
      console.error("Technician account has invalid date ranges.");
      return jsonResponse(500, { error: "Sign-in could not be completed." });
    }
    const today = new Date(Date.now() + 7 * 60 * 60 * 1000)
      .toISOString()
      .slice(0, 10);
    const ranges = technician.start_time.map((start, index) => {
      const end = technician.end_time[index];
      if (typeof start !== "string" || typeof end !== "string") return null;
      const startDate = bangkokDate(start);
      const endDate = bangkokDate(end);
      if (!startDate || !endDate || startDate > endDate) return null;
      return {
        start: startDate,
        end: endDate,
        storedStart: start,
        storedEnd: end,
      };
    });
    if (ranges.some((range) => range === null)) {
      console.error("Technician account has an invalid date range value.");
      return jsonResponse(500, { error: "Sign-in could not be completed." });
    }
    const retainedRanges = ranges.filter(
      (range) => range !== null && range.end >= today,
    );
    if (retainedRanges.length !== ranges.length) {
      const { error: updateError } = await supabase
        .from("Maintenance_Users")
        .update({
          start_time: retainedRanges.map((range) => range.storedStart),
          end_time: retainedRanges.map((range) => range.storedEnd),
        })
        .eq("uid", technician.uid);
      if (updateError) {
        console.error(
          "Failed to remove expired technician date ranges.",
          updateError,
        );
        return jsonResponse(500, { error: "Sign-in could not be completed." });
      }
    }
    const activeRanges = retainedRanges.filter(
      (range) => range.start <= today && range.end >= today,
    );
    if (activeRanges.length === 0) {
      console.error("Technician authenticated without an active date range.");
      return jsonResponse(500, { error: "Sign-in could not be completed." });
    }
    let coveredThrough = Math.max(
      ...activeRanges.map((range) => dateNumber(range.end)),
    );
    let coveredFrom = Math.min(
      ...activeRanges.map((range) => dateNumber(range.start)),
    );
    let extended = true;
    while (extended) {
      extended = false;
      for (const range of retainedRanges) {
        if (
          range !== null &&
          dateNumber(range.start) <= coveredThrough + 1 &&
          dateNumber(range.end) >= coveredFrom - 1 &&
          (dateNumber(range.start) < coveredFrom ||
            dateNumber(range.end) > coveredThrough)
        ) {
          coveredFrom = Math.min(coveredFrom, dateNumber(range.start));
          coveredThrough = Math.max(coveredThrough, dateNumber(range.end));
          extended = true;
        }
      }
    }
    const coveredStartDate = new Date(coveredFrom * 24 * 60 * 60 * 1000);
    const coveredEndDate = new Date(coveredThrough * 24 * 60 * 60 * 1000);
    accessRangeStart = `${coveredStartDate.getUTCFullYear()}-${String(
      coveredStartDate.getUTCMonth() + 1,
    ).padStart(
      2,
      "0",
    )}-${String(coveredStartDate.getUTCDate()).padStart(2, "0")}`;
    const endDate = `${coveredEndDate.getUTCFullYear()}-${String(
      coveredEndDate.getUTCMonth() + 1,
    ).padStart(
      2,
      "0",
    )}-${String(coveredEndDate.getUTCDate()).padStart(2, "0")}`;
    accessRangeEnd = endDate;
    accessUntil = Math.floor(endOfBangkokDate(endDate) / 1000);
    uid = technician.uid;
  }
  return jsonResponse(200, {
    ...user,
    ...(uid ? { uid } : {}),
    ...(accessUntil ? { accessUntil } : {}),
    ...(accessRangeStart ? { accessRangeStart } : {}),
    ...(accessRangeEnd ? { accessRangeEnd } : {}),
    hasNationalId: false,
    isSystemAccount: true,
    ...session,
  });
});
