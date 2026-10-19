import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import {
  accessPeriodContainsSchedule,
  classifyAssignmentRpcFailure,
  validatePendingTicketUpdate,
} from "./admin_ticket_update_contract.ts";
import { verifyTemporarySession } from "../_shared/credentials.ts";
import { getSupabaseAdminKey } from "../_shared/supabase_admin_key.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const technicianWorkBucket = "technician-work-results";

function jsonResponse(status: number, body: Record<string, unknown>) {
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

const ticketStatusOrder: Record<string, number> = {
  pending: 0,
  validating: 1,
  finish: 2,
  rejected: 3,
  cancel: 4,
};

type TicketRow = {
  TicketId: string;
  request_date: string;
  status: string;
  building: string;
  latitude?: number;
  longtitude?: number;
  area: string | null;
  floor: string | null;
  room: string | null;
  fix_history_time_start?: string[] | null;
  fix_history_time_end?: string[] | null;
  next_fix_date_start?: string | null;
  next_fix_date_end?: string | null;
};

const ticketSortColumns = [
  "TicketId",
  "request_date",
  "next_fix_date",
  "status",
];

function sortTickets<T extends TicketRow>(
  tickets: T[],
  sortBy: string,
  ascending: boolean,
): T[] {
  return [...tickets].sort((first, second) => {
    let valueOrder: number;
    if (sortBy === "status") {
      valueOrder =
        (ticketStatusOrder[first.status] ?? Number.MAX_SAFE_INTEGER) -
        (ticketStatusOrder[second.status] ?? Number.MAX_SAFE_INTEGER);
      if (!ascending) valueOrder *= -1;
    } else {
      const firstValue = sortBy === "next_fix_date"
        ? first.next_fix_date_start
        : first[sortBy as keyof TicketRow];
      const secondValue = sortBy === "next_fix_date"
        ? second.next_fix_date_start
        : second[sortBy as keyof TicketRow];
      if (firstValue == null && secondValue != null) return 1;
      if (firstValue != null && secondValue == null) return -1;
      if (firstValue == null || secondValue == null) {
        valueOrder = 0;
      } else if (sortBy === "request_date") {
        valueOrder =
          (Date.parse(firstValue as string) -
            Date.parse(secondValue as string)) *
          (ascending ? 1 : -1);
      } else {
        valueOrder =
          String(firstValue).localeCompare(String(secondValue), undefined, {
            numeric: true,
            sensitivity: "base",
          }) * (ascending ? 1 : -1);
      }
    }
    if (valueOrder !== 0) return valueOrder;
    const dateOrder =
      Date.parse(second.request_date) - Date.parse(first.request_date);
    return dateOrder || second.TicketId.localeCompare(first.TicketId);
  });
}

async function requesterUid(
  token: string,
  supabase: SupabaseClient,
  signingSecret: string,
): Promise<string | null> {
  const claims = await verifyTemporarySession(token, signingSecret);
  let subject: string;
  if (
    claims &&
    typeof claims.sub === "string" &&
    ["User", "Admin"].includes(String(claims.role))
  ) {
    subject = claims.sub;
  } else {
    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data.user) return null;
    subject = data.user.id;
    if (
      data.user.app_metadata.role != null &&
      !["User", "Admin"].includes(String(data.user.app_metadata.role))
    ) {
      return null;
    }
  }

  if (/^(?:\d{10}|u_\d{10})$/.test(subject)) return subject;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      subject,
    )
  ) {
    return null;
  }

  const { data: account, error } = await supabase
    .from("Users")
    .select("uid, role")
    .eq("google_auth_user_id", subject)
    .maybeSingle();
  if (error) throw error;
  if (!account || !["User", "Admin"].includes(String(account.role))) {
    return null;
  }
  const uid = account.uid;
  if (typeof uid === "number" && Number.isSafeInteger(uid)) {
    const value = String(uid);
    return /^\d{10}$/.test(value) ? value : null;
  }
  return typeof uid === "string" && /^(?:\d{10}|u_\d{10})$/.test(uid)
    ? uid
    : null;
}

