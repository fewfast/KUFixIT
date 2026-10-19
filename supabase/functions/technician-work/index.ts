import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { verifyTemporarySession } from "../_shared/credentials.ts";
import { getSupabaseAdminKey } from "../_shared/supabase_admin_key.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const bucketName = "technician-work-results";
const maxPhotoBytes = 2 * 1024 * 1024;
const maxRequestBytes = 32_000_000;
const photoTypes = new Map([
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
  ["image/webp", "webp"],
]);

type RecordValue = Record<string, unknown>;
type Identity = {
  role: string;
  username: string;
  technicianUid?: string;
};
type Photo = {
  bytes: Uint8Array;
  contentType: string;
  extension: string;
};

function jsonResponse(status: number, body: RecordValue) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function expireOverdueTicketsSilently(supabase: SupabaseClient) {
  try {
    await supabase.rpc("check_and_expire_overdue_tickets");
  } catch (error) {
    console.error("Failed to run check_and_expire_overdue_tickets:", error);
  }
}

function isRecord(value: unknown): value is RecordValue {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function bangkokDate(value: string): string | null {
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) return null;
  return new Date(milliseconds + 7 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function activeWorkPeriod(
  value: RecordValue | null,
): { start: string; end: string } | null {
  if (
    !value ||
    !Array.isArray(value.start_time) ||
    !Array.isArray(value.end_time) ||
    value.start_time.length !== value.end_time.length
  )
    return null;

  const today = bangkokDate(new Date().toISOString());
  if (!today) return null;
  for (let index = 0; index < value.start_time.length; index++) {
    const start = value.start_time[index];
    const end = value.end_time[index];
    if (typeof start !== "string" || typeof end !== "string") continue;
    const startDate = bangkokDate(start);
    const endDate = bangkokDate(end);
    if (startDate && endDate && startDate <= today && endDate >= today) {
      return { start, end };
    }
  }
  return null;
}

async function readLimitedJson(request: Request): Promise<unknown> {
  const contentLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > maxRequestBytes) {
    throw new RangeError("Request is too large.");
  }
  if (!request.body) throw new SyntaxError("Missing request body.");

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxRequestBytes) {
      await reader.cancel();
      throw new RangeError("Request is too large.");
    }
    chunks.push(value);
  }
  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(new TextDecoder().decode(body));
}

function decodePhoto(payload: RecordValue): Photo | null {
  const rawBase64 = payload.photoBase64;
  if (rawBase64 === undefined || rawBase64 === null || rawBase64 === "") {
    if (
      payload.photoContentType !== undefined ||
      payload.photoName !== undefined
    ) {
      throw new TypeError("Photo metadata requires a photo.");
    }
    return null;
  }
  if (typeof rawBase64 !== "string" || rawBase64.length > 2_800_000) {
    throw new TypeError("Invalid photo data.");
  }

  let encoded = rawBase64;
  let dataUrlType: string | undefined;
  const dataUrlMatch = rawBase64.match(
    /^data:(image\/[a-zA-Z0-9.+-]+);base64,(.*)$/s,
  );
  if (dataUrlMatch) {
    dataUrlType = dataUrlMatch[1].toLowerCase();
    encoded = dataUrlMatch[2];
  } else if (rawBase64.startsWith("data:")) {
    throw new TypeError("Invalid photo data URL.");
  }
  if (
    !encoded ||
    encoded.length % 4 !== 0 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
      encoded,
    )
  ) {
    throw new TypeError("Invalid photo encoding.");
  }

  const binary = atob(encoded);
  if (binary.length === 0 || binary.length > maxPhotoBytes) {
    throw new RangeError("Photo must not exceed 2 MB.");
  }
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  const detectedType =
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff
      ? "image/jpeg"
      : bytes.length >= 8 &&
          bytes[0] === 0x89 &&
          bytes[1] === 0x50 &&
          bytes[2] === 0x4e &&
          bytes[3] === 0x47 &&
          bytes[4] === 0x0d &&
          bytes[5] === 0x0a &&
          bytes[6] === 0x1a &&
          bytes[7] === 0x0a
        ? "image/png"
        : bytes.length >= 12 &&
            bytes[0] === 0x52 &&
            bytes[1] === 0x49 &&
            bytes[2] === 0x46 &&
            bytes[3] === 0x46 &&
            bytes[8] === 0x57 &&
            bytes[9] === 0x45 &&
            bytes[10] === 0x42 &&
            bytes[11] === 0x50
          ? "image/webp"
          : null;
  const requestedType = payload.photoContentType;
  if (requestedType !== undefined && typeof requestedType !== "string") {
    throw new TypeError("Invalid photo content type.");
  }
  const contentType =
    typeof requestedType === "string"
      ? requestedType.toLowerCase().split(";")[0].trim()
      : (dataUrlType ?? detectedType);
  if (
    !contentType ||
    !photoTypes.has(contentType) ||
    contentType !== detectedType ||
    (dataUrlType !== undefined && dataUrlType !== contentType)
  ) {
    throw new TypeError("Photo must be valid JPEG, PNG, or WebP data.");
  }
  const name = payload.photoName;
  if (
    name !== undefined &&
    (typeof name !== "string" ||
      name.length > 128 ||
      /[\u0000-\u001f\u007f]/.test(name))
  ) {
    throw new TypeError("Invalid photo name.");
  }
  return { bytes, contentType, extension: photoTypes.get(contentType)! };
}

