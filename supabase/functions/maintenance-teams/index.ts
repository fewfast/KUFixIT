import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyTemporarySession } from "../_shared/credentials.ts";
import { getSupabaseAdminKey } from "../_shared/supabase_admin_key.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const passwordAlphabet =
  "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
const encoder = new TextEncoder();

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromBase64Url(value: string): ArrayBuffer {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
  const decoded = atob(padded);
  const bytes = new Uint8Array(decoded.length);
  for (let index = 0; index < decoded.length; index++) {
    bytes[index] = decoded.charCodeAt(index);
  }
  return bytes.buffer;
}

async function getCredentialKey(): Promise<CryptoKey> {
  const configuredKey = Deno.env.get("MAINTENANCE_CREDENTIALS_KEY");
  if (!configuredKey || configuredKey.length < 32) {
    throw new Error("MAINTENANCE_CREDENTIALS_KEY must be at least 32 characters.");
  }
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(configuredKey));
  return crypto.subtle.importKey("raw", digest, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

async function encryptPassword(password: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await getCredentialKey(),
    encoder.encode(password),
  );
  return `enc:v1:${toBase64Url(iv)}.${toBase64Url(new Uint8Array(ciphertext))}`;
}

async function decryptPassword(value: unknown): Promise<string> {
  if (typeof value !== "string") throw new Error("Stored password is invalid.");
  if (!value.startsWith("enc:v1:")) return value;
  const encryptedValue = value.slice("enc:v1:".length);
  const [ivText, ciphertextText, extra] = encryptedValue.split(".");
  if (!ivText || !ciphertextText || extra !== undefined) {
    throw new Error("Stored password has an invalid encrypted format.");
  }
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: fromBase64Url(ivText) },
    await getCredentialKey(),
    fromBase64Url(ciphertextText),
  );
  return new TextDecoder().decode(plaintext);
}

function generateRandomString(length: number): string {
  const output: string[] = [];
  const limit = 256 - (256 % passwordAlphabet.length);
  while (output.length < length) {
    const bytes = crypto.getRandomValues(new Uint8Array(length - output.length));
    for (const byte of bytes) {
      if (byte < limit) output.push(passwordAlphabet[byte % passwordAlphabet.length]);
    }
  }
  return output.join("");
}

function generateRandomTechnicianUid(): string {
  let digits = "";
  for (let index = 0; index < 10; index++) {
    const limit = index === 0 ? 252 : 250;
    let byte: number;
    do {
      const randomByte = crypto.getRandomValues(new Uint8Array(1));
      byte = randomByte[0];
    } while (byte >= limit);
    digits += String(index === 0 ? 1 + byte % 9 : byte % 10);
  }
  return `t_${digits}`;
}

function validateTechnicianUid(value: unknown): value is string {
  return typeof value === "string" && /^t_[0-9]{10}$/.test(value);
}

function bangkokDate(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const milliseconds = Date.parse(value);
  return Number.isFinite(milliseconds)
    ? new Date(milliseconds + 7 * 60 * 60 * 1000).toISOString().slice(0, 10)
    : null;
}

function duplicateValueMessage(error: unknown): string | null {
  if (!isRecord(error) || error.code !== "23505") return null;
  const conflict = [
    error.constraint,
    error.message,
    error.details,
  ].filter((value): value is string => typeof value === "string")
    .join(" ")
    .toLowerCase();

  if (
    conflict.includes("maintenance_users_display_name_key") ||
    conflict.includes("teamname")
  ) {
    return "ชื่อช่างนี้มีในระบบแล้ว กรุณาใช้ชื่ออื่น";
  }
  if (conflict.includes("username") || conflict.includes("systems_users")) {
    return "username นี้ถูกใช้แล้ว กรุณาใช้ username อื่น";
  }
  if (conflict.includes("uid") || conflict.includes("maintenance_users_pkey")) {
    return "ระบบสร้าง UID ซ้ำ กรุณาลองสร้างบัญชีอีกครั้ง";
  }
  return "ข้อมูลบัญชีช่างซ้ำกับบัญชีที่มีอยู่ กรุณาตรวจสอบชื่อช่างและ username";
}

