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

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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
  area: string | null;
  floor: string | null;
  room: string | null;
  fix_history_time_start?: string[] | null;
  fix_history_time_end?: string[] | null;
  next_fix_date?: string | null;
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
      const firstValue = first[sortBy as keyof TicketRow];
      const secondValue = second[sortBy as keyof TicketRow];
      if (firstValue == null && secondValue != null) return 1;
      if (firstValue != null && secondValue == null) return -1;
      if (firstValue == null || secondValue == null) {
        valueOrder = 0;
      } else if (sortBy === "request_date") {
        valueOrder = (Date.parse(firstValue as string) -
          Date.parse(secondValue as string)) * (ascending ? 1 : -1);
      } else {
        valueOrder = String(firstValue).localeCompare(String(secondValue), undefined, {
          numeric: true,
          sensitivity: "base",
        }) * (ascending ? 1 : -1);
      }
    }
    if (valueOrder !== 0) return valueOrder;
    const dateOrder = Date.parse(second.request_date) -
      Date.parse(first.request_date);
    return dateOrder || second.TicketId.localeCompare(first.TicketId);
  });
}

async function ticketNextFixDate(
  supabase: SupabaseClient,
  ticketId: string,
): Promise<string | null> {
  const { data: schedules, error } = await supabase
    .from(ticketId)
    .select("next_fix_date")
    .not("next_fix_date", "is", null)
    .order("deviceid", { ascending: true })
    .limit(50);
  if (error) {
    console.error(`Failed to load schedule for ticket ${ticketId}.`, error);
    throw new Error("Ticket schedules could not be loaded.");
  }
  const dates = (schedules ?? []).flatMap((row) =>
    Array.isArray(row.next_fix_date) ? row.next_fix_date : []
  );
  const latestDate = dates.at(-1);
  return typeof latestDate === "string" ? latestDate : null;
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
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(subject)
  ) {
    return null;
  }

  const { data: account, error } = await supabase
    .from("Users")
    .select("uid, role")
    .eq("google_auth_user_id", subject)
    .maybeSingle();
  if (error) throw error;
  if (
    !account ||
    !["User", "Admin"].includes(String(account.role))
  ) {
    return null;
  }
  const uid = account.uid;
  if (typeof uid === "number" && Number.isSafeInteger(uid)) {
    const value = String(uid);
    return /^\d{10}$/.test(value) ? value : null;
  }
  return typeof uid === "string" &&
      /^(?:\d{10}|u_\d{10})$/.test(uid)
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
    return true;
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
    .select("role")
    .eq("google_auth_user_id", data.user.id)
    .maybeSingle();
  if (accountError) throw accountError;
  return account != null &&
    ["Admin", "SuperAdmin"].includes(String(account.role));
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
  const ticketId = typeof values.ticketId === "string"
    ? values.ticketId.trim()
    : "";
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
    const token = request.headers.get("authorization")
      ?.match(/^Bearer\s+(.+)$/i)?.[1];
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = getSupabaseAdminKey();
    if (!supabaseUrl || !serviceRoleKey) {
      console.error("Supabase server configuration is missing.");
      return jsonResponse(500, { error: "Ticket service is not configured." });
    }
    if (!token) {
      return jsonResponse(401, { error: "Sign in with an administrator account." });
    }
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    try {
      if (!await isAdministrator(token, supabase, serviceRoleKey)) {
        return jsonResponse(403, { error: "Administrator access is required." });
      }
    } catch (error) {
      console.error("Failed to verify administrator access.", error);
      return jsonResponse(500, { error: "Administrator access could not be verified." });
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
      const area = requestFields.area;
      const floor = requestFields.floor;
      const room = requestFields.room;
      const status = requestFields.status;
      const technicianTeam = requestFields.technician_team;
      const validRequest =
        typeof building === "string" &&
        (building === "other" || /^\d{1,2}$/.test(building)) &&
        (area == null || typeof area === "string") &&
        (building !== "other" || (typeof area === "string" && area.trim() !== "")) &&
        (building === "other" || area == null) &&
        (floor == null ||
          (typeof floor === "string" && /^\d+$/.test(floor) &&
            floor.replace(/^0+/, "").length <= 2 &&
            Number(floor) <= 50)) &&
        (room == null ||
          (typeof room === "string" && /^[a-zA-Z0-9-]{1,8}$/.test(room))) &&
        typeof status === "string" &&
        ["validating", "pending", "finish", "rejected", "cancel"].includes(status) &&
        (technicianTeam == null ||
          (typeof technicianTeam === "string" && technicianTeam.length <= 120));
      if (!validRequest) {
        return jsonResponse(400, { error: "Invalid request fields." });
      }

      const devices = deviceData.map((value) => {
        if (typeof value !== "object" || value === null || Array.isArray(value)) {
          return null;
        }
        const device = value as Record<string, unknown>;
        if (
          !Number.isSafeInteger(device.deviceid) ||
          typeof device.device !== "string" ||
          device.device.trim() === "" ||
          device.device.length > 120 ||
          (device.discription != null && typeof device.discription !== "string") ||
          typeof device.status !== "string" ||
          device.status.length > 80 ||
          (device.next_fix_date != null &&
            (!Array.isArray(device.next_fix_date) ||
              device.next_fix_date.length > 50 ||
              !device.next_fix_date.every(
                (date) => date == null ||
                  (typeof date === "string" &&
                    Number.isFinite(Date.parse(date))),
              ))) ||
          !Array.isArray(device.technician_comment) ||
          device.technician_comment.length > 50 ||
          !device.technician_comment.every(
            (comment) => comment == null ||
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
          next_fix_date: device.next_fix_date as (string | null)[] | null,
          technician_comment: device.technician_comment as (string | null)[],
        };
      });
      if (devices.some((device) => device == null)) {
        return jsonResponse(400, { error: "Invalid device update data." });
      }
      const deviceIds = devices.map((device) => device!.deviceid);
      if (new Set(deviceIds).size !== deviceIds.length) {
        return jsonResponse(400, { error: "Duplicate device IDs are not allowed." });
      }

      const { data: existingDevices, error: existingDevicesError } = await supabase
        .from(ticketId)
        .select("deviceid")
        .order("deviceid", { ascending: true });
      if (existingDevicesError) {
        console.error("Failed to validate ticket devices before update.", existingDevicesError);
        return jsonResponse(500, { error: "Ticket devices could not be updated." });
      }
      const existingIds = (existingDevices ?? []).map((device) => device.deviceid);
      if (
        existingIds.length !== deviceIds.length ||
        existingIds.some((id, index) => id !== [...deviceIds].sort((a, b) => a - b)[index])
      ) {
        return jsonResponse(400, { error: "The device list does not match this ticket." });
      }

      const { error: ticketUpdateError } = await supabase
        .from("FixList")
        .update({
          building,
          area: area == null ? null : String(area).trim(),
          floor: floor == null ? null : String(floor).trim(),
          room: room == null ? null : String(room).trim(),
          status,
          technician_team: technicianTeam == null
            ? null
            : String(technicianTeam).trim(),
        })
        .eq("TicketId", ticketId);
      if (ticketUpdateError) {
        console.error("Failed to update repair request.", ticketUpdateError);
        return jsonResponse(500, { error: "Repair request could not be updated." });
      }
      for (const device of devices) {
        const { error } = await supabase
          .from(ticketId)
          .update({
            device: device!.device.trim(),
            discription: device!.discription?.trim() || null,
            status: device!.status.trim(),
            next_fix_date: device!.next_fix_date,
            technician_comment: device!.technician_comment,
          })
          .eq("deviceid", device!.deviceid);
        if (error) {
          console.error(
            `Failed to update device ${device!.deviceid} for ticket ${ticketId}.`,
            error,
          );
          return jsonResponse(500, {
            error: "A device could not be updated; some ticket changes may already have been saved.",
          });
        }
      }
      return jsonResponse(200, { updated: true });
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
    const { data, count, error } = await supabase
      .from("FixList")
      .select(
        "TicketId, building, area, floor, room, status, request_date, technician_team, fix_history_time_start, fix_history_time_end",
        { count: "exact" },
      )
      .order("request_date", { ascending: false })
      .order("TicketId", { ascending: false })
      .ilike("TicketId", ticketId ? `%${ticketId}%` : "%");
    if (error) {
      console.error("Failed to load admin repair requests.", error);
      return jsonResponse(500, { error: "Repair requests could not be loaded." });
    }
    let tickets: TicketRow[] = data ?? [];
    try {
      tickets = await Promise.all(
        tickets.map(async (ticket) => ({
          ...ticket,
          next_fix_date: await ticketNextFixDate(supabase, ticket.TicketId),
        })),
      );
    } catch (error) {
      console.error("Failed to load schedules for admin repair requests.", error);
      return jsonResponse(500, { error: "Ticket schedules could not be loaded." });
    }
    const pageTickets = sortTickets(tickets, sortBy, sortAscending).slice(
      page * pageSize,
      (page + 1) * pageSize,
    );
    return jsonResponse(200, { tickets: pageTickets, total: count ?? 0 });
  }

  if (action === "my-tickets" || action === "cancel-request") {
    const token = request.headers.get("authorization")
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
      return jsonResponse(500, { error: "Your requests could not be verified." });
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
        return jsonResponse(500, { error: "The repair request could not be cancelled." });
      }
      if (!cancelledTicket) {
        return jsonResponse(409, {
          error: "This request cannot be cancelled because it is no longer awaiting validation.",
        });
      }
      return jsonResponse(200, { cancelled: true });
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

    let query = supabase
      .from("FixList")
      .select(
        "TicketId, building, area, floor, room, status, request_date, fix_history_time_start, fix_history_time_end",
        { count: "exact" },
      )
      .eq("requester", requester)
      .order("request_date", { ascending: false })
      .order("TicketId", { ascending: false });
    if (ticketId) query = query.ilike("TicketId", `%${ticketId}%`);

    const { data, count, error } = await query;
    if (error) {
      console.error("Failed to load the requester's tickets.", error);
      return jsonResponse(500, { error: "Your requests could not be loaded." });
    }
    let tickets: TicketRow[] = data ?? [];
    if (sortBy === "next_fix_date") {
      try {
        tickets = await Promise.all(
          tickets.map(async (ticket) => ({
            ...ticket,
            next_fix_date: await ticketNextFixDate(supabase, ticket.TicketId),
          })),
        );
      } catch (error) {
        console.error("Failed to load ticket schedules for sorting.", error);
        return jsonResponse(500, {
          error: "Ticket schedules could not be loaded.",
        });
      }
    }
    tickets = sortTickets(tickets, sortBy, sortAscending);
    const offset = page * pageSize;
    if (!Number.isSafeInteger(offset)) {
      return jsonResponse(400, { error: "Invalid page." });
    }
    const pageTickets = tickets.slice(offset, offset + pageSize);
    const pageWithSchedules = await Promise.all(
      pageTickets.map(async (ticket) => {
        return {
          ...ticket,
          next_fix_date: sortBy === "next_fix_date"
            ? ticket.next_fix_date ?? null
            : await ticketNextFixDate(supabase, ticket.TicketId),
        };
      }),
    ).catch((error: unknown) => {
      console.error("Failed to load requester's ticket schedules.", error);
      return null;
    });
    if (pageWithSchedules === null) {
      return jsonResponse(500, { error: "Ticket schedules could not be loaded." });
    }
    return jsonResponse(200, { tickets: pageWithSchedules, total: count ?? 0 });
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
    const { data: ticket, error: ticketError } = await supabase
      .from("FixList")
      .select(
        "TicketId, technician_history, fix_history_time_start, fix_history_time_end",
      )
      .eq("TicketId", ticketId)
      .maybeSingle();
    if (ticketError) {
      console.error("Failed to verify ticket before loading its devices.", ticketError);
      return jsonResponse(500, { error: "Ticket devices could not be loaded." });
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
      return jsonResponse(500, { error: "Ticket devices could not be loaded." });
    }
    return jsonResponse(200, {
      devices,
      technician_history: ticket.technician_history,
      fix_history_time_start: ticket.fix_history_time_start,
      fix_history_time_end: ticket.fix_history_time_end,
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
  let query = supabase
    .from("FixList")
    .select(
      "TicketId, building, area, floor, room, status, request_date, fix_history_time_start, fix_history_time_end",
      { count: "exact" },
    )
    .order("request_date", { ascending: false })
    .order("TicketId", { ascending: false });
  if (ticketId) query = query.ilike("TicketId", `%${ticketId}%`);

  const { data, count, error } = await query;
  if (error) {
    console.error("Failed to load public tickets.", error);
    return jsonResponse(500, { error: "Tickets could not be loaded." });
  }

  let allTickets: TicketRow[] = data ?? [];
  if (sortBy === "next_fix_date") {
    try {
      allTickets = await Promise.all(
        allTickets.map(async (ticket) => ({
          ...ticket,
          next_fix_date: await ticketNextFixDate(supabase, ticket.TicketId),
        })),
      );
    } catch (error) {
      console.error("Failed to load ticket schedules for sorting.", error);
      return jsonResponse(500, {
        error: "Ticket schedules could not be loaded.",
      });
    }
  }
  const pageTickets = sortTickets(allTickets, sortBy, sortAscending).slice(
    offset,
    offset + pageSize,
  );
  const tickets = await Promise.all(
    pageTickets.map(async (ticket) => {
      return {
        ...ticket,
        next_fix_date: sortBy === "next_fix_date"
          ? ticket.next_fix_date ?? null
          : await ticketNextFixDate(supabase, ticket.TicketId),
      };
    }),
  ).catch((error: unknown) => {
    console.error("Failed to load ticket schedules.", error);
    return null;
  });

  if (tickets === null) {
    return jsonResponse(500, { error: "Ticket schedules could not be loaded." });
  }

  return jsonResponse(200, { tickets, total: count ?? 0 });
});