function cleanPhotoName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const name = value.split(/[\\/]/).pop()?.trim() ?? "";
  return name ? name.slice(0, 128) : null;
}

async function requireIdentity(
  supabase: SupabaseClient,
  claims: RecordValue,
): Promise<Identity | null> {
  if (typeof claims.sub !== "string" || typeof claims.role !== "string") {
    return null;
  }
  const role = claims.role;
  if (role === "Technician") {
    if (
      claims.username !== claims.sub ||
      !/^[A-Za-z0-9_]{3,64}$/.test(claims.sub)
    )
      return null;

    const [
      { data: systemAccount, error: systemError },
      { data: technician, error: technicianError },
    ] = await Promise.all([
      supabase
        .from("Systems_Users")
        .select("role, endtime")
        .eq("Username", claims.sub)
        .maybeSingle(),
      supabase
        .from("Maintenance_Users")
        .select("uid, username, status")
        .eq("username", claims.sub)
        .maybeSingle(),
    ]);
    if (systemError || technicianError) throw systemError ?? technicianError;
    if (
      !systemAccount ||
      systemAccount.role !== "Technician" ||
      (systemAccount.endtime !== null &&
        (typeof systemAccount.endtime !== "string" ||
          Date.parse(systemAccount.endtime) <= Date.now())) ||
      !technician ||
      technician.status !== true ||
      typeof technician.uid !== "string" ||
      !/^t_[0-9]{10}$/.test(technician.uid) ||
      typeof technician.username !== "string" ||
      technician.username.toLowerCase() !== claims.sub.toLowerCase()
    )
      return null;
    return { role, username: claims.sub, technicianUid: technician.uid };
  }

  if (role !== "Admin" && role !== "SuperAdmin") return null;
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
  const validSystemAccount =
    isSystemAccount &&
    account !== null &&
    "endtime" in account &&
    ["Admin", "SuperAdmin"].includes(String(account.role)) &&
    (account.endtime === null ||
      (typeof account.endtime === "string" &&
        Date.parse(account.endtime) > Date.now()));
  const validGoogleAccount =
    !isSystemAccount &&
    account !== null &&
    "status" in account &&
    ["Admin", "SuperAdmin"].includes(String(account.role)) &&
    account.status === "active";
  if (!(isSystemAccount ? validSystemAccount : validGoogleAccount)) return null;
  return { role, username: claims.username === claims.sub ? claims.sub : "" };
}

async function signedPhotoUrl(
  supabase: SupabaseClient,
  path: unknown,
): Promise<string | null> {
  if (typeof path !== "string") return null;
  const { data, error } = await supabase.storage
    .from(bucketName)
    .createSignedUrl(path, 60 * 60);
  if (error || !data?.signedUrl)
    throw error ?? new Error("Unable to sign report photo.");
  return data.signedUrl;
}

async function signedDeviceResults(
  supabase: SupabaseClient,
  value: unknown,
) {
  if (!Array.isArray(value)) throw new Error("Invalid report device results.");
  return Promise.all(value.map(async (entry) => {
    if (!isRecord(entry) ||
      !Number.isSafeInteger(entry.deviceid) ||
      !Number.isSafeInteger(entry.row_index) ||
      typeof entry.success !== "boolean") {
      throw new Error("Invalid report device result.");
    }
    const photoPath = typeof entry.photo_path === "string"
      ? entry.photo_path
      : null;
    return {
      deviceid: entry.deviceid,
      row_index: entry.row_index,
      success: entry.success,
      photoUrl: await signedPhotoUrl(supabase, photoPath),
    };
  }));
}