function validateDateRanges(
  value: unknown,
): { starts: string[]; ends: string[] } | null {
  if (!Array.isArray(value) || value.length > 48) return null;
  const ranges: { start: string; end: string }[] = [];
  const today = new Date(Date.now() + 7 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
  for (const range of value) {
    if (!isRecord(range) || typeof range.start !== "string" ||
      typeof range.end !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(range.start) ||
      !/^\d{4}-\d{2}-\d{2}$/.test(range.end)) {
      return null;
    }
    const startDate = new Date(`${range.start}T00:00:00Z`);
    const endDate = new Date(`${range.end}T00:00:00Z`);
    if (
      !Number.isFinite(startDate.getTime()) ||
      !Number.isFinite(endDate.getTime()) ||
      startDate.toISOString().slice(0, 10) !== range.start ||
      endDate.toISOString().slice(0, 10) !== range.end ||
      range.start < today ||
      range.end < range.start
    ) {
      return null;
    }
    ranges.push({ start: range.start, end: range.end });
  }
  ranges.sort((first, second) =>
      first.start.localeCompare(second.start) ||
      first.end.localeCompare(second.end)
    );
  for (let index = 1; index < ranges.length; index++) {
    if (ranges[index].start <= ranges[index - 1].end) {
      return null;
    }
  }
  return {
    starts: ranges.map((range) => `${range.start}T00:00:00+07:00`),
    ends: ranges.map((range) => `${range.end}T00:00:00+07:00`),
  };
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
    return jsonResponse(500, { error: "Maintenance service is not configured." });
  }

  const token = request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)
    ?.[1];
  if (!token) {
    return jsonResponse(401, { error: "กรุณาเข้าสู่ระบบด้วยบัญชีผู้ดูแลระบบ" });
  }
  const claims = await verifyTemporarySession(token, serviceRoleKey);
  if (
    !claims ||
    typeof claims.sub !== "string" ||
    !["Admin", "SuperAdmin"].includes(String(claims.role))
  ) {
    return jsonResponse(403, { error: "หน้านี้สำหรับผู้ดูแลระบบเท่านั้น" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  try {
    const isSystemAccount = claims.username === claims.sub;
    const { data: account, error } = isSystemAccount
      ? await supabase
        .from("Systems_Users")
        .select("role, endtime")
        .eq("Username", claims.sub)
        .maybeSingle()
      : await supabase
        .from("Users")
        .select("role, status")
        .eq("google_auth_user_id", claims.sub)
        .maybeSingle();
    if (error) throw error;
    const currentlyAdmin = account &&
      ["Admin", "SuperAdmin"].includes(account.role) &&
      (isSystemAccount
        ? "endtime" in account && (account.endtime === null ||
          (typeof account.endtime === "string" &&
            Date.parse(account.endtime) > Date.now()))
        : "status" in account && account.status === "active");
    if (!currentlyAdmin) {
      return jsonResponse(403, { error: "หน้านี้สำหรับผู้ดูแลระบบเท่านั้น" });
    }
  } catch (error) {
    console.error("Failed to verify current maintenance administrator.", error);
    return jsonResponse(500, {
      error: "ไม่สามารถตรวจสอบสิทธิ์ผู้ดูแลระบบได้ กรุณาลองอีกครั้ง",
    });
  }

  let payload: Record<string, unknown>;
  try {
    const body: unknown = await request.json();
    if (!isRecord(body)) return jsonResponse(400, { error: "Invalid request body." });
    payload = body;
  } catch {
    return jsonResponse(400, { error: "Invalid JSON request body." });
  }

  const action = payload.action;
  if (typeof action !== "string") {
    return jsonResponse(400, { error: "กรุณาระบุคำสั่งจัดการช่าง" });
  }

  try {
    if (action === "list-technicians") {
      const { data, error } = await supabase
        .from("Maintenance_Users")
        .select("uid, created_at, teamName, username, comment, password, start_time, end_time")
        .order("created_at", { ascending: false });
      if (error) throw error;
      const technicians = await Promise.all(
        (data ?? []).map(async (technician) => ({
          ...technician,
          password: await decryptPassword(technician.password),
        })),
      );
      return jsonResponse(200, { technicians });
    }

    if (action === "list-eligible-teams") {
      const { data, error } = await supabase
        .from("Maintenance_Users")
        .select("teamName, start_time, end_time")
        .eq("status", true)
        .order("teamName", { ascending: true });
      if (error) throw error;

      const today = new Date(Date.now() + 7 * 60 * 60 * 1000)
        .toISOString()
        .slice(0, 10);
      const teamsByName = new Map<
        string,
        { name: string; periods: Map<string, { start: string; end: string }> }
      >();
      for (const technician of data ?? []) {
        if (
          typeof technician.teamName !== "string" ||
          !Array.isArray(technician.start_time) ||
          !Array.isArray(technician.end_time) ||
          technician.start_time.length !== technician.end_time.length
        ) {
          throw new Error("Maintenance team date ranges are invalid.");
        }
        const normalizedName = technician.teamName.trim().toLowerCase();
        if (!normalizedName) {
          throw new Error("Maintenance team name is invalid.");
        }
        let team = teamsByName.get(normalizedName);
        if (!team) {
          team = { name: technician.teamName.trim(), periods: new Map() };
          teamsByName.set(normalizedName, team);
        }
        for (let index = 0; index < technician.start_time.length; index++) {
          const start = bangkokDate(technician.start_time[index]);
          const end = bangkokDate(technician.end_time[index]);
          if (!start || !end || start > end) {
            throw new Error("Maintenance team date range is invalid.");
          }
          if (end >= today) team.periods.set(`${start}/${end}`, { start, end });
        }
      }

      const teams = [...teamsByName.values()]
        .filter((team) => team.periods.size > 0)
        .map((team) => ({
          name: team.name,
          periods: [...team.periods.values()].sort((first, second) =>
            first.start.localeCompare(second.start) ||
            first.end.localeCompare(second.end)
          ),
        }));
      return jsonResponse(200, { teams });
    }

    if (action === "list-technician-tickets") {
      const uid = payload.uid;
      if (!validateTechnicianUid(uid)) {
        return jsonResponse(400, { error: "กรุณาตรวจสอบ UID ของบัญชีช่าง" });
      }

      const ticketIds: string[] = [];
      for (let offset = 0; ; offset += 500) {
        const { data: assignments, error: assignmentsError } = await supabase
          .from(uid)
          .select("ticketId")
          .order("ticketId", { ascending: false })
          .range(offset, offset + 499);
        if (assignmentsError) throw assignmentsError;
        const page = assignments ?? [];
        for (const assignment of page) {
          if (
            typeof assignment.ticketId !== "string" ||
            !/^\d{10}$/.test(assignment.ticketId)
          ) {
            throw new Error(`Invalid ticket ID in technician table ${uid}.`);
          }
          ticketIds.push(assignment.ticketId);
        }
        if (page.length < 500) break;
      }
      if (ticketIds.length === 0) return jsonResponse(200, { tickets: [] });

      const ticketsById = new Map<string, Record<string, unknown>>();
      for (let offset = 0; offset < ticketIds.length; offset += 100) {
        const batch = ticketIds.slice(offset, offset + 100);
        const { data: tickets, error: ticketsError } = await supabase
          .from("FixList")
          .select("TicketId, building, area, floor, room, longtitude, latitude")
          .in("TicketId", batch);
        if (ticketsError) throw ticketsError;
        for (const ticket of tickets ?? []) {
          ticketsById.set(ticket.TicketId, ticket);
        }
      }
      const missingTicketIds = ticketIds.filter((ticketId) =>
        !ticketsById.has(ticketId)
      );
      if (missingTicketIds.length > 0) {
        throw new Error(
          `Assigned tickets are missing from FixList: ${missingTicketIds.join(", ")}.`,
        );
      }
      const tickets: Record<string, unknown>[] = [];
      for (let offset = 0; offset < ticketIds.length; offset += 20) {
        const batch = ticketIds.slice(offset, offset + 20);
        const batchTickets = await Promise.all(
          batch.map(async (ticketId) => {
            const { data: devices, error: deviceError } = await supabase
              .from(ticketId)
              .select("deviceid, device, discription")
              .order("deviceid", { ascending: true })
              .limit(100);
            if (deviceError) {
              console.error(
                `Failed to load devices for ticket ${ticketId}.`,
                deviceError,
              );
              throw new Error(
                `Devices for ticket ${ticketId} could not be loaded.`,
              );
            }
            const { data: photos, error: photosError } = await supabase.storage
              .from(ticketId)
              .list("", { limit: 100 });
            if (photosError) {
              console.error(
                `Failed to list device photos for ticket ${ticketId}.`,
                photosError,
              );
              throw new Error(
                `Device photos for ticket ${ticketId} could not be loaded.`,
              );
            }
            const photoNames = new Set(
              (photos ?? []).map((photo) => photo.name),
            );
            const ticketDevices = await Promise.all(
              (devices ?? []).map(async (device) => {
                const photoName = String(device.deviceid);
                if (!photoNames.has(photoName)) {
                  return { ...device, devicePhotoUrl: null };
                }
                const { data: photo, error: photoError } = await supabase.storage
                  .from(ticketId)
                  .createSignedUrl(photoName, 3600);
                if (photoError) {
                  console.error(
                    `Failed to create a signed URL for device ${photoName} of ticket ${ticketId}.`,
                    photoError,
                  );
                  throw new Error(
                    `Device photo ${photoName} for ticket ${ticketId} could not be loaded.`,
                  );
                }
                return { ...device, devicePhotoUrl: photo.signedUrl };
              }),
            );
            return {
              ...ticketsById.get(ticketId)!,
              devices: ticketDevices,
            };
          }),
        );
        tickets.push(...batchTickets);
      }
      return jsonResponse(200, {
        tickets,
      });
    }

    if (action === "update-assigned-ticket") {
      const uid = payload.uid;
      const ticketId = payload.ticketId;
      const request = payload.request;
      if (!validateTechnicianUid(uid) || typeof ticketId !== "string" ||
        !/^\d{10}$/.test(ticketId) || !isRecord(request)) {
        return jsonResponse(400, { error: "ข้อมูล ticket ไม่ถูกต้อง" });
      }
      const { data: assignment, error: assignmentError } = await supabase
        .from(uid)
        .select("ticketId")
        .eq("ticketId", ticketId)
        .maybeSingle();
      if (assignmentError) throw assignmentError;
      if (!assignment) {
        return jsonResponse(404, { error: "ไม่พบ ticket นี้ในรายการงานของทีมช่าง" });
      }

      const building = request.building;
      const area = request.area;
      const floor = request.floor;
      const room = request.room;
      const latitude = request.latitude;
      const longitude = request.longitude;
      const validRequest =
        typeof building === "string" &&
        (building === "other" || /^\d{1,2}$/.test(building)) &&
        (building === "other"
          ? typeof area === "string" && area.trim().length > 0 &&
            area.trim().length <= 120
          : area == null || area === "") &&
        (floor == null || (typeof floor === "string" &&
          (floor === "" || (/^\d{1,2}$/.test(floor) && Number(floor) <= 50)))) &&
        (room == null || (typeof room === "string" &&
          (room === "" || /^[a-zA-Z0-9-]{1,8}$/.test(room)))) &&
        typeof latitude === "number" && Number.isFinite(latitude) &&
        latitude >= -90 && latitude <= 90 &&
        typeof longitude === "number" && Number.isFinite(longitude) &&
        longitude >= -180 && longitude <= 180;
      if (!validRequest) {
        return jsonResponse(400, { error: "กรุณาตรวจสอบข้อมูลอาคาร ห้อง และพิกัด" });
      }

      const { data: updatedTicket, error: updateError } = await supabase
        .from("FixList")
        .update({
          building,
          area: building === "other" ? (area as string).trim() : null,
          floor: typeof floor === "string" && floor.trim() ? floor.trim() : null,
          room: typeof room === "string" && room.trim() ? room.trim() : null,
          latitude,
          longtitude: longitude,
        })
        .eq("TicketId", ticketId)
        .select("TicketId")
        .maybeSingle();
      if (updateError) throw updateError;
      if (!updatedTicket) {
        return jsonResponse(404, { error: "ไม่พบ ticket ใน FixList" });
      }
      return jsonResponse(200, { updated: true });
    }

    if (action === "update-assigned-device") {
      const uid = payload.uid;
      const ticketId = payload.ticketId;
      const deviceId = payload.deviceId;
      const request = payload.request;
      if (!validateTechnicianUid(uid) || typeof ticketId !== "string" ||
        !/^\d{10}$/.test(ticketId) || typeof deviceId !== "number" ||
        !Number.isInteger(deviceId) || deviceId < 1 || !isRecord(request)) {
        return jsonResponse(400, { error: "ข้อมูลอุปกรณ์ไม่ถูกต้อง" });
      }
      const { data: assignment, error: assignmentError } = await supabase
        .from(uid)
        .select("ticketId")
        .eq("ticketId", ticketId)
        .maybeSingle();
      if (assignmentError) throw assignmentError;
      if (!assignment) {
        return jsonResponse(404, { error: "ไม่พบ ticket นี้ในรายการงานของทีมช่าง" });
      }

      const device = request.device;
      const description = request.description;
      if (typeof device !== "string" || device.length > 500 ||
        typeof description !== "string" || description.length > 5000) {
        return jsonResponse(400, { error: "กรุณาตรวจสอบชื่ออุปกรณ์และคำอธิบาย" });
      }
      const { data: updatedDevice, error: updateError } = await supabase
        .from(ticketId)
        .update({
          device: device.trim() || null,
          discription: description.trim() || null,
        })
        .eq("deviceid", deviceId)
        .select("deviceid")
        .maybeSingle();
      if (updateError) throw updateError;
      if (!updatedDevice) {
        return jsonResponse(404, { error: "ไม่พบรายการอุปกรณ์ของ ticket นี้" });
      }
      return jsonResponse(200, { updated: true });
    }

    if (action === "remove-assigned-ticket") {
      const uid = payload.uid;
      const ticketId = payload.ticketId;
      if (!validateTechnicianUid(uid) || typeof ticketId !== "string" ||
        !/^\d{10}$/.test(ticketId)) {
        return jsonResponse(400, { error: "ข้อมูล ticket ไม่ถูกต้อง" });
      }
      const { data: removedAssignments, error: removeError } = await supabase
        .from(uid)
        .delete()
        .eq("ticketId", ticketId)
        .select("ticketId");
      if (removeError) throw removeError;
      if (!removedAssignments || removedAssignments.length !== 1) {
        return jsonResponse(404, { error: "ไม่พบ ticket นี้ในรายการงานของทีมช่าง" });
      }
      return jsonResponse(200, { removed: true });
    }

    if (action === "create-technician") {
      const teamName = typeof payload.teamName === "string"
        ? payload.teamName.trim()
        : "";
      const username = typeof payload.username === "string"
        ? payload.username.trim()
        : "";
      const comment = typeof payload.comment === "string"
        ? payload.comment.trim()
        : "";
      if (!teamName || teamName.length > 100) {
        return jsonResponse(400, { error: "กรุณากรอกชื่อช่างไม่เกิน 100 ตัวอักษร" });
      }
      if (!/^[A-Za-z0-9_]{3,10}$/.test(username)) {
        return jsonResponse(400, { error: "username ต้องมี 3-10 ตัวอักษร และใช้ได้เฉพาะ A-Z, a-z, 0-9 หรือ _" });
      }
      if (!comment) {
        return jsonResponse(400, { error: "กรุณากรอกข้อมูลช่าง" });
      }
      if (comment.length > 1000) {
        return jsonResponse(400, { error: "ข้อมูลช่างต้องไม่เกิน 1,000 ตัวอักษร" });
      }
      const password = generateRandomString(10);
      const technicianUid = generateRandomTechnicianUid();
      const encryptedPassword = await encryptPassword(password);
      const { data: resolvedUid, error } = await supabase.rpc(
        "create_maintenance_technician",
        {
          p_technician_uid: technicianUid,
          p_team_name: teamName,
          p_username: username,
          p_password: password,
          p_encrypted_password: encryptedPassword,
          p_comment: comment,
        },
      );
      const duplicateMessage = duplicateValueMessage(error);
      if (duplicateMessage) {
        return jsonResponse(409, { error: duplicateMessage });
      }
      if (error) throw error;
      if (!validateTechnicianUid(resolvedUid)) {
        throw new Error("Technician creation returned an invalid UID.");
      }
      return jsonResponse(200, {
        uid: resolvedUid,
        username,
        password,
      });
    }

    if (action === "update-technician") {
      const uid = payload.uid;
      if (!validateTechnicianUid(uid)) {
        return jsonResponse(400, { error: "กรุณาตรวจสอบ UID ของบัญชีช่าง" });
      }

      const update: Record<string, unknown> = {};
      const hasUsernameUpdate = "username" in payload;
      if (hasUsernameUpdate) {
        const username = typeof payload.username === "string"
          ? payload.username.trim()
          : "";
        if (!/^[A-Za-z0-9_]{3,10}$/.test(username)) {
          return jsonResponse(400, {
            error: "username ต้องมี 3-10 ตัวอักษร และใช้ได้เฉพาะ A-Z, a-z, 0-9 หรือ _",
          });
        }
        const { data, error } = await supabase.rpc(
          "update_maintenance_technician_username",
          { p_technician_uid: uid, p_username: username },
        );
        if (error) throw error;
        if (data !== true) {
          return jsonResponse(404, { error: "ไม่พบบัญชีช่างที่ต้องการแก้ไข" });
        }
      }
      if ("teamName" in payload) {
        const teamName = typeof payload.teamName === "string"
          ? payload.teamName.trim()
          : "";
        if (!teamName || teamName.length > 100) {
          return jsonResponse(400, { error: "กรุณากรอกชื่อช่างไม่เกิน 100 ตัวอักษร" });
        }
        update.teamName = teamName;
      }
      if ("comment" in payload) {
        const comment = typeof payload.comment === "string"
          ? payload.comment.trim()
          : "";
        if (!comment) {
          return jsonResponse(400, { error: "กรุณากรอกข้อมูลช่าง" });
        }
        if (comment.length > 1000) {
          return jsonResponse(400, { error: "ข้อมูลช่างต้องไม่เกิน 1,000 ตัวอักษร" });
        }
        update.comment = comment;
      }
      if ("dateRanges" in payload) {
        const dateRanges = validateDateRanges(payload.dateRanges);
        if (!dateRanges) {
          return jsonResponse(400, {
            error: "ช่วงวันที่ต้องเริ่มตั้งแต่วันนี้ วันสิ้นสุดต้องไม่น้อยกว่าวันเริ่มต้น และห้ามซ้ำหรือทับซ้อนกัน",
          });
        }
        update.start_time = dateRanges.starts;
        update.end_time = dateRanges.ends;
      }
      if (Object.keys(update).length === 0 && !hasUsernameUpdate) {
        return jsonResponse(400, { error: "ไม่มีข้อมูลที่ต้องการแก้ไข" });
      }
      if (Object.keys(update).length === 0) {
        return jsonResponse(200, { success: true });
      }
      const { data, error } = await supabase
        .from("Maintenance_Users")
        .update(update)
        .eq("uid", uid)
        .select("uid")
        .maybeSingle();
      if (error) throw error;
      if (!data) return jsonResponse(404, { error: "ไม่พบบัญชีช่างที่ต้องการแก้ไข" });
      return jsonResponse(200, { success: true });
    }

    if (action === "delete-technician") {
      const uid = payload.uid;
      if (!validateTechnicianUid(uid)) {
        return jsonResponse(400, { error: "กรุณาตรวจสอบ UID ของบัญชีช่าง" });
      }
      const { data, error } = await supabase.rpc(
        "delete_maintenance_technician",
        { p_technician_uid: uid },
      );
      if (error) {
        if (
          typeof error.message === "string" &&
          error.message.includes("ACTIVE_JOBS_EXIST")
        ) {
          const cleanMessage = error.message.replace(
            /^.*?ACTIVE_JOBS_EXIST:\s*/,
            "",
          );
          return jsonResponse(400, { error: cleanMessage });
        }
        throw error;
      }
      if (data !== true) {
        return jsonResponse(404, { error: "ไม่พบบัญชีช่างที่ต้องการลบ" });
      }
      return jsonResponse(200, { deleted: true });
    }

    return jsonResponse(400, { error: "ไม่รู้จักคำสั่งจัดการช่างนี้" });
  } catch (error) {
    const referenceId = crypto.randomUUID();
    if (isRecord(error)) {
      console.error("Maintenance technician operation failed.", {
        referenceId,
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      });
    } else {
      console.error("Maintenance technician operation failed.", {
        referenceId,
        message: String(error),
      });
    }
    const duplicateMessage = duplicateValueMessage(error);
    if (duplicateMessage) {
      return jsonResponse(409, { error: duplicateMessage });
    }
    return jsonResponse(500, {
      error: `บันทึกข้อมูลช่างไม่สำเร็จ กรุณาลองใหม่อีกครั้ง หากยังพบปัญหาให้แจ้งรหัสอ้างอิง ${referenceId}`,
      referenceId,
    });
  }
});
