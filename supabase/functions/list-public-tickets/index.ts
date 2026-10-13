import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
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
      .select("TicketId")
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
      .select("deviceid, device, discription, status, next_fix_date")
      .order("deviceid", { ascending: true });
    if (devicesError) {
      console.error("Failed to load ticket devices.", devicesError);
      return jsonResponse(500, { error: "Ticket devices could not be loaded." });
    }
    return jsonResponse(200, { devices });
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
    .select("TicketId, building, area, floor, room, status, request_date", {
      count: "exact",
    })
    .order("TicketId", { ascending: false });
  if (ticketId) query = query.ilike("TicketId", `%${ticketId}%`);

  const { data, count, error } = await query.range(
    offset,
    offset + pageSize - 1,
  );
  if (error) {
    console.error("Failed to load public tickets.", error);
    return jsonResponse(500, { error: "Tickets could not be loaded." });
  }

  const tickets = await Promise.all(
    (data ?? []).map(async (ticket) => {
      const { data: schedules, error: scheduleError } = await supabase
        .from(ticket.TicketId)
        .select("next_fix_date")
        .not("next_fix_date", "is", null)
        .order("deviceid", { ascending: true })
        .limit(50);

      if (scheduleError) {
        console.error(
          `Failed to load schedule for ticket ${ticket.TicketId}.`,
          scheduleError,
        );
        throw new Error("Ticket schedules could not be loaded.");
      }

      const scheduleDates = (schedules ?? []).flatMap((row) =>
        Array.isArray(row.next_fix_date) ? row.next_fix_date : []
      );
      return {
        ...ticket,
        next_fix_date: scheduleDates.at(-1) ?? null,
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