async function listTechnicianTickets(
  supabase: SupabaseClient,
  technicianUid: string,
) {
  const assignedTicketIds = new Set<string>();
  for (let offset = 0; ; offset += 500) {
    const { data: page, error: assignmentError } = await supabase
      .from(technicianUid)
      .select("ticketId")
      .order("ticketId", { ascending: false })
      .range(offset, offset + 499);
    if (assignmentError) throw assignmentError;
    for (const assignment of page ?? []) {
      if (
        typeof assignment.ticketId !== "string" ||
        !/^[0-9]{10}$/.test(assignment.ticketId)
      ) {
        throw new Error("Invalid ticket assignment.");
      }
      assignedTicketIds.add(assignment.ticketId);
    }
    if (!page || page.length < 500) break;
  }

  const tickets = [];
  for (const ticketId of assignedTicketIds) {
    const reportQuery = supabase
      .from("technician_work_reports")
      .select("id, outcome, status, comment, submitted_at, photo_path, device_results")
      .eq("TicketId", ticketId);
    const latestReportsQuery = reportQuery
      .order("submitted_at", { ascending: false })
      .limit(1);
    const [
      { data: ticket, error: ticketError },
      { data: devices, error: deviceError },
      { data: latestReports, error: reportError },
    ] = await Promise.all([
      supabase
        .from("FixList")
        .select(
          "TicketId, building, area, floor, room, latitude, longtitude, status",
        )
        .eq("TicketId", ticketId)
        .maybeSingle(),
      supabase
        .from(ticketId)
        .select("deviceid, device, discription, status")
        .order("deviceid", { ascending: true }),
      latestReportsQuery,
    ]);
    if (ticketError || deviceError || reportError) {
      throw ticketError ?? deviceError ?? reportError;
    }
    if (!ticket) throw new Error("Assigned ticket was not found.");
    const latest = latestReports?.[0];
    const visibleDevices = (devices ?? [])
      .map((device, index) => ({ ...device, row_index: index + 1 }))
      .filter((device) => device.status === "pending");
    if (visibleDevices.length === 0) continue;
    const report =
      latest && latest.status !== "rejected"
        ? {
            id: latest.id,
            outcome: latest.outcome,
            status: latest.status,
            comment: latest.comment,
            submitted_at: latest.submitted_at,
            photoUrl: await signedPhotoUrl(supabase, latest.photo_path),
            deviceResults: await signedDeviceResults(
              supabase,
              latest.device_results,
            ),
          }
        : null;
    tickets.push({ ...ticket, devices: visibleDevices, report });
  }
  return { tickets };
}

