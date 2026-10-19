type AssignmentInput = {
  status: unknown;
  technicianTeam: unknown;
  start: unknown;
  end: unknown;
};

export type AssignmentValidationError =
  | "team_required"
  | "schedule_required_or_invalid"
  | "team_schedule_not_allowed";

export type TicketDeviceStatusError =
  | "rejected_ticket_requires_rejected_devices"
  | "finished_ticket_has_invalid_devices"
  | "pending_ticket_requires_pending_device"
  | "validating_status_not_allowed";

export type TicketDeviceUpdate = {
  deviceid: number;
  status: string;
};

export function validateTicketDeviceStatuses(
  ticketStatus: unknown,
  deviceStatuses: unknown[],
): TicketDeviceStatusError | null {
  if (
    ticketStatus === "validating" || deviceStatuses.includes("validating")
  ) return "validating_status_not_allowed";
  if (
    ticketStatus === "rejected" &&
    deviceStatuses.some((status) => status !== "rejected")
  ) return "rejected_ticket_requires_rejected_devices";
  if (
    ticketStatus === "finish" &&
    deviceStatuses.some((status) => status !== "rejected" && status !== "finish")
  ) return "finished_ticket_has_invalid_devices";
  if (
    ticketStatus === "pending" &&
    !deviceStatuses.some((status) => status === "pending")
  ) return "pending_ticket_requires_pending_device";
  return null;
}

export function validatePendingTicketUpdate(
  ticketStatus: unknown,
  technicianTeam: unknown,
  start: unknown,
  end: unknown,
  devices: TicketDeviceUpdate[],
): TicketDeviceStatusError | AssignmentValidationError | null {
  const assignmentError = validateAssignmentInput({
    status: ticketStatus,
    technicianTeam,
    start,
    end,
  });
  if (assignmentError) return assignmentError;
  return validateTicketDeviceStatuses(
    ticketStatus,
    devices.map((device) => device.status),
  );
}

export function validateAssignmentInput(
  input: AssignmentInput,
): AssignmentValidationError | null {
  if (input.status === "pending") {
    if (
      typeof input.technicianTeam !== "string" ||
      input.technicianTeam.trim() === ""
    ) return "team_required";

    if (
      typeof input.start !== "string" ||
      !Number.isFinite(Date.parse(input.start)) ||
      typeof input.end !== "string" ||
      !Number.isFinite(Date.parse(input.end)) ||
      Date.parse(input.start) > Date.parse(input.end)
    ) return "schedule_required_or_invalid";

    return null;
  }

  if (
    input.technicianTeam != null || input.start != null || input.end != null
  ) return "team_schedule_not_allowed";

  return null;
}

export function accessPeriodContainsSchedule(
  starts: unknown,
  ends: unknown,
  scheduleStart: unknown,
  scheduleEnd: unknown,
): boolean {
  if (
    !Array.isArray(starts) || !Array.isArray(ends) ||
    starts.length !== ends.length ||
    typeof scheduleStart !== "string" ||
    typeof scheduleEnd !== "string"
  ) return false;

  const requestedStart = Date.parse(scheduleStart);
  const requestedEnd = Date.parse(scheduleEnd);
  if (
    !Number.isFinite(requestedStart) || !Number.isFinite(requestedEnd) ||
    requestedStart > requestedEnd
  ) return false;

  return starts.some((start, index) => {
    const end = ends[index];
    if (typeof start !== "string" || typeof end !== "string") return false;
    const accessStart = Date.parse(start);
    const accessEnd = Date.parse(end);
    return Number.isFinite(accessStart) && Number.isFinite(accessEnd) &&
      requestedStart >= accessStart && requestedEnd <= accessEnd;
  });
}

export type AssignmentRpcFailure = {
  category:
    | "schedule_mismatch"
    | "not_found"
    | "rpc_schema_cache"
    | "rpc_ambiguous_overload"
    | "rpc_missing"
    | "database";
  status: number;
  message: string;
};

export function classifyAssignmentRpcFailure(error: {
  code?: unknown;
  message?: unknown;
}): AssignmentRpcFailure {
  const code = typeof error.code === "string" ? error.code : "";
  const message = typeof error.message === "string" ? error.message : "";

  if (message === "The selected team does not have that access period.") {
    return {
      category: "schedule_mismatch",
      status: 400,
      message: "ช่วงเวลาที่เลือกไม่อยู่ในสิทธิ์เข้าใช้งานของทีมช่าง กรุณาเลือกทีมและช่วงเวลาใหม่",
    };
  }
  if (message === "Invalid repair request assignment.") {
    return {
      category: "schedule_mismatch",
      status: 400,
      message: "กรุณาเลือกทีมช่างและกำหนดช่วงเวลาซ่อมที่ถูกต้องสำหรับสถานะรอซ่อม",
    };
  }
  if (message === "Repair request was not found.") {
    return {
      category: "not_found",
      status: 404,
      message: "ไม่พบคำร้องนี้แล้ว กรุณาโหลดรายการใหม่ก่อนบันทึก",
    };
  }
  if (code === "PGRST202") {
    return {
      category: "rpc_schema_cache",
      status: 503,
      message: "ระบบยังโหลดข้อกำหนดการบันทึกไม่ครบ กรุณาลองอีกครั้งภายหลัง",
    };
  }
  if (code === "PGRST203") {
    return {
      category: "rpc_ambiguous_overload",
      status: 503,
      message: "ระบบพบข้อกำหนด RPC ซ้ำ กรุณาแจ้งผู้ดูแลระบบพร้อมรหัสตรวจสอบ",
    };
  }
  if (code === "42883") {
    return {
      category: "rpc_missing",
      status: 503,
      message: "ระบบไม่พบ RPC สำหรับบันทึก กรุณาแจ้งผู้ดูแลระบบพร้อมรหัสตรวจสอบ",
    };
  }
  return {
    category: "database",
    status: 500,
    message: "บันทึกคำร้องและการมอบหมายทีมไม่สำเร็จ กรุณาลองใหม่อีกครั้ง",
  };
}