async function isAdministrator(
  token: string,
  supabase: SupabaseClient,
  signingSecret: string,
): Promise<boolean> {
  const claims = await verifyTemporarySession(token, signingSecret);
  if (
    claims &&
    typeof claims.sub === "string" &&
    ["Admin", "SuperAdmin"].includes(String(claims.role))
  ) {
    if (claims.username === claims.sub) {
      const { data: account, error } = await supabase
        .from("Systems_Users")
        .select("role, endtime")
        .eq("Username", claims.sub)
        .maybeSingle();
      if (error) throw error;
      return (
        account != null &&
        ["Admin", "SuperAdmin"].includes(String(account.role)) &&
        (account.endtime === null ||
          (typeof account.endtime === "string" &&
            Date.parse(account.endtime) > Date.now()))
      );
    }

    const { data: account, error } = await supabase
      .from("Users")
      .select("role, status")
      .eq("google_auth_user_id", claims.sub)
      .maybeSingle();
    if (error) throw error;
    return (
      account != null &&
      ["Admin", "SuperAdmin"].includes(String(account.role)) &&
      account.status === "active"
    );
  }

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) return false;
  if (
    data.user.app_metadata.role != null &&
    !["Admin", "SuperAdmin"].includes(String(data.user.app_metadata.role))
  ) {
    return false;
  }
  const { data: account, error: accountError } = await supabase
    .from("Users")
    .select("role, status")
    .eq("google_auth_user_id", data.user.id)
    .maybeSingle();
  if (accountError) throw accountError;
  return (
    account != null &&
    ["Admin", "SuperAdmin"].includes(String(account.role)) &&
    account.status === "active"
  );
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
  const action = values.action;
  const ticketId =
    typeof values.ticketId === "string" ? values.ticketId.trim() : "";
  const sortBy = values.sortBy ?? "status";
  const sortAscending = values.sortAscending ?? true;
  if (
    typeof sortBy !== "string" ||
    !ticketSortColumns.includes(sortBy) ||
    typeof sortAscending !== "boolean"
  ) {
    return jsonResponse(400, { error: "Invalid ticket sort options." });
  }

  if (action === "admin-tickets" || action === "admin-update-ticket") {
    const token = request.headers
      .get("authorization")
      ?.match(/^Bearer\s+(.+)$/i)?.[1];
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = getSupabaseAdminKey();
    if (!supabaseUrl || !serviceRoleKey) {
      console.error("Supabase server configuration is missing.");
      return jsonResponse(500, { error: "Ticket service is not configured." });
    }
    if (!token) {
      return jsonResponse(401, {
        error: "Sign in with an administrator account.",
      });
    }
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    try {
      if (!(await isAdministrator(token, supabase, serviceRoleKey))) {
        return jsonResponse(403, {
          error: "Administrator access is required.",
        });
      }
    } catch (error) {
      console.error("Failed to verify administrator access.", error);
      return jsonResponse(500, {
        error: "Administrator access could not be verified.",
      });
    }

    if (action === "admin-update-ticket") {
      const requestData = values.request;
      const deviceData = values.devices;
      if (
        !/^\d{10}$/.test(ticketId) ||
        typeof requestData !== "object" ||
        requestData === null ||
        Array.isArray(requestData) ||
        !Array.isArray(deviceData) ||
        deviceData.length > 50
      ) {
        return jsonResponse(400, { error: "Invalid ticket update data." });
      }
      const requestFields = requestData as Record<string, unknown>;
      const building = requestFields.building;
      const latitude = requestFields.latitude;
      const longtitude = requestFields.longtitude;
      const area = requestFields.area;
      const floor = requestFields.floor;
      const room = requestFields.room;
      const status = requestFields.status;
      const technicianTeam = requestFields.technician_team;
      const nextFixStart = requestFields.next_fix_date_start;
      const nextFixEnd = requestFields.next_fix_date_end;
      const validRequest =
        typeof building === "string" &&
        (building === "other" || /^\d{1,2}$/.test(building)) &&
        typeof latitude === "number" &&
        Number.isFinite(latitude) &&
        latitude >= -90 &&
        latitude <= 90 &&
        typeof longtitude === "number" &&
        Number.isFinite(longtitude) &&
        longtitude >= -180 &&
        longtitude <= 180 &&
        (area == null || typeof area === "string") &&
        (building !== "other" ||
          (typeof area === "string" && area.trim() !== "")) &&
        (building === "other" || area == null || area === building) &&
        (floor == null ||
          (typeof floor === "string" &&
            /^\d+$/.test(floor) &&
            floor.replace(/^0+/, "").length <= 2 &&
            Number(floor) <= 50)) &&
        (building === "other" ||
          (typeof floor === "string" && floor.trim() !== "")) &&
        (room == null ||
          (typeof room === "string" && /^[a-zA-Z0-9-]{1,8}$/.test(room))) &&
        typeof status === "string" &&
        ["validating", "pending", "finish", "rejected", "cancel"].includes(
          status,
        ) &&
        (technicianTeam == null ||
          (typeof technicianTeam === "string" &&
            technicianTeam.trim() !== "" &&
            technicianTeam.length <= 120));
      if (!validRequest) {
        return jsonResponse(400, { error: "Invalid request fields." });
      }
      const devices = deviceData.map((value) => {
        if (
          typeof value !== "object" ||
          value === null ||
          Array.isArray(value)
        ) {
          return null;
        }
        const device = value as Record<string, unknown>;
        if (
          !Number.isSafeInteger(device.deviceid) ||
          typeof device.device !== "string" ||
          device.device.trim() === "" ||
          device.device.length > 120 ||
          (device.discription != null &&
            typeof device.discription !== "string") ||
          typeof device.status !== "string" ||
          !["validating", "pending", "rejected", "finish"].includes(
            device.status,
          ) ||
          (device.next_fix_date != null &&
            (typeof device.next_fix_date !== "string" ||
              !Number.isFinite(Date.parse(device.next_fix_date)))) ||
          !Array.isArray(device.technician_comment) ||
          device.technician_comment.length > 50 ||
          !device.technician_comment.every(
            (comment) =>
              comment == null ||
              (typeof comment === "string" && comment.length <= 1000),
          )
        ) {
          return null;
        }
        return {
          deviceid: device.deviceid as number,
          device: device.device,
          discription: device.discription as string | null,
          status: device.status,
          next_fix_date: device.next_fix_date as string | null,
          technician_comment: device.technician_comment as (string | null)[],
        };
      });
      if (devices.some((device) => device == null)) {
        return jsonResponse(400, { error: "Invalid device update data." });
      }
      const assignmentValidationError = validatePendingTicketUpdate(
        status,
        technicianTeam,
        nextFixStart,
        nextFixEnd,
        devices as NonNullable<(typeof devices)[number]>[],
      );
      if (assignmentValidationError === "team_required") {
        return jsonResponse(400, {
          error: "กรุณาเลือกทีมช่างก่อนบันทึกคำร้องสถานะรอซ่อม",
        });
      }
      if (assignmentValidationError === "schedule_required_or_invalid") {
        return jsonResponse(400, {
          error: "กรุณากำหนดช่วงเวลาเริ่มและสิ้นสุดการซ่อมให้ถูกต้อง",
        });
      }
      if (assignmentValidationError === "team_schedule_not_allowed") {
        return jsonResponse(400, {
          error: "เลือกทีมและช่วงเวลาซ่อมได้เฉพาะคำร้องสถานะรอซ่อม",
        });
      }

      if (typeof technicianTeam === "string") {
        const { data: teamAccounts, error: teamAccountsError } = await supabase
          .from("Maintenance_Users")
          .select("start_time, end_time")
          .eq("teamName", technicianTeam)
          .eq("status", true);
        if (teamAccountsError) {
          console.error(
            "Failed to validate the assigned maintenance team.",
            teamAccountsError,
          );
          return jsonResponse(500, {
            error: "Maintenance teams could not be checked.",
          });
        }
        const today = new Date(Date.now() + 7 * 60 * 60 * 1000)
          .toISOString()
          .slice(0, 10);
        const isEligible = (teamAccounts ?? []).some((technician) => {
          if (
            !Array.isArray(technician.start_time) ||
            !Array.isArray(technician.end_time) ||
            technician.start_time.length !== technician.end_time.length
          ) {
            return false;
          }
          return technician.start_time.some((start, index) => {
            const end = technician.end_time[index];
            if (typeof start !== "string" || typeof end !== "string") {
              return false;
            }
            const startTime = Date.parse(start);
            const endTime = Date.parse(end);
            if (!Number.isFinite(startTime) || !Number.isFinite(endTime)) {
              return false;
            }
            const startDate = new Date(startTime + 7 * 60 * 60 * 1000)
              .toISOString()
              .slice(0, 10);
            const endDate = new Date(endTime + 7 * 60 * 60 * 1000)
              .toISOString()
              .slice(0, 10);
            return startDate <= endDate && endDate >= today;
          });
        });
        if (!isEligible) {
          return jsonResponse(400, {
            error:
              "The selected maintenance team has no current or upcoming access period.",
          });
        }
        const scheduleIsAllowed = (teamAccounts ?? []).some((technician) =>
          accessPeriodContainsSchedule(
            technician.start_time,
            technician.end_time,
            nextFixStart,
            nextFixEnd,
          )
        );
        if (!scheduleIsAllowed) {
          return jsonResponse(400, {
            error:
              "ช่วงเวลาที่เลือกไม่อยู่ในสิทธิ์เข้าใช้งานของทีมช่าง กรุณาเลือกทีมและช่วงเวลาใหม่",
          });
        }
      }

      if (
        status === "rejected" &&
        devices.some((device) => device!.status !== "rejected")
      ) {
        return jsonResponse(400, {
          error: "All devices must be rejected when the ticket is rejected.",
        });
      }
      if (
        status === "finish" &&
        devices.some(
          (device) => !["rejected", "finish"].includes(device!.status),
        )
      ) {
        return jsonResponse(400, {
          error:
            "Devices must be rejected or finished when the ticket is finished.",
        });
      }
      if (
        status === "pending" &&
        !devices.some((device) => device!.status === "pending")
      ) {
        return jsonResponse(400, {
          error:
            "At least one device must be pending when the ticket is pending.",
        });
      }
      if (
        status === "validating" ||
        devices.some((device) => device!.status === "validating")
      ) {
        return jsonResponse(400, {
          error:
            "The ticket and all devices must leave validating before they can be saved.",
        });
      }
      const deviceIds = devices.map((device) => device!.deviceid);
      if (new Set(deviceIds).size !== deviceIds.length) {
        return jsonResponse(400, {
          error: "Duplicate device IDs are not allowed.",
        });
      }

      const { error: ticketUpdateError } = await supabase.rpc(
        "admin_update_ticket_assignment_atomic",
        {
          p_ticket_id: ticketId,
          p_building: building,
          p_latitude: latitude,
          p_longtitude: longtitude,
          p_area: area == null ? null : String(area).trim(),
          p_floor: floor == null ? null : String(floor).trim(),
          p_room: room == null ? null : String(room).trim(),
          p_status: status,
          p_technician_team:
            technicianTeam == null ? null : String(technicianTeam).trim(),
          p_next_fix_date_start: nextFixStart ?? null,
          p_next_fix_date_end: nextFixEnd ?? null,
          p_devices: devices,
        },
      );
      if (ticketUpdateError) {
        const failure = classifyAssignmentRpcFailure(ticketUpdateError);
        const correlationId = crypto.randomUUID();
        const errorCode = typeof ticketUpdateError.code === "string" &&
            /^[A-Z0-9]{5,8}$/.test(ticketUpdateError.code)
          ? ticketUpdateError.code
          : "unknown";
        console.error("admin_update_ticket_rpc_failed", {
          category: failure.category,
          errorCode,
          correlationId,
        });
        return jsonResponse(failure.status, {
          error: failure.message,
          correlationId,
        });
      }
      return jsonResponse(200, { updated: true });
    }

    await expireOverdueTicketsSilently(supabase);

    const page = values.page;
    const pageSize = values.pageSize;
    if (
      ticketId.length > 10 ||
      !/^\d*$/.test(ticketId) ||
      typeof page !== "number" ||
      !Number.isSafeInteger(page) ||
      page < 0 ||
      typeof pageSize !== "number" ||
      !Number.isSafeInteger(pageSize) ||
      pageSize < 1 ||
      pageSize > 50
    ) {
      return jsonResponse(400, { error: "Invalid ticket search or page." });
    }
    const orderColumn = sortBy === "next_fix_date" ? "next_fix_date_start" : sortBy;
    const offset = page * pageSize;
    const { data, count, error } = await supabase
      .from("FixList")
      .select(
        "TicketId, building, latitude, longtitude, area, floor, room, status, request_date, technician_team, fix_history_time_start, fix_history_time_end, next_fix_date_start, next_fix_date_end",
        { count: "exact" },
      )
      .ilike("TicketId", ticketId ? `%${ticketId}%` : "%")
      .order(orderColumn, { ascending: sortAscending })
      .order("request_date", { ascending: false })
      .order("TicketId", { ascending: false })
      .range(offset, offset + pageSize - 1);
    if (error) {
      console.error("Failed to load admin repair requests.", error);
      return jsonResponse(500, {
        error: "Repair requests could not be loaded.",
      });
    }
    return jsonResponse(200, { tickets: data ?? [], total: count ?? 0 });
  }

  if (action === "my-tickets" || action === "cancel-request") {
    const token = request.headers
      .get("authorization")
      ?.match(/^Bearer\s+(.+)$/i)?.[1];
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = getSupabaseAdminKey();
    if (!supabaseUrl || !serviceRoleKey) {
      console.error("Supabase server configuration is missing.");
      return jsonResponse(500, { error: "Ticket service is not configured." });
    }
    if (!token) {
      return jsonResponse(401, { error: "Sign in to access your requests." });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    let requester: string | null;
    try {
      requester = await requesterUid(token, supabase, serviceRoleKey);
    } catch (error) {
      console.error("Failed to verify repair request owner.", error);
      return jsonResponse(500, {
        error: "Your requests could not be verified.",
      });
    }
    if (!requester) {
      return jsonResponse(401, { error: "A valid user account is required." });
    }

    if (action === "cancel-request") {
      if (!/^\d{10}$/.test(ticketId)) {
        return jsonResponse(400, { error: "Invalid ticket ID." });
      }
      const { data: cancelledTicket, error } = await supabase
        .from("FixList")
        .update({ status: "cancel" })
        .eq("TicketId", ticketId)
        .eq("requester", requester)
        .eq("status", "validating")
        .select("TicketId")
        .maybeSingle();
      if (error) {
        console.error("Failed to cancel repair request.", error);
        return jsonResponse(500, {
          error: "The repair request could not be cancelled.",
        });
      }
      if (!cancelledTicket) {
        return jsonResponse(409, {
          error:
            "This request cannot be cancelled because it is no longer awaiting validation.",
        });
      }
      return jsonResponse(200, { cancelled: true });
    }

    await expireOverdueTicketsSilently(supabase);

    const page = values.page;
    const pageSize = values.pageSize;
    if (
      ticketId.length > 10 ||
      !/^\d*$/.test(ticketId) ||
      typeof page !== "number" ||
      !Number.isSafeInteger(page) ||
      page < 0 ||
      typeof pageSize !== "number" ||
      !Number.isSafeInteger(pageSize) ||
      pageSize < 1 ||
      pageSize > 50
    ) {
      return jsonResponse(400, { error: "Invalid ticket search or page." });
    }

    const orderColumn = sortBy === "next_fix_date" ? "next_fix_date_start" : sortBy;
    const offset = page * pageSize;
    if (!Number.isSafeInteger(offset)) {
      return jsonResponse(400, { error: "Invalid page." });
    }

    let query = supabase
      .from("FixList")
      .select(
        "TicketId, building, area, floor, room, status, request_date, fix_history_time_start, fix_history_time_end, next_fix_date_start, next_fix_date_end",
        { count: "exact" },
      )
      .eq("requester", requester);
    if (ticketId) query = query.ilike("TicketId", `%${ticketId}%`);

    const { data, count, error } = await query
      .order(orderColumn, { ascending: sortAscending })
      .order("request_date", { ascending: false })
      .order("TicketId", { ascending: false })
      .range(offset, offset + pageSize - 1);
    if (error) {
      console.error("Failed to load the requester's tickets.", error);
      return jsonResponse(500, { error: "Your requests could not be loaded." });
    }
    return jsonResponse(200, { tickets: data ?? [], total: count ?? 0 });
  }

  if (action === "devices") {
    if (!/^\d{10}$/.test(ticketId)) {
      return jsonResponse(400, { error: "Invalid ticket ID." });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = getSupabaseAdminKey();
    if (!supabaseUrl || !serviceRoleKey) {
      console.error("Supabase server configuration is missing.");
      return jsonResponse(500, { error: "Ticket service is not configured." });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    await expireOverdueTicketsSilently(supabase);
    const { data: ticket, error: ticketError } = await supabase
      .from("FixList")
      .select(
        "TicketId, requester, technician_history, technician_comment, fix_history_time_start, fix_history_time_end, next_fix_date_start, next_fix_date_end",
      )
      .eq("TicketId", ticketId)
      .maybeSingle();
    if (ticketError) {
      console.error(
        "Failed to verify ticket before loading its devices.",
        ticketError,
      );
      return jsonResponse(500, {
        error: "Ticket devices could not be loaded.",
      });
    }
    if (!ticket) {
      return jsonResponse(404, { error: "Ticket not found." });
    }

    const { data: devices, error: devicesError } = await supabase
      .from(ticketId)
      .select(
        "deviceid, device, discription, status, next_fix_date, fix_history_progress, technician_comment",
      )
      .order("deviceid", { ascending: true });
    if (devicesError) {
      console.error("Failed to load ticket devices.", devicesError);
      return jsonResponse(500, {
        error: "Ticket devices could not be loaded.",
      });
    }
    const { data: historyReports, error: historyReportsError } = await supabase
      .from("technician_work_reports")
      .select("history_index, photo_path, device_results")
      .eq("TicketId", ticketId)
      .eq("status", "approved")
      .not("history_index", "is", null)
      .order("history_index", { ascending: true });
    if (historyReportsError) {
      console.error(
        "Failed to load repair history reports.",
        historyReportsError,
      );
      return jsonResponse(500, {
        error: "Repair history could not be loaded.",
      });
    }
    const historyPhotoReports: Array<{
      history_index: number;
      deviceid: number | null;
      row_index: number | null;
      photo_path: string;
    }> = [];
    for (const report of historyReports ?? []) {
      if (typeof report.history_index !== "number") continue;
      if (Array.isArray(report.device_results) && report.device_results.length > 0) {
        for (const result of report.device_results) {
          if (
            result?.success === true &&
            typeof result?.photo_path === "string" &&
            typeof result.deviceid === "number" &&
            typeof result.row_index === "number"
          ) {
            historyPhotoReports.push({
              history_index: report.history_index,
              deviceid: result.deviceid,
              row_index: result.row_index,
              photo_path: result.photo_path,
            });
          }
        }
      } else if (typeof report.photo_path === "string") {
        historyPhotoReports.push({
          history_index: report.history_index,
          deviceid: null,
          row_index: null,
          photo_path: report.photo_path,
        });
      }
    }
    const { data: signedHistoryPhotos, error: signedHistoryPhotosError } =
      historyPhotoReports.length === 0
        ? { data: [], error: null }
        : await supabase.storage.from(technicianWorkBucket).createSignedUrls(
            historyPhotoReports.map((report) => report.photo_path),
            300,
          );
    if (signedHistoryPhotosError) {
      console.error(
        "Failed to create signed URLs for repair history photos.",
        signedHistoryPhotosError,
      );
      return jsonResponse(500, {
        error: "Repair history photos could not be loaded.",
      });
    }
    const historyPhotoUrls = new Map(
      (signedHistoryPhotos ?? []).map((photo) => [photo.path, photo.signedUrl]),
    );
    const { data: signedPhotos, error: signedPhotosError } =
      await supabase.storage.from(ticketId).createSignedUrls(
        (devices ?? []).map((device) => String(device.deviceid)),
        300,
      );
    if (signedPhotosError) {
      console.error(
        "Failed to create signed URLs for ticket photos.",
        signedPhotosError,
      );
      return jsonResponse(500, { error: "Ticket photos could not be loaded." });
    }
    const photoUrls = new Map(
      (signedPhotos ?? []).map((photo) => [photo.path, photo.signedUrl]),
    );
    return jsonResponse(200, {
      devices: (devices ?? []).map((device) => ({
        ...device,
        next_fix_date: device.next_fix_date,
        photo_url: photoUrls.get(String(device.deviceid)) ?? null,
      })),
      technician_history: ticket.technician_history,
      technician_comment: ticket.technician_comment,
      fix_history_time_start: ticket.fix_history_time_start,
      fix_history_time_end: ticket.fix_history_time_end,
      next_fix_date_start: ticket.next_fix_date_start,
      next_fix_date_end: ticket.next_fix_date_end,
      repair_history_photos: historyPhotoReports.map((report) => ({
        history_index: report.history_index,
        deviceid: report.deviceid,
        row_index: report.row_index,
        photo_url: historyPhotoUrls.get(report.photo_path) ?? null,
      })),
    });
  }

  const page = values.page;
  const pageSize = values.pageSize;
  if (
    ticketId.length > 10 ||
    !/^\d*$/.test(ticketId) ||
    typeof page !== "number" ||
    !Number.isSafeInteger(page) ||
    page < 0 ||
    typeof pageSize !== "number" ||
    !Number.isSafeInteger(pageSize) ||
    pageSize < 1 ||
    pageSize > 50
  ) {
    return jsonResponse(400, { error: "Invalid ticket search or page." });
  }
  const offset = page * pageSize;
  if (!Number.isSafeInteger(offset)) {
    return jsonResponse(400, { error: "Invalid page." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = getSupabaseAdminKey();
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Supabase server configuration is missing.");
    return jsonResponse(500, { error: "Ticket service is not configured." });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  await expireOverdueTicketsSilently(supabase);
  const orderColumn = sortBy === "next_fix_date" ? "next_fix_date_start" : sortBy;
  let query = supabase
    .from("FixList")
    .select(
      "TicketId, building, area, floor, room, status, request_date, fix_history_time_start, fix_history_time_end, next_fix_date_start, next_fix_date_end",
      { count: "exact" },
    );
  if (ticketId) query = query.ilike("TicketId", `%${ticketId}%`);

  const { data, count, error } = await query
    .order(orderColumn, { ascending: sortAscending })
    .order("request_date", { ascending: false })
    .order("TicketId", { ascending: false })
    .range(offset, offset + pageSize - 1);
  if (error) {
    console.error("Failed to load public tickets.", error);
    return jsonResponse(500, { error: "Tickets could not be loaded." });
  }

  return jsonResponse(200, { tickets: data ?? [], total: count ?? 0 });
});