async function submitReport(
  supabase: SupabaseClient,
  identity: { role: string; username: string; technicianUid: string },
  payload: RecordValue,
) {
  const uid = identity.technicianUid;
  const ticketId = payload.ticketId;
  if (typeof ticketId !== "string" || !/^[0-9]{10}$/.test(ticketId)) {
    return jsonResponse(400, { error: "Invalid ticketId." });
  }
  const comment = payload.comment === undefined ? null : payload.comment;
  if (
    comment !== null &&
    (typeof comment !== "string" || comment.length > 5000)
  ) {
    return jsonResponse(400, { error: "Invalid comment." });
  }
  const rawResults = payload.deviceResults;
  if (!Array.isArray(rawResults) || rawResults.length === 0 ||
    rawResults.length > 200) {
    return jsonResponse(400, { error: "Invalid device result list." });
  }

  const [
    { data: assignment, error: assignmentError },
    { data: ticket, error: ticketError },
    { data: technician, error: technicianError },
    { data: devices, error: deviceError },
  ] = await Promise.all([
    supabase
      .from(uid)
      .select("ticketId")
      .eq("ticketId", ticketId)
      .maybeSingle(),
    supabase
      .from("FixList")
      .select("status")
      .eq("TicketId", ticketId)
      .maybeSingle(),
    supabase
      .from("Maintenance_Users")
      .select("start_time, end_time")
      .eq("uid", uid)
      .maybeSingle(),
    supabase
      .from(ticketId)
      .select("deviceid, status")
      .order("deviceid", { ascending: true }),
  ]);
  if (assignmentError || ticketError || technicianError || deviceError) {
    throw assignmentError ?? ticketError ?? technicianError ?? deviceError;
  }
  if (!assignment)
    return jsonResponse(403, {
      error: "Ticket is not assigned to this technician.",
    });
  if (!ticket || ticket.status === "finish") {
    return jsonResponse(409, { error: "This ticket is already finished." });
  }
  const pendingDevices = (devices ?? [])
    .map((device, index) => ({ ...device, row_index: index + 1 }))
    .filter((device) => device.status === "pending");
  if (pendingDevices.length !== rawResults.length) {
    return jsonResponse(409, {
      error: "Report every pending device exactly once.",
    });
  }

  const results = [];
  const seenDeviceIds = new Set<number>();
  let successCount = 0;
  const reportId = crypto.randomUUID();
  for (let index = 0; index < rawResults.length; index++) {
    const raw = rawResults[index];
    if (!isRecord(raw) ||
      !Number.isSafeInteger(raw.deviceid) ||
      !Number.isSafeInteger(raw.row_index) ||
      typeof raw.success !== "boolean") {
      return jsonResponse(400, { error: "Invalid device result." });
    }
    const device = pendingDevices[index];
    const deviceId = raw.deviceid as number;
    const success = raw.success;
    const rowIndex = raw.row_index as number;
    if (device.deviceid !== deviceId ||
      device.row_index !== rowIndex ||
      seenDeviceIds.has(deviceId)) {
      return jsonResponse(409, {
        error: "Report device rows do not match the current ticket.",
      });
    }
    seenDeviceIds.add(deviceId);
    if (success) successCount++;

    let photo: Photo | null;
    try {
      photo = decodePhoto(raw);
    } catch (error) {
      return jsonResponse(error instanceof RangeError ? 413 : 400, {
        error: error instanceof Error ? error.message : "Invalid photo.",
      });
    }
    if (success && !photo) {
      return jsonResponse(400, {
        error: "Each successful device requires one result photo.",
      });
    }
    if (!success && photo) {
      return jsonResponse(400, {
        error: "Unsuccessful devices cannot include a result photo.",
      });
    }
    results.push({
      deviceId,
      rowIndex,
      success,
      photo,
      photoName: photo ? cleanPhotoName(raw.photoName) : null,
    });
  }

  if (successCount > 0 && successCount < results.length &&
    (typeof comment !== "string" || comment.trim().length === 0)) {
    return jsonResponse(400, {
      error: "A comment is required when a device was not repaired.",
    });
  }
  const workPeriod = activeWorkPeriod(technician);
  if (!workPeriod) {
    return jsonResponse(403, {
      error: "Technician has no active work period.",
    });
  }

  const uploadedPaths: string[] = [];
  const deviceResults = [];
  try {
    for (const result of results) {
      const photoPath = result.photo
        ? `${ticketId}/${uid}/${reportId}/${result.rowIndex}.${result.photo.extension}`
        : null;
      if (result.photo && photoPath) {
        uploadedPaths.push(photoPath);
        const { error: uploadError } = await supabase.storage
          .from(bucketName)
          .upload(photoPath, result.photo.bytes, {
            contentType: result.photo.contentType,
            upsert: false,
          });
        if (uploadError) throw uploadError;
      }
      deviceResults.push({
        deviceid: result.deviceId,
        row_index: result.rowIndex,
        success: result.success,
        photo_path: photoPath,
        photo_size: result.photo?.bytes.length ?? null,
        photo_name: result.photoName,
      });
    }

    const { error: insertError } = await supabase.rpc(
      "create_technician_work_report",
      {
        p_report_id: reportId,
        p_ticket_id: ticketId,
        p_technician_uid: uid,
        p_comment: successCount === 0
          ? "ซ่อมไม่สำเร็จ"
          : typeof comment === "string" ? comment.trim() || null : null,
        p_work_period_start: workPeriod.start,
        p_work_period_end: workPeriod.end,
        p_device_results: deviceResults,
      },
    );
    if (insertError) throw insertError;

    const { data: techUser } = await supabase
      .from("Maintenance_Users")
      .select("teamName, username")
      .eq("uid", identity.technicianUid)
      .maybeSingle();

    const teamName = techUser?.teamName ?? "techteam";

    const { error: logError } = await supabase.from("activity_logs").insert({
      actor_username: identity.username,
      actor_role: "Technician",
      actor_display_name: `ทีมช่าง ${teamName}`,
      action_type: "TECH_SUBMIT",
      action_title: "ส่งงานช่าง",
      description: `ส่งรายงานผลการซ่อม Ticket #${ticketId}`,
      target_id: ticketId,
      metadata: {
        uid: identity.technicianUid,
        team: teamName,
      },
      created_at: new Date().toISOString(),
    });
    if (logError) {
      console.error("Failed to insert technician activity log:", logError);
    }
  } catch (error) {
    // A network timeout can happen after the database committed the report.
    // Keep its photos if that commit is visible to the service-role client.
    const { data: committedReport, error: lookupError } = await supabase
      .from("technician_work_reports")
      .select("id")
      .eq("id", reportId)
      .maybeSingle();
    if (!lookupError && committedReport?.id === reportId) {
      return jsonResponse(200, { submitted: true });
    }
    if (lookupError) {
      console.error("Unable to determine report submission outcome.");
      return jsonResponse(503, {
        error: "Report status is being checked. Reload the work list shortly.",
      });
    }
    if (uploadedPaths.length > 0) {
      const { error: cleanupError } = await supabase.storage
        .from(bucketName)
        .remove(uploadedPaths);
      if (cleanupError) {
        console.error("Failed to clean up an incomplete report upload.");
      }
    }
    if (isRecord(error) && error.code === "23505") {
      return jsonResponse(409, {
        error: "A report is already under review for this ticket.",
      });
    }
    if (isRecord(error) && error.code === "P0001") {
      return jsonResponse(409, {
        error: "The assignment or device list changed. Submit the report again.",
      });
    }
    throw error;
  }
  return jsonResponse(200, { submitted: true });
}

