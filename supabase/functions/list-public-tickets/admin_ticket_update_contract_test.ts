import {
  accessPeriodContainsSchedule,
  classifyAssignmentRpcFailure,
  validatePendingTicketUpdate,
  validateAssignmentInput,
} from "./admin_ticket_update_contract.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Assertion failed: ${JSON.stringify(actual)} !== ${
        JSON.stringify(expected)
      }`,
    );
  }
}

Deno.test("pending assignment requires a team and a valid schedule", () => {
  assertEquals(
    validateAssignmentInput({
      status: "pending",
      technicianTeam: null,
      start: "2026-10-21T17:00:00.000Z",
      end: "2026-10-22T17:00:00.000Z",
    }),
    "team_required",
  );

  assertEquals(
    validateAssignmentInput({
      status: "pending",
      technicianTeam: "Team A",
      start: null,
      end: null,
    }),
    "schedule_required_or_invalid",
  );

  assertEquals(
    validateAssignmentInput({
      status: "pending",
      technicianTeam: "Team A",
      start: "2026-10-22T17:00:00.000Z",
      end: "2026-10-21T17:00:00.000Z",
    }),
    "schedule_required_or_invalid",
  );

  assertEquals(
    validateAssignmentInput({
      status: "pending",
      technicianTeam: "Team A",
      start: "2026-10-21T17:00:00.000Z",
      end: "2026-10-22T17:00:00.000Z",
    }),
    null,
  );
});

Deno.test("non-pending status cannot carry team assignment or schedule", () => {
  assertEquals(
    validateAssignmentInput({
      status: "finish",
      technicianTeam: null,
      start: null,
      end: null,
    }),
    null,
  );
  assertEquals(
    validateAssignmentInput({
      status: "finish",
      technicianTeam: "Team A",
      start: null,
      end: null,
    }),
    "team_schedule_not_allowed",
  );
});

Deno.test("schedule must be contained in one team access period", () => {
  const starts = ["2026-10-21T17:00:00.000Z"];
  const ends = ["2026-10-25T17:00:00.000Z"];
  assertEquals(
    accessPeriodContainsSchedule(
      starts,
      ends,
      "2026-10-21T17:00:00.000Z",
      "2026-10-25T17:00:00.000Z",
    ),
    true,
  );
  assertEquals(
    accessPeriodContainsSchedule(
      starts,
      ends,
      "2026-10-21T17:00:00.000Z",
      "2026-10-26T00:00:00.000Z",
    ),
    false,
  );
});

Deno.test("pending ticket with two pending devices and a team is valid", () => {
  assertEquals(
    validatePendingTicketUpdate(
      "pending",
      "Team A",
      "2026-10-21T17:00:00.000Z",
      "2026-10-22T17:00:00.000Z",
      [{ deviceid: 1, status: "pending" }, { deviceid: 2, status: "pending" }],
    ),
    null,
  );
});

Deno.test("pending ticket rejects missing schedule, team, or pending device", () => {
  const devices = [
    { deviceid: 1, status: "pending" },
    { deviceid: 2, status: "pending" },
  ];
  assertEquals(
    validatePendingTicketUpdate("pending", "Team A", null, null, devices),
    "schedule_required_or_invalid",
  );
  assertEquals(
    validatePendingTicketUpdate(
      "pending",
      null,
      "2026-10-21T17:00:00.000Z",
      "2026-10-22T17:00:00.000Z",
      devices,
    ),
    "team_required",
  );
  assertEquals(
    validatePendingTicketUpdate(
      "pending",
      "Team A",
      "2026-10-21T17:00:00.000Z",
      "2026-10-22T17:00:00.000Z",
      [{ deviceid: 1, status: "finish" }, { deviceid: 2, status: "rejected" }],
    ),
    "pending_ticket_requires_pending_device",
  );
});

Deno.test("RPC failures return actionable, sanitized categories", () => {
  assertEquals(
    classifyAssignmentRpcFailure({
      code: "P0001",
      message: "The selected team does not have that access period.",
    }),
    {
      category: "schedule_mismatch",
      status: 400,
      message: "ช่วงเวลาที่เลือกไม่อยู่ในสิทธิ์เข้าใช้งานของทีมช่าง กรุณาเลือกทีมและช่วงเวลาใหม่",
    },
  );
  assertEquals(
    classifyAssignmentRpcFailure({
      code: "PGRST202",
      message: "raw schema cache text must not reach the client",
    }).category,
    "rpc_schema_cache",
  );
  assertEquals(
    classifyAssignmentRpcFailure({ code: "PGRST203", message: "redacted" })
      .category,
    "rpc_ambiguous_overload",
  );
  assertEquals(
    classifyAssignmentRpcFailure({ code: "42883", message: "redacted" })
      .category,
    "rpc_missing",
  );
  assertEquals(
    classifyAssignmentRpcFailure({
      code: "XX000",
      message: "private SQL diagnostic must not reach the client",
    }).message,
    "บันทึกคำร้องและการมอบหมายทีมไม่สำเร็จ กรุณาลองใหม่อีกครั้ง",
  );
});
