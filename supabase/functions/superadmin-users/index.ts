import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyTemporarySession } from "../_shared/credentials.ts";
import { getSupabaseAdminKey } from "../_shared/supabase_admin_key.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonObject = Record<string, unknown>;

function jsonResponse(status: number, body: JsonObject) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isRecord(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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
    return jsonResponse(500, { error: "User management is not configured." });
  }

  const token = request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)
    ?.[1];
  const claims = token
    ? await verifyTemporarySession(token, serviceRoleKey)
    : null;
  if (
    !claims ||
    typeof claims.sub !== "string" ||
    (claims.role !== "Admin" && claims.role !== "SuperAdmin")
  ) {
    return jsonResponse(403, { error: "หน้านี้สำหรับผู้ดูแลระบบเท่านั้น" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const isSystemAccount = claims.username === claims.sub;
  let requesterDisplayName: string;
  let requesterUid: string = claims.sub;
  try {
    if (isSystemAccount) {
      const { data, error } = await supabase
        .from("Systems_Users")
        .select('"Username", role, endtime')
        .eq("Username", claims.sub)
        .maybeSingle();
      if (error) throw error;
      if (
        !data ||
        data.role !== claims.role ||
        (data.endtime !== null &&
          (typeof data.endtime !== "string" ||
            !Number.isFinite(Date.parse(data.endtime)) ||
            Date.parse(data.endtime) <= Date.now()))
      ) {
        return jsonResponse(403, { error: "ต้องใช้บัญชีผู้ดูแลระบบที่ยังใช้งานได้" });
      }
      requesterDisplayName = data.Username;
      requesterUid = data.Username;
    } else {
      const { data, error } = await supabase
        .from("Users")
        .select('uid, role, status, "Display Name"')
        .eq("google_auth_user_id", claims.sub)
        .maybeSingle();
      if (error) throw error;
      if (!data || data.role !== claims.role || data.status !== "active") {
        return jsonResponse(403, { error: "ต้องใช้บัญชีผู้ดูแลระบบที่ยังใช้งานได้" });
      }
      requesterDisplayName = data["Display Name"];
      if (typeof data.uid === "string" && data.uid) {
        requesterUid = data.uid;
      }
    }
  } catch (error) {
    console.error("Failed to verify the SuperAdmin account.", error);
    return jsonResponse(500, { error: "ไม่สามารถตรวจสอบสิทธิ์ SuperAdmin ได้" });
  }

  let payload: JsonObject;
  try {
    const body: unknown = await request.json();
    if (!isRecord(body)) return jsonResponse(400, { error: "Invalid request body." });
    payload = body;
  } catch {
    return jsonResponse(400, { error: "Invalid JSON request body." });
  }

  const action = payload.action;
  if (action === "list-users") {
    const users: JsonObject[] = [];
    for (let from = 0; ; from += 500) {
      let query = supabase
        .from("Users")
        .select('uid, created_at, "Display Name", role, status')
        .order("created_at", { ascending: false });
      if (claims.role === "Admin") query = query.eq("role", "User");
      const { data, error } = await query.range(from, from + 499);
      if (error) {
        console.error("Failed to list users for SuperAdmin.", error);
        return jsonResponse(500, { error: "ไม่สามารถโหลดข้อมูลผู้ใช้ได้" });
      }
      for (const user of data) {
        users.push({
          uid: user.uid,
          created_at: user.created_at,
          displayName: user["Display Name"],
          role: user.role,
          status: user.status,
        });
      }
      if (data.length < 500) break;
    }
    return jsonResponse(200, { users });
  }

  if (action === "submit-change") {
    const uid = payload.uid;
    const changes = payload.changes;
    if (
      typeof uid !== "string" ||
      !/^u_[0-9]{10}$/.test(uid) ||
      !isRecord(changes) ||
      Object.keys(changes).length === 0 ||
      Object.keys(changes).some((key) =>
        !["displayName", "role", "status"].includes(key)
      )
    ) {
      return jsonResponse(400, { error: "ข้อมูลคำขอแก้ไขไม่ถูกต้อง" });
    }
    if (
      claims.role === "Admin" &&
      (Object.keys(changes).length !== 1 || !("displayName" in changes))
    ) {
      return jsonResponse(403, {
        error: "Admin สามารถแก้ไขได้เฉพาะชื่อที่แสดง",
      });
    }

    let requestedDisplayName: string | null = null;
    let requestedRole: string | null = null;
    let requestedStatus: string | null = null;
    if ("displayName" in changes) {
      if (typeof changes.displayName !== "string") {
        return jsonResponse(400, { error: "กรุณาตรวจสอบชื่อที่แสดง" });
      }
      requestedDisplayName = changes.displayName.trim();
      if (!requestedDisplayName || requestedDisplayName.length > 160) {
        return jsonResponse(400, { error: "กรุณาตรวจสอบชื่อที่แสดง" });
      }
    }
    if ("role" in changes) {
      if (changes.role !== "User" && changes.role !== "Admin") {
        return jsonResponse(400, { error: "บทบาทผู้ใช้ไม่ถูกต้อง" });
      }
      requestedRole = changes.role;
    }
    if ("status" in changes) {
      if (changes.status !== "active" && changes.status !== "unactive") {
        return jsonResponse(400, { error: "สถานะผู้ใช้ไม่ถูกต้อง" });
      }
      requestedStatus = changes.status;
    }

    const { data: target, error: targetError } = await supabase
      .from("Users")
      .select('uid, "Display Name", role, status')
      .eq("uid", uid)
      .maybeSingle();
    if (targetError) {
      console.error("Failed to load target user.", targetError);
      return jsonResponse(500, { error: "ไม่สามารถตรวจสอบผู้ใช้เป้าหมายได้" });
    }
    if (!target) return jsonResponse(404, { error: "ไม่พบผู้ใช้ที่ต้องการแก้ไข" });
    if (claims.role === "Admin") {
      if (target.role !== "User") {
        return jsonResponse(404, { error: "ไม่พบผู้ใช้ที่ต้องการแก้ไข" });
      }
      const { error: updateError } = await supabase
        .from("Users")
        .update({ "Display Name": requestedDisplayName })
        .eq("uid", target.uid);
      if (updateError) {
        console.error("Admin failed to update a user display name.", updateError);
        return jsonResponse(500, { error: "ไม่สามารถบันทึกชื่อที่แสดงได้" });
      }

      const { error: logError } = await supabase.from("activity_logs").insert({
        actor_username: requesterUid,
        actor_role: "Admin",
        actor_display_name: requesterDisplayName,
        action_type: "CHANGE_USER_DISPLAY_NAME",
        action_title: "แอดมินเปลี่ยนชื่อที่แสดงของผู้ใช้อื่น",
        target_id: target.uid,
        description: `แอดมินเปลี่ยนชื่อที่แสดงของ ${target.uid} จาก "${target["Display Name"] ?? ""}" เป็น "${requestedDisplayName}"`,
        metadata: {
          uid: requesterUid,
          target_uid: target.uid,
          old_display_name: target["Display Name"],
          new_display_name: requestedDisplayName,
        },
        created_at: new Date().toISOString(),
      });
      if (logError) {
        console.error("Failed to record activity log for admin user display name change:", logError);
      }

      return jsonResponse(200, {
        result: { status: "updated", displayNameUpdated: true },
      });
    }
    const { data, error } = await supabase.rpc(
      "submit_superadmin_user_change",
      {
        p_target_uid: target.uid,
        p_requester_id: claims.sub,
        p_requester_is_system: isSystemAccount,
        p_requester_display_name: requesterDisplayName,
        p_display_name: requestedDisplayName,
        p_role: requestedRole,
        p_status: requestedStatus,
      },
    );
    if (error) {
      console.error("Failed to submit SuperAdmin user change.", error);
      return jsonResponse(409, { error: error.message });
    }

    const displayNameUpdated =
      (isRecord(data) && data.displayNameUpdated === true) ||
      (requestedDisplayName !== undefined &&
        requestedDisplayName !== null &&
        requestedDisplayName !== target["Display Name"]);

    if (displayNameUpdated) {
      const { error: logError } = await supabase.from("activity_logs").insert({
        actor_username: requesterUid,
        actor_role: "SuperAdmin",
        actor_display_name: requesterDisplayName,
        action_type: "CHANGE_USER_DISPLAY_NAME",
        action_title: "SuperAdmin เปลี่ยนชื่อที่แสดงของผู้ใช้อื่น",
        target_id: target.uid,
        description: `SuperAdmin เปลี่ยนชื่อที่แสดงของ ${target.uid} จาก "${target["Display Name"] ?? ""}" เป็น "${requestedDisplayName}"`,
        metadata: {
          uid: requesterUid,
          target_uid: target.uid,
          old_display_name: target["Display Name"],
          new_display_name: requestedDisplayName,
        },
        created_at: new Date().toISOString(),
      });
      if (logError) {
        console.error(
          "Failed to record activity log for superadmin user display name change:",
          logError,
        );
      }
    }

    return jsonResponse(200, { result: data });
  }

  if (action === "list-requests") {
    if (claims.role !== "SuperAdmin") {
      return jsonResponse(403, { error: "ต้องใช้บัญชี SuperAdmin" });
    }
    const requests: JsonObject[] = [];
    for (let from = 0; ; from += 500) {
      const { data, error } = await supabase
        .from("superadmin_user_change_requests")
        .select(
          "id, created_at, target_uid, target_display_name, current_display_name, old_role, current_status, requested_display_name, requested_role, requested_status, requester_id, requester_is_system, requester_display_name, status",
        )
        .order("created_at", { ascending: false })
        .range(from, from + 499);
      if (error) {
        console.error("Failed to list SuperAdmin user change requests.", error);
        return jsonResponse(500, { error: "ไม่สามารถโหลดคำขอยืนยันได้" });
      }
      requests.push(...data);
      if (data.length < 500) break;
    }
    return jsonResponse(200, { requests });
  }

  if (action === "resolve-request") {
    if (claims.role !== "SuperAdmin") {
      return jsonResponse(403, { error: "ต้องใช้บัญชี SuperAdmin" });
    }
    const requestId = payload.requestId;
    const decision = payload.decision;
    if (
      typeof requestId !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        .test(requestId) ||
      (decision !== "approved" && decision !== "rejected")
    ) {
      return jsonResponse(400, { error: "ข้อมูลการยืนยันไม่ถูกต้อง" });
    }
    const { data, error } = await supabase.rpc(
      "resolve_superadmin_user_change_request",
      {
        p_request_id: requestId,
        p_actor_id: claims.sub,
        p_actor_is_system: isSystemAccount,
        p_decision: decision,
      },
    );
    if (error) {
      console.error("Failed to resolve a SuperAdmin user change request.", error);
      return jsonResponse(409, { error: error.message });
    }
    return jsonResponse(200, { requestId, status: data });
  }

  if (action === "list-activity-logs") {
    if (claims.role !== "SuperAdmin") {
      return jsonResponse(403, { error: "ต้องใช้บัญชี SuperAdmin" });
    }

    const page = Math.max(1, typeof payload.page === "number" ? Math.floor(payload.page) : 1);
    const pageSize = Math.min(100, Math.max(1, typeof payload.pageSize === "number" ? Math.floor(payload.pageSize) : 5));
    const search = typeof payload.search === "string" ? payload.search.trim() : "";
    const actionType = typeof payload.actionType === "string" ? payload.actionType.trim() : "ALL";
    const actorRole = typeof payload.actorRole === "string" ? payload.actorRole.trim() : "ALL";
    const startDate = typeof payload.startDate === "string" ? payload.startDate.trim() : "";
    const endDate = typeof payload.endDate === "string" ? payload.endDate.trim() : "";

    let query = supabase
      .from("activity_logs")
      .select(
        "id, actor_username, actor_role, actor_display_name, action_type, action_title, description, target_id, metadata, created_at",
        { count: "exact" },
      );

    if (actorRole && actorRole !== "ALL") {
      query = query.eq("actor_role", actorRole);
    }

    if (actionType && actionType !== "ALL") {
      if (actionType.includes(",")) {
        const types = actionType.split(",").map((s) => s.trim()).filter(Boolean);
        query = query.in("action_type", types);
      } else {
        query = query.eq("action_type", actionType);
      }
    }

    if (startDate) {
      const startIso = startDate.includes("T") ? startDate : `${startDate}T00:00:00+07:00`;
      query = query.gte("created_at", startIso);
    }

    if (endDate) {
      const endIso = endDate.includes("T") ? endDate : `${endDate}T23:59:59.999+07:00`;
      query = query.lte("created_at", endIso);
    }

    if (search) {
      const pattern = `%${search}%`;
      query = query.or(
        `actor_username.ilike.${pattern},actor_display_name.ilike.${pattern},description.ilike.${pattern},target_id.ilike.${pattern},action_title.ilike.${pattern}`,
      );
    }

    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;

    query = query.order("created_at", { ascending: false }).range(from, to);

    const { data: logs, count, error } = await query;
    if (error) {
      console.error("Failed to list activity logs.", error);
      return jsonResponse(500, { error: "ไม่สามารถโหลดข้อมูลประวัติการกระทำได้" });
    }

    const totalCount = count ?? 0;
    const totalPages = Math.ceil(totalCount / pageSize);

    return jsonResponse(200, {
      logs: logs ?? [],
      totalCount,
      page,
      pageSize,
      totalPages,
    });
  }

  return jsonResponse(400, { error: "Unknown user management action." });
});