async function listReports(supabase: SupabaseClient) {
  const reports = [];
  for (let offset = 0; ; offset += 500) {
    const { data: page, error } = await supabase
      .from("technician_work_reports")
      .select(
        "id, TicketId, technicianUid, outcome, comment, submitted_at, photo_path, device_results",
      )
      .eq("status", "under_review")
      .order("submitted_at", { ascending: true })
      .range(offset, offset + 499);
    if (error) throw error;
    reports.push(...(page ?? []));
    if (!page || page.length < 500) break;
  }
  const output = [];
  for (const report of reports) {
    const [
      { data: ticket, error: ticketError },
      { data: technician, error: technicianError },
    ] = await Promise.all([
      supabase
        .from("FixList")
        .select(
          "TicketId, building, area, floor, room, latitude, longtitude, status",
        )
        .eq("TicketId", report.TicketId)
        .maybeSingle(),
      supabase
        .from("Maintenance_Users")
        .select("teamName, username")
        .eq("uid", report.technicianUid)
        .maybeSingle(),
    ]);
    if (ticketError || technicianError) throw ticketError ?? technicianError;
    if (!ticket) throw new Error("Report ticket was not found.");
    output.push({
      id: report.id,
      ...ticket,
      technicianUid: report.technicianUid,
      technicianName:
        technician?.teamName ?? technician?.username ?? report.technicianUid,
      outcome: report.outcome,
      comment: report.comment,
      submitted_at: report.submitted_at,
      photoUrl: await signedPhotoUrl(supabase, report.photo_path),
      deviceResults: await signedDeviceResults(
        supabase,
        report.device_results,
      ),
    });
  }
  return { reports: output };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed." });
  }

  let supabaseUrl: string | undefined;
  let serviceRoleKey: string | undefined;
  try {
    supabaseUrl = Deno.env.get("SUPABASE_URL");
    serviceRoleKey = getSupabaseAdminKey();
  } catch (error) {
    console.error(
      "Failed to load technician work-report configuration.",
      error,
    );
    return jsonResponse(500, {
      error: "Work-report service is not configured.",
    });
  }
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(500, {
      error: "Work-report service is not configured.",
    });
  }
  const token = request.headers
    .get("authorization")
    ?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token)
    return jsonResponse(401, { error: "Authentication is required." });
  const claims = await verifyTemporarySession(token, serviceRoleKey);
  if (!claims)
    return jsonResponse(401, { error: "Invalid or expired session." });

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  try {
    const identity = await requireIdentity(supabase, claims);
    if (!identity)
      return jsonResponse(403, { error: "This action is not allowed." });

    await expireOverdueTicketsSilently(supabase);

    let body: unknown;
    try {
      body = await readLimitedJson(request);
    } catch (error) {
      return jsonResponse(error instanceof RangeError ? 413 : 400, {
        error:
          error instanceof RangeError
            ? "Request body is too large."
            : "Invalid JSON request body.",
      });
    }
    if (!isRecord(body) || typeof body.action !== "string") {
      return jsonResponse(400, { error: "A valid action is required." });
    }
    const action = body.action;
    if (action === "list-technician-tickets") {
      if (identity.role !== "Technician" || !identity.technicianUid) {
        return jsonResponse(403, {
          error: "This action is for technicians only.",
        });
      }
      return jsonResponse(
        200,
        await listTechnicianTickets(supabase, identity.technicianUid),
      );
    }
    if (action === "submit-report") {
      if (identity.role !== "Technician" || !identity.technicianUid) {
        return jsonResponse(403, {
          error: "This action is for technicians only.",
        });
      }
      return await submitReport(
        supabase,
        identity as { role: string; username: string; technicianUid: string },
        body,
      );
    }
    if (action === "admin-list-reports") {
      if (identity.role !== "Admin" && identity.role !== "SuperAdmin") {
        return jsonResponse(403, {
          error: "This action is for administrators only.",
        });
      }
      return jsonResponse(200, await listReports(supabase));
    }
    if (action === "admin-review-report") {
      if (identity.role !== "Admin" && identity.role !== "SuperAdmin") {
        return jsonResponse(403, {
          error: "This action is for administrators only.",
        });
      }
      if (
        typeof body.reportId !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
          body.reportId,
        ) ||
        (body.decision !== "approve" && body.decision !== "reject")
      ) {
        return jsonResponse(400, { error: "Invalid report review request." });
      }

      const { data: reportData } = await supabase
        .from("technician_work_reports")
        .select('"TicketId"')
        .eq("id", body.reportId)
        .maybeSingle();
      const reportTicketId = reportData?.TicketId ?? "";

      const { error } = await supabase.rpc(
        "admin_review_technician_work_report",
        {
          p_report_id: body.reportId,
          p_decision: body.decision,
        },
      );
      if (error) {
        if (error.code === "P0001") {
          return jsonResponse(409, {
            error: "Report is no longer awaiting review.",
          });
        }
        console.error("admin_review_technician_work_report RPC failed:", error);
        return jsonResponse(500, {
          error: `RPC failed: ${error.message} (${error.code || "unknown"})`,
          details: error.details,
          hint: error.hint,
        });
      }

      let adminDisplayName = typeof claims.username === "string" && claims.username
        ? claims.username
        : String(claims.sub);
      let adminUid = String(claims.sub);

      const { data: adminUser } = await supabase
        .from("Users")
        .select('uid, "Display Name"')
        .eq("google_auth_user_id", claims.sub)
        .maybeSingle();

      if (adminUser) {
        adminDisplayName = adminUser["Display Name"] || adminDisplayName;
        adminUid = adminUser.uid || adminUid;
      }

      const { error: logError } = await supabase.from("activity_logs").insert({
        actor_username: adminUser?.uid ?? (typeof claims.username === "string" ? claims.username : String(claims.sub)),
        actor_role: identity.role === "SuperAdmin" ? "SuperAdmin" : "Admin",
        actor_display_name: adminDisplayName,
        action_type: body.decision === "approve" ? "REPORT_APPROVE" : "REPORT_REJECT",
        action_title: body.decision === "approve" ? "อนุมัติงานช่าง" : "ปฏิเสธงานช่าง",
        description: `${body.decision === "approve" ? "อนุมัติ" : "ปฏิเสธ"}รายงานผลการซ่อม Ticket #${reportTicketId}`,
        target_id: reportTicketId,
        metadata: {
          uid: adminUid,
        },
        created_at: new Date().toISOString(),
      });
      if (logError) {
        console.error("Failed to insert admin review activity log:", logError);
      }

      return jsonResponse(200, { reviewed: true });
    }
    return jsonResponse(400, { error: "Unsupported action." });
  } catch (error) {
    console.error("Technician work request failed.", error);
    const message = error instanceof Error
      ? error.message
      : typeof error === "object" && error !== null && "message" in error
      ? String((error as { message: unknown }).message)
      : String(error);
    return jsonResponse(500, {
      error: `Work-report request failed: ${message}`,
    });
  }
});
