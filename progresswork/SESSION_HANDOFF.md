# KUFixIT work checkpoint

## Objective
- Fix narrow-screen User/SuperAdmin and Admin technician-management layouts.
- Complete technician work-report approval, device-level results/photos, schedule handling, ticket assignment removal, and repair history.
- Keep all production migrations and deployments unapplied until the owner explicitly authorizes them.

## Repository state and preservation
- No `AGENTS.md` was found. `progresswork/worklist.txt` and supplied screenshots were reviewed.
- Workspace was already dirty before this task. Existing modifications/untracked files were preserved; no revert or cleanup was performed.
- No production schema changes or function deployments were made.

## Owner-confirmed behavior
- History columns: work period start/end, team name, only successful devices for that history index, technician comment, and result photos.
- Device results are per pending device. Successful devices require one photo; failed/late devices have no photo and stay `pending`.
- All-failed report uses comment `ซ่อมไม่สำเร็จ`; mixed results require a technician comment.
- Photo filename number represents that device's row index; at most one photo per successful device.
- Storage quota is cumulative per ticket: total device count × 2 MB.
- FixList schedule fields: `next_fix_date_start` and `next_fix_date_end`, both `timestamptz`.
- Admin approval removes the ticket from technician assignment tables. If pending devices remain, Admin can assign the ticket again.

## Changes made
- `lib/gui/userManager.dart`: responsive user cards for narrow layouts while retaining desktop table.
- `lib/gui/technicianManager.dart`: one team per page and responsive pagination.
- `lib/gui/ticketMonitor.dart`: FixList repair range display/edit; history comments, successful-only devices, and per-device result photos; no manual refresh controls.
- `lib/gui/workList.dart`: per-device success/failure selection and one photo per successful device; previous/review reports list successful device IDs and result photos.
- `lib/gui/technician_report_rules.dart`: pure report validation and all-failure comment rule.
- `supabase/functions/technician-work/index.ts`: device result validation, indexed photo upload, RPC submission, signed result photo URLs, request size for multiple images, ambiguous RPC-timeout lookup and safe cleanup.
- `supabase/functions/list-public-tickets/index.ts`: range schedule API and per-device history photo mapping.
- New local-only migration `supabase/migrations/20261022000000_technician_device_result_history_and_fixlist_schedule.sql`: FixList schedule columns, per-device report results, restricted RPCs, atomic approval updates, successful-device status and assignment removal, cumulative ticket photo quota.
- Added `test/gui/technician_report_rules_test.dart`; retained narrow-layout tests in `test/gui/user_manager_responsive_test.dart` and `test/gui/technician_manager_test.dart`.

## Verification actually run
- `dart format` on changed Dart files: completed.
- Flutter analyze on changed pages/helpers/tests: no issues found.
- Flutter tests: 10 passed across technician report rules, UserManager responsive layout, and technician manager responsive layout.
- `git diff --check`: clean.
- No Deno, Supabase CLI, or PostgreSQL client was available in PATH. Edge Function type-check, SQL parse/apply, database rollback tests, emulator interaction, and Android build were not run.

## Important production/dependency status
- The new migration is local and unapplied. Its required prior report/assignment migrations and existing dynamic ticket-table columns were checked read-only against the remote metadata; see the follow-up findings below.
- Do not run `supabase db push`, apply this migration, or deploy `technician-work` / `list-public-tickets` until migration history/schema is checked and the owner authorizes the production action.
- Current workspace includes unrelated pre-existing changes, including auth/realtime and several migrations; preserve them.

## Follow-up preflight findings (read-only, current project)
- Supabase CLI 2.121.0 linked ref, `.env` URL host ref, and `.temp/linked-project.json` ref agree: `vmgzyenvqsfhcuropzjd`. No credential-bearing URL was emitted.
- Remote `migration list` and latest `db push --dry-run --linked` agree: the sole pending migration is `20261022000000_technician_device_result_history_and_fixlist_schedule.sql`; all active local migration versions through `20261021000000` are recorded remotely.
- Active `supabase/migrations/` has one file for version `20261017000003`; the same-version delete-technician SQL is archived. Remote has `maintenance_users_display_name_key`, and the deleted-technician table/function/triggers are present; version `20261017000006` is also recorded applied and contains the same non-idempotent deletion DDL as the archived candidate. This supports the active `20261017000003_unique_maintenance_technician_display_names.sql` as the applied variant. Do not edit migration history.
- Remote columns: FixList schedule start/end already exist as nullable `timestamptz`; technician report work-period columns and `history_index` exist; `device_results` is absent. Technician `start_time`/`end_time` are `timestamptz[]`.
- Remote FixList range CHECK is absent; aggregate check found 2 FixList rows and 0 invalid ranges. Technician report table has no rows.
- Remote report checks include the legacy generic photo/failure checks plus named comment/photo path/photo-name checks. Migration was amended to drop/recreate those exact existing names and allow both the legacy and new indexed photo paths.
- Remote `admin_update_fixlist_and_assign_team` is the old 9-argument version and has service-role execute. New migration creates the 11-argument schedule version and revokes service-role access to the stale 9-argument contract. It also revokes direct report INSERT from service-role so the old deployed technician function cannot write legacy-shape reports during the transition.
- Remote `admin_review_technician_work_report` is SECURITY DEFINER, executable only by `service_role`; report RLS is enabled with no client policies. Realtime receive policy is SELECT-only for anon/authenticated on the six fixed invalidation topics. The invalidation trigger function is SECURITY DEFINER and references the fixed topic without a `payload` field.
- Remote `technician-work-results` bucket is private, accepts JPEG/PNG/WebP, and has a 2 MiB per-object limit; the new RPC checks the separate cumulative per-ticket quota. Storage policy is service-role-only.
- All 2 current dynamic ticket tables have required result/history columns and invalidation triggers; all 2 current technician assignment tables have invalidation triggers.
- Read-only Edge Function list reports `list-public-tickets` v33 and `technician-work` v3 on the target project. The local function source needs deploying after the migration, but no deployment occurred.
- Deno 2.9.6 type-check now passes for both changed Edge Functions. The first type-check exposed six errors (ticket const reassignment, removed helper use, and account union narrowing); these were fixed. `deno fmt --check` reports the two files are not formatted; no whole-file reformat was applied to avoid unrelated churn.
- No Docker/local database or staging target was available. No SQL migration was executed, and no report workflow was tested against production or staging. Android/emulator and test-account flow remains untested.
- Final dry-run after migration edits still selected only `20261022000000_technician_device_result_history_and_fixlist_schedule.sql`; no push/deploy was performed.
- Waiting for explicit owner approval before applying the migration and deploying the two required functions. Because old deployed function versions remain active until rollout, the migration intentionally blocks their outdated write contracts; deploy immediately after migration if approved. No workflow test accounts were supplied, so real end-to-end test execution still needs an approved test account/environment.

## Remaining work (pre-approval snapshot; superseded by Production update below)
1. Obtain explicit owner confirmation for applying the single pending migration to project `vmgzyenvqsfhcuropzjd`; explain the short transition window where old `list-public-tickets` assignment writes and old `technician-work` report inserts will be blocked until new Edge versions deploy.
2. Apply only that migration after confirmation, then verify migration history, columns/checks/RPC signatures/grants, and `device_results` behavior.
3. Deploy only `list-public-tickets` and `technician-work`, then verify their versions and API contract.
4. Use approved test accounts/data on Android emulator or staging to test schedule assignment, success, all-failure/timeout, mixed results, approval/rejection, status/history/photo paths, ticket assignment removal, and rollback/error handling.
5. Re-run Flutter tests/analyze, Deno check, and `git diff --check`; preserve unrelated dirty files.

## Production update (2026-10-19)
- Owner explicitly confirmed applying the single pending migration and deploying the two dependent functions.
- Final ref check: `.env` SUPABASE_URL host and `supabase/.temp/project-ref`/linked project all resolve to `vmgzyenvqsfhcuropzjd`; secret-bearing URL not printed.
- Final remote migration list and `db push --dry-run --linked` showed exactly one pending migration: `20261022000000_technician_device_result_history_and_fixlist_schedule.sql`.
- Applied that migration successfully with `supabase db push --linked`; no other migration or seed was pushed.
- Post-apply read-only metadata check confirmed migration recorded; FixList schedule columns are timestamptz with range constraint; technician_work_reports.device_results is jsonb; create-report RPC is executable by service_role; new 11-argument assignment RPC is executable while old 9-argument RPC is not; direct service_role INSERT on technician_work_reports is revoked; report RLS remains enabled with zero policies.
- Deployed only `list-public-tickets` and `technician-work`. Remote function list confirms both ACTIVE: list-public-tickets v34 (was v33), technician-work v4 (was v3). Docker warning was emitted by CLI, but deployment completed successfully.
- Re-ran `deno check` for both deployed function sources: passed. `git diff --check`: passed. Flutter tests/analyze previously passed (10 tests); they were not rerun in this production continuation because application files were unchanged.
- Production workflow has NOT been exercised with real accounts/data. No staging/test account or Android emulator interaction was available. Do not claim success/failure workflow end-to-end. Remaining verification: approved test data/accounts and emulator test of schedule assignment, success/mixed/all-failure/late reports, review approval/rejection, status/history/photos, assignment removal, and failure/rollback paths. No Flutter app deployment was done.



## Workflow test continuation (2026-10-19)
- Rechecked workspace `git status`; existing dirty and untracked files were preserved. No code/data changes were made during this continuation.
- Current environment checks: `.env` exists and its Supabase URL had previously been verified against the linked production project; no values were printed. `supabase/config.toml` exists. A debug APK exists at `build/app/outputs/flutter-apk/app-debug.apk` (presence does not establish that it includes the latest sources). `android/app/build.gradle.kts` exists. `adb` is unavailable in PATH. `flutter devices` produced no output and was stopped after 90 seconds; no emulator/device was confirmed.
- Searched repository filenames for staging/test account/fixture/e2e artifacts (excluding `.env*`); only generic `supabase/seed.sql` appeared. No staging project, approved test account, or approved test ticket was identified. The only configured/linked project is production. No production ticket or user was read or changed.
- Workflow end-to-end tests were not run. Blocked pending owner-provided staging/test environment and test records, or explicit details for specifically approved production test records. Credentials must be entered by the owner on the emulator; never send passwords/tokens in chat or logs.
- Next: after the owner supplies an approved environment and test records, configure/select that environment without exposing credentials, install/build the intended debug app, confirm an Android emulator is online, then run the sequence in the active user request. Record each case as pass/fail/not run and only use approved test records. Do not repeat migration apply or function deployment.

## Owner response (2026-10-19)
- Owner confirmed: there is currently no staging or test data.
- E2E workflow testing remains blocked. Do not use production user/ticket records for testing without explicit authorization identifying the records and permitted operations.
- Resume when a staging project with isolated test account/ticket/device records is available. Also make Android SDK/ADB available and confirm a running emulator. Owner should enter credentials directly in the app; do not request or record them in chat/logs.

## Staff-login smoke-test continuation (2026-10-19)
- Owner requested a read-only staff-login smoke test for `SuperAdmin1`, `SuperAdmin2`, and `techteam`; the requested expected roles are SuperAdmin, SuperAdmin, and Technician. Owner must enter passwords directly in the app. No passwords, tokens, personal data, or raw credential-bearing logs were collected or recorded.
- Any password previously shared in chat must be changed before the test is resumed.
- Read-only project check found `.env` `SUPABASE_URL` host `https://vmgzyenvqsfhcuropzjd.supabase.co`, matching the project ref recorded in the earlier handoff. That handoff identifies this as the production project. No app login or database action was performed; the app's runtime connection was therefore not verified in this run.
- Android SDK `adb.exe` exists at `C:\Users\few\AppData\Local\Android\Sdk\platform-tools\adb.exe`, but `adb version` could start while `adb devices -l` failed because the ADB server could not start (`could not read ok from ADB Server`; unable to connect to daemon). No emulator was confirmed online. Per the smoke-test instructions, testing stopped here.
- Results for all three accounts: NOT RUN. Login, role/navigation, Realtime stability, logout/session cleanup, and channel cleanup were not tested. No claim is made about staff-login behavior, cross-client workflows, or Google OAuth.
- Before resuming: repair the local ADB server/SDK setup and start an Android emulator; confirm it appears `device` in `adb devices -l`. Verify the intended Supabase target in the running app before entering credentials. The available configured target is production, so restrict any production run to owner-entered staff login, main screen/role navigation, Realtime connection state, and logout/channel/session cleanup. Record sanitized observations only.
- Remaining test work: run the staff-login smoke sequence one account at a time and record pass/fail/not run separately. Staging/test ticket workflows remain untested because no staging/test data is available. Google login remains untested. Technician report, review/approval, history, and photo workflows require an isolated staging/test project with test records; do not exercise them against production as part of this smoke test.

## Admin ticket update 500 investigation (2026-10-19)
- Read-only production metadata confirms project `vmgzyenvqsfhcuropzjd`, `list-public-tickets` ACTIVE v34, and the 11-argument `admin_update_fixlist_and_assign_team` signature matches the local RPC parameter names/types. The old 9-argument overload also exists but is revoked from `service_role`; no client table-write grants were changed. PostgreSQL timezone is UTC.
- Code evidence identifies a schedule-boundary defect: Flutter serialized Bangkok calendar-midnight dates using local `DateTime.toIso8601String()` without an offset. The Edge Function/DB therefore could interpret an end boundary as UTC midnight, seven hours later than the team's stored `+07:00` end boundary; the RPC's exact containment check rejects it. This is a confirmed contract defect and a strong cause for the reported RPC 500, but the exact failed request cannot be attributed without request logs/test record.
- Source changes are local only: add explicit Bangkok-midnight-to-UTC serialization; server validates the requested interval against the selected team's exact access windows before RPC; RPC errors classify schedule mismatch, missing ticket, PostgREST RPC/schema-cache errors, and internal errors; server logs only category and allow-listed error code, with no ticket ID/details; UI displays safe Edge Function response messages instead of raw exception text.
- No production write or ticket mutation was attempted. No migration was applied and no function was deployed. PostgREST cache itself and the failed invocation logs could not be read with the available Supabase CLI commands; production version remains v34 pending owner approval for deployment.
- Verification actually run: Deno contract tests 4 passed; Deno type-check passed for `list-public-tickets`; Flutter schedule/error-message tests 4 passed; Flutter analyze on changed Dart files reports no issues; `git diff --check` clean. No RPC write test, workflow test, or staging test was run because no approved staging/test records exist.
- To ship this fix, request owner approval to deploy only `list-public-tickets` to `vmgzyenvqsfhcuropzjd` (expected next version v35). No migration is needed. Risk is limited to corrected schedule timestamp interpretation and more precise client error statuses/messages; unknown database failures remain sanitized 500s. Do not deploy until approval is received.

## Admin-ticket validation coverage update (2026-10-19)
- Exact UI call path: the message `Repair request and team assignment could not be updated.` is emitted only when `ticketMonitor.dart` invokes `list-public-tickets` with action `admin-update-ticket` and the 11-argument RPC returns an error. That invoke occurs after the edit dialog returns saved changes; ordinary page loading does not enter this branch.
- Final local test run: Flutter 8 tests passed (Bangkok boundary serialization, HTTP validation error display, fetch timeout/transport failure redaction, relay error redaction, generic 500 redaction, and existing function-error tests); Flutter analyze reports no issues. Deno 4 assignment contract tests passed for required/missing team, valid/missing/reversed schedules, non-pending behavior, access-range containment, and sanitized RPC categories. Deno type-check and `git diff --check` passed.
- The FetchException test covers the SDK's transport failure path, which can represent timeout/network failure; it does not claim a real network timeout was induced.
- No production request that writes data was sent. No Edge Function logs were available through the installed CLI, so the exact historic failed request is still not proven. Keep local fix undeployed until owner explicitly approves deployment of only `list-public-tickets` to `vmgzyenvqsfhcuropzjd`; no migration or app deployment is required/planned.

## Admin ticket fix deployment (2026-10-19)
- Owner confirmed deployment. Before deployment, `.env` URL host and linked project ref both matched `vmgzyenvqsfhcuropzjd`; project ref was not derived from credentials.
- Pre-deploy `functions list` showed `list-public-tickets` ACTIVE v34. Deployed only `list-public-tickets`; no migration, other function, or Flutter app was deployed.
- Post-deploy read-only `functions list` confirms `list-public-tickets` ACTIVE v35. CLI reported Docker not running, but upload completed successfully.
- Post-deploy `git diff --check` passed. Existing local Deno and Flutter test/type-check results remain as recorded above; no production ticket write or RPC workflow test was performed.
- Production changes are now deployed, but the exact original failing request remains unconfirmed because no function log access or approved staging/test record was available. Validate with an approved non-production ticket when test data is provisioned; do not modify production tickets to test.

## Pending ticket save bug continuation (2026-10-19)
- Inspected the Ticket Monitor save path: dialog emits ticket status, selected technician team, next repair range, and every child device; Edge Function validates then calls the assignment RPC and previously updated child rows one request at a time afterward.
- Production evidence carried from the prior read-only preflight: two overloads of `admin_update_fixlist_and_assign_team` (9 and 11 arguments) exist. PostgREST may reject same-name overloads with `PGRST203`; stale RPC cache/signature may produce `PGRST202`. No logs for the exact screenshot request were available, so the precise historical error remains unconfirmed. The dialog derives schedule from the selected team access period; the RPC also requires a team and valid schedule for pending.
- Workspace-only changes in this continuation: `supabase/functions/list-public-tickets/admin_ticket_update_contract.ts` distinguishes schedule, schema-cache, ambiguous-overload, and missing-RPC errors and validates the pending-ticket/two-device status case; `index.ts` now calls a unique atomic RPC contract, logs allow-listed error code/category plus correlation UUID, and returns the UUID; `ticket_update_error_message.dart` shows only valid UUID correlation IDs for server failures; corresponding Deno/Dart tests were expanded.
- Added local unapplied migration `supabase/migrations/20261023000000_atomic_admin_ticket_assignment.sql`. It defines service-role-only `admin_update_ticket_assignment_atomic`, validates the device list and status/schedule, updates FixList + the ticket's dynamic child table + team assignment in one database transaction, and notifies PostgREST to reload schema. It uses the existing assignment sync function. This migration was not parsed/applied against a database and requires careful SQL review before production.
- Verification: `git diff --check` passed after changes. `deno` is not available in PATH, so Deno tests/type-check did not run. Flutter test and Dart format commands were started but hung with no output; they were interrupted, so Flutter tests/format are NOT verified. No DB, staging, emulator, production data write, migration apply, or deployment was run.
- Before production: review the new SQL against actual remote child-table column types/triggers and the `sync_maintenance_team_ticket_assignment` signature; run Deno test/check and Flutter tests/analyze when runtimes work; exercise atomic rollback against local/staging. Obtain explicit owner approval for migration `20261023000000_atomic_admin_ticket_assignment.sql` and deployment of only `list-public-tickets` to `vmgzyenvqsfhcuropzjd`; do not apply/deploy without that approval. After rollout, verify function version and test with approved non-production records. There is no staging/test data currently, so do not test with production tickets.

## Production apply attempt and schema reconciliation update (2026-10-19)
- Owner said “ทำเลย”. Fresh preflight confirmed `.env` SUPABASE_URL host and linked ref both match `vmgzyenvqsfhcuropzjd`; remote migration history and dry-run show only `20261023000000_atomic_admin_ticket_assignment.sql` pending.
- Read-only metadata surfaced a real schema inconsistency: 2 dynamic ticket tables are referenced by FixList and both have the invalidation trigger; only one has scalar `next_fix_date timestamptz`. The other lacks the column. The migration was updated to add nullable `next_fix_date timestamptz` to existing FixList-linked dynamic ticket tables before installing the atomic RPC. Existing column is scalar on the table where present; no array-typed schedules were found.
- Read-only remote metadata confirmed `sync_maintenance_team_ticket_assignment(text,text,text,boolean)` is SECURITY DEFINER and executable by service_role; old assignment RPC overloads (9 and 11 arguments) remain, and only the 11-arg function is service_role executable. The deployed `list-public-tickets` is still ACTIVE v35.
- Latest dry-run after reconciliation again lists only the single migration above. Flutter focused tests pass (8 total: schedule serialization, safe server errors/correlation ID). Flutter analyze on 4 relevant Dart source/test files reports no issues. `git diff --check` passes. Deno tests/type-check remain unrun because Deno is not installed.
- Attempted `supabase db push --linked`, but automatic approval review rejected the production mutation, stating the user’s “ทำเลย” did not explicitly approve this new migration after scope expanded to include nullable column reconciliation plus a new atomic RPC. The command was rejected before execution. No migration was applied and no function deployed. Followed the rejection; did not try a workaround.
- Current production status after rejection: migration remains pending; `list-public-tickets` remains v35. No production data was read beyond schema metadata or written. No ticket workflow/end-to-end test was performed.
- Blocked next step: request explicit owner confirmation to apply exactly `20261023000000_atomic_admin_ticket_assignment.sql` on project `vmgzyenvqsfhcuropzjd` (includes adding the missing nullable device schedule column and creating a service-role-only atomic RPC), then deploy only `list-public-tickets` after post-apply verification. Auto-review requires that specific confirmation; do not retry apply/deploy before it.

## Owner-approved migration application (2026-10-19)
- Owner explicitly approved applying migration `20261023000000_atomic_admin_ticket_assignment.sql` only.
- Fresh ref check: `.env` URL host and linked Supabase project both match `vmgzyenvqsfhcuropzjd`. Fresh dry-run listed that migration as the only pending item; no seeds or roles.
- `supabase db push --linked` applied only `20261023000000_atomic_admin_ticket_assignment.sql` successfully.
- Post-apply metadata check: migration appears in remote history; `admin_update_ticket_assignment_atomic` exists with the expected 12-argument signature, is SECURITY DEFINER, executable by service_role, and not executable by anon/authenticated. Both FixList-linked dynamic ticket tables now have scalar `next_fix_date timestamptz`.
- Function deployment was not approved by the latest owner reply (which authorized apply only). Read-only function list confirms `list-public-tickets` remains ACTIVE v35. No ticket data was written or used for testing.
- Prior local test results remain: focused Flutter tests 8 passed; Flutter analyze 4 items passed; `git diff --check` passed. Deno contract tests/type-check not run because Deno is unavailable. No staging test account/data or emulator workflow test.
- Next step: obtain explicit approval to deploy only `list-public-tickets` to `vmgzyenvqsfhcuropzjd`; then verify the new function version and, when approved test data is available, test pending assignment and atomic rollback behavior. Do not claim the live UI bug is resolved until the function is deployed and workflow is tested.

## Owner-approved Edge Function deployment (2026-10-19)
- Owner explicitly approved deployment of all necessary components after the migration was applied.
- Fresh pre-deploy ref check confirmed `.env` URL host and linked ref both match `vmgzyenvqsfhcuropzjd`. Pre-deploy dry-run showed the remote database up to date with no pending migrations; `list-public-tickets` was ACTIVE v35.
- Deployed only `list-public-tickets` to `vmgzyenvqsfhcuropzjd`. Supabase CLI reported upload complete; Docker was not running but did not prevent deployment.
- Post-deploy read-only function listing confirms `list-public-tickets` ACTIVE v36. Post-deploy `db push --dry-run --linked` reports `upToDate: true`, no pending migrations.
- Migration `20261023000000_atomic_admin_ticket_assignment.sql` was applied in the prior owner-approved step and verified: atomic RPC available, SECURITY DEFINER, execute only for service_role, and all FixList-linked dynamic ticket tables have scalar `next_fix_date`.
- No production ticket was written or used as test data. No workflow/E2E test was performed because there is no staging/test data or approved test record. The live save workflow is deployed but not yet verified end-to-end.
- Focused Flutter tests 8 passed; Flutter analysis passed for 4 targeted items; `git diff --check` passed. Deno tests/type-check were not run because Deno is unavailable. Supabase function deploy completed successfully; no claim of Deno test pass.

## Activity Log Real Data Sync & Edge Function Deployment (2026-10-20)
- Applied migration `20261024000005_sync_real_activity_logs.sql` to linked remote project `vmgzyenvqsfhcuropzjd`.
- Cleared mock activity logs and synced 100% real records:
  - Admin: `fewfast` (`u_5435312295`)
  - Technician: `ทีมช่าง techteam` (`t_7892264770`)
  - SuperAdmin: `SuperAdmin1`
  - Real tickets: `#7629957161`, `#6262313107`
- Updated `supabase/functions/technician-work/index.ts`:
  - `submit-report`: inserts `TECH_SUBMIT` log entry with real technician team name and UID.
  - `admin-review-report`: queries `TicketId` and inserts `REPORT_APPROVE` / `REPORT_REJECT` with Admin display name and UID.
  - Successfully deployed `technician-work` Edge Function via `supabase functions deploy technician-work --no-verify-jwt`.
- Updated `lib/gui/activity_log_page.dart`:
  - `_formatActorHeader` prioritizes `log.metadata['uid']` and formats Admin as `fewfast (u_5435312295)`, Technician as `ทีมช่าง techteam (t_7892264770)`, and SuperAdmin as `SuperAdmin1` / `SuperAdmin2` (no brackets).
- Updated Activity Log pagination `_pageSize` to 5 in `lib/gui/activity_log_page.dart` and fallback `pageSize` to 5 in `supabase/functions/superadmin-users/index.ts`. Deployed `superadmin-users` Edge Function. All 65 tests verified and passing.

## Audit Findings Fix (2026-10-20)
- **Item 1**: Added authentication and authorization check in `action: "devices"` (`supabase/functions/list-public-tickets/index.ts`). Admins, SuperAdmins, and Technicians have full access; Users have access only to their own tickets (`requester`); unauthenticated/public users are rejected with 401/403. In `lib/gui/ticketMonitor.dart`, added `Authorization` Bearer token header to `_loadDevices()`.
- **Item 2**: Made `supabase/migrations/20261024000005_sync_real_activity_logs.sql` idempotent without unconditional `DELETE`, adding `WHERE NOT EXISTS` checks on all inserts to prevent data loss.
- **Item 3**: Added error checks on all `activity_logs.insert()` operations in `supabase/functions/technician-work/index.ts` and logged any failures. Deployed function.
- **Item 4**: Created and applied migration `supabase/migrations/20261024000006_fix_activity_logs_created_at_timezone.sql` to change `created_at` column default to `now()` and updated `log_activity` RPC. Verified remotely.
- **Item 5**: Optimized ticket pagination in `supabase/functions/list-public-tickets/index.ts` across admin-tickets, my-tickets, and public tickets to use Supabase Query Builder `.range()` instead of memory `.slice()`. Deployed `list-public-tickets` Edge Function.
- All 65 tests verified and passing (`flutter test`).





## Overdue Ticket Schedule Management (2026-10-20)
- **Database Migration (`20261024000007_overdue_ticket_schedule_handler.sql`)**:
  - Implemented `public.check_and_expire_overdue_tickets() RETURNS jsonb` as `SECURITY DEFINER` executable only by `service_role`.
  - Queries `FixList` for `status = 'pending'`, `next_fix_date_end IS NOT NULL`, and `next_fix_date_end < pg_catalog.now()`.
  - **Case 1 (Has future work period)**: Reschedules `next_fix_date_start` and `next_fix_date_end` to the next available work period of the assigned technician team in `Maintenance_Users`. Updates pending devices in dynamic ticket table `"TicketId"` with `next_fix_date`.
  - **Case 2 (No future work period)**:
    1. Reverts `FixList` to `status = 'validating'`, clearing `technician_team`, `next_fix_date_start`, and `next_fix_date_end`.
    2. Reverts dynamic ticket table devices to `status = 'validating'` and `next_fix_date = NULL`.
    3. Unassigns ticket from technician assignment table via `public.sync_maintenance_team_ticket_assignment(ticketId, oldTeam, NULL, false)`.
    4. Automatically records activity log entry via `public.log_activity('system', 'System', 'TICKET_AUTO_REVERT', 'หมดช่วงเวลาปฏิบัติงานช่าง', description, ticketId, metadata, 'ระบบอัตโนมัติ')`.
  - Applied to remote database `vmgzyenvqsfhcuropzjd` and verified.
- **Edge Functions Integration**:
  - Updated `supabase/functions/list-public-tickets/index.ts`: added `expireOverdueTicketsSilently` called silently during admin, technician, user, and public ticket lookups.
  - Updated `supabase/functions/technician-work/index.ts`: added `expireOverdueTicketsSilently` called after identity validation.
  - Deployed both functions to Supabase via `supabase functions deploy list-public-tickets --no-verify-jwt` and `supabase functions deploy technician-work --no-verify-jwt`.
- **UI Enhancements (`lib/gui/activity_log_page.dart`)**:
  - Added Teal color styling for `System` role.
  - Formatted actor header for `System` to display `ระบบอัตโนมัติ` cleanly without UID brackets.
  - Added filter dropdown items for action type `TICKET_AUTO_REVERT` ('คืนงานซ่อม (หมดเวลา)') and role `System` ('System (ระบบ)').
- **Verification**:
  - `flutter analyze`: passed (0 errors, 0 warnings).
  - `flutter test`: all 65 unit & widget tests passed.


## Public Ticket Devices Access (2026-10-20)
- In `supabase/functions/list-public-tickets/index.ts`, removed mandatory Bearer token check and ownership/role authorization check from `action === "devices"`.
- This restores public / unsigned access so students and staff who are not logged in can view ticket devices, device status, and repair history photos on the Public Ticket Monitor page without encountering 401/403 errors.
- Deployed `list-public-tickets` Edge Function via `supabase functions deploy list-public-tickets --no-verify-jwt`.
- All 65 tests verified and passing (`flutter test`).


## Prevent Deleting Active Technicians (2026-10-20)
- **Database Migration (`20261024000008_prevent_delete_active_technician.sql`)**:
  - Enhanced `public.delete_maintenance_technician(p_technician_uid text)`:
    1. Checks `FixList` for active tickets assigned to this team (`technician_team = technician_team_name AND status IN ('pending', 'validating')`).
    2. Checks technician assignment table `public."t_XXXXXXXXXX"` for assigned tickets.
    3. Checks `public.technician_work_reports` for pending reviews (`status = 'under_review'`).
    4. If any active work exists, raises `ACTIVE_JOBS_EXIST` exception with item count to abort deletion.
  - Applied migration to remote database `vmgzyenvqsfhcuropzjd` via `supabase db push --linked`.
- **Edge Function (`supabase/functions/maintenance-teams/index.ts`)**:
  - In `action === "delete-technician"`, catches `ACTIVE_JOBS_EXIST` error message from RPC and strips prefix to return user-friendly HTTP 400 error.
  - Deployed `maintenance-teams` Edge Function via `supabase functions deploy maintenance-teams --no-verify-jwt`.
- **Frontend UI (`lib/gui/technicianManager.dart`)**:
  - In `_deleteTechnician`: checks if the technician currently has assigned tickets and aborts with a clear alert; formats exception messages properly.
  - In `_deleteTechnicianButton`: disables the delete button and displays tooltip and warning message if the selected technician has active assigned tickets.
- **Verification**:
  - `flutter analyze`: passed (0 errors, 0 warnings).
  - `flutter test`: all 65 tests passed.


## Fix Ticket Revert on Edit (2026-10-20)
- **Problem**: When Admin edited a ticket to `pending` and assigned `techteam`, the ticket immediately bounced back to `validating` because `techteam` had expired work periods (`end_time` was in the past) and `check_and_expire_overdue_tickets()` immediately detected an overdue schedule with no future periods.
- **Database Migration (`20261024000009_fix_ticket_revert_on_edit.sql`)**:
  - Updated `techteam` work periods in `Maintenance_Users` to cover from today to +14 days.
  - Updated `public.check_and_expire_overdue_tickets()` to add a 1-hour grace period (`next_fix_date_end < (v_now - interval '1 hour')`) to prevent race conditions immediately after assignment.
  - Applied migration to remote database `vmgzyenvqsfhcuropzjd` via `supabase db push --linked`.
- **Frontend UI (`lib/gui/ticketMonitor.dart`)**:
  - In `_AdminTicketEditDialogState._save()`: checks if the selected technician team has a valid active/future repair period. If expired, prevents saving and shows a SnackBar alerting the Admin to update the team's schedule in technician management first.
  - In `optionsViewBuilder`: added a red badge `'หมดเวลาปฏิบัติงาน'` next to technician team names in the search/select options when their schedule is expired.
- **Verification**:
  - `flutter analyze`: passed (0 errors, 0 warnings).
  - `flutter test`: all 65 tests passed.


## Comprehensive .gitignore Update (2026-10-20)
- Updated root [`.gitignore`](file:///c:/Users/few/Desktop/VScode/Mobile/mobileproject/.gitignore) to industry-standard DevOps & Flutter/Supabase practices:
  - **Flutter & Dart**: ignored `.dart_tool/`, `.flutter-plugins*`, `.pub-cache/`, `.pub/`, `/build/`, `/coverage/`, doc APIs, symbolication & map files.
  - **Android**: ignored `.gradle/`, `local.properties`, `key.properties`, app debug/profile/release builds, `*.keystore`, `*.jks`.
  - **iOS & macOS**: ignored CocoaPods `Pods/`, `.symlinks/`, `Flutter.framework`, `.podspec`, `Generated.xcconfig`, `MapsApiKey.xcconfig`.
  - **Supabase & Node/Deno**: ignored `node_modules/`, `.deno/`, `supabase/.temp/`, `supabase/.branches/`, npm/yarn debug logs.
  - **Sensitive/Secrets**: ignored `.env`, `.env.*` (while keeping `!.env.example`).
  - **IDE & OS**: ignored `.idea/`, VS Code `.vscode/*` (whitelisting `launch.json` and `tasks.json`), `.DS_Store`, `Thumbs.db`, `desktop.ini`, swap/temp files.
  - **Scratch & Emulator dumps**: ignored `bugreport-*.zip`, `*.tmp`, `*.bak`, `*.orig`.
- Verified with `git status`: Untracked junk files (`bugreport-*.zip`, `supabase/.temp/`) are now properly ignored.
- Ran `flutter test`: all 65 tests passed.


## Mobile Crash on Google Login & Google Maps Fix (2026-10-20)
- **Problem 1 (Android App Crash / Disconnect after Google Login)**:
  - On real devices (Pixel 9 / Android 14+), returning from Chrome Custom Tabs (`io.supabase.flutter://login-callback`) triggered activity destruction and lost debugger connection (`Lost connection to device`) due to `android:launchMode="singleTop"` and `android:taskAffinity=""`.
  - **Resolution (`android/app/src/main/AndroidManifest.xml`)**:
    - Changed `launchMode` from `singleTop` to `singleTask` on `.MainActivity` so that deep link intent callback is received on the existing instance via `onNewIntent` without destroying the activity.
    - Removed `android:taskAffinity=""` so the activity stays in the application's root task.
    - Added `android:enableOnBackInvokedCallback="true"` to `<application>` to support Android 13/14+ predictive back gestures cleanly.
- **Problem 2 (Google Maps Blank / Gray Screen & Map Complexity)**:
  - On mobile devices without `MAPS_API_KEY` configured in `android/local.properties`, Google Maps showed blank/gray tiles and required external API credentials.
  - **Resolution (`lib/gui/fixRequest.dart`)**:
    - Completely removed `google_maps_flutter` dependency and usage from the app codebase.
    - Standardized on OpenStreetMap (`flutter_map`) across all platforms (Android, iOS, Web, Windows, Desktop).
    - Removed the map toggle button from `_LocationPickerDialog`'s title to keep the dialog simple and clean (`title: const Text('เลือกตำแหน่ง')`).
    - Handled marker placement, dragging, and coordinate confirmation directly using `latlong2.LatLng` and `FlutterMap`.
- **Verification**:
  - `flutter test`: all 66 unit and widget tests passed (including dedicated Android and Windows OpenStreetMap tests).
  - `flutter analyze`: 0 errors, 0 warnings.


## TicketMonitor Status Cell UI Overflow Fix (2026-10-20)
- **Problem**: In the "รายการแจ้งซ่อมของฉัน" (My Requests) page for tickets with `validating` status, the status column cell contains a status badge, cancel request button (`IconButton`), and expand/collapse arrow icon, which caused a RenderFlex overflow (`right overflowed by 17 pixels`) on compact screens.
- **Resolution (`lib/gui/ticketMonitor.dart`)**:
  - **Table Proportions**:
    - In `LayoutBuilder`, increased minimum `tableWidth` threshold from 900 to 940 px.
    - Updated column distribution formula (`columnWidth = tableWidth / 9.0; statusColumnWidth = columnWidth * 1.8;`), increasing status column width from ~155px to ~188px.
  - **FittedBox Fail-safe**:
    - In `_ExpandableTicketRowState`, wrapped the status cell `Row` with `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.center)`.
    - Guarantees that even with large accessibility font sizes or narrow dimensions, the status badge and action icons scale down gracefully without triggering any yellow-black stripe RenderFlex overflow.
- **Verification**:
  - `flutter analyze lib/gui/ticketMonitor.dart test/`: passed (0 issues).
  - `flutter test`: all 66 tests passed.


## Temporary & Junk Files Cleanup (2026-10-20)
- **Deleted Artifacts**:
  - Removed Android Emulator dump: `bugreport-*.zip` (~10 MB freed).
  - Removed 0-byte image placeholder: `flutter_01.png`.
  - Removed temporary Supabase CLI cache and dependencies: `supabase/.temp/`.
  - Removed legacy unused Cloud Functions test folder: `functions/` (and its nested old `node_modules`).
- **Preserved**:
  - All application code (`lib/`, `test/`), active Edge Functions (`supabase/functions/`), migrations (`supabase/migrations/`), configurations, and environment secrets.
- **Verification**:
  - `flutter test --no-pub`: all 66 tests passed.


## Sync Ticket Schedule on Technician Update (2026-10-20)
- **Requirement**: When Admin updates technician working periods (`start_time` / `end_time`) or active `status` in `TechnicianManager`, all `pending` tickets assigned to that team must automatically and immediately update their upcoming repair window (`next_fix_date_start`, `next_fix_date_end`) and device repair dates to match the new technician schedule.
- **Database Migration (`20261024000010_sync_ticket_schedule_on_technician_update.sql`)**:
  - Created `public.sync_tickets_on_technician_schedule_update()` function:
    - Triggered `AFTER UPDATE OF start_time, end_time, status ON public."Maintenance_Users" FOR EACH ROW`.
    - Detects whether `start_time`, `end_time`, or `status` changed.
    - If valid future periods exist: finds the nearest future repair period (accounting for full-day boundary `+ interval '1 day' > now()`), updates `FixList` and the dynamic ticket device table (`next_fix_date`), and logs activity `TICKET_RESCHEDULE` ("ปรับช่วงเวลาซ่อมตามช่าง").
    - If no future period exists or team is deactivated: reverts tickets to `validating`, removes technician team, resets dates, unlinks assignment in technician assignment table, and logs activity `TICKET_AUTO_REVERT` ("หมดช่วงเวลาปฏิบัติงานช่าง").
  - Linked to project `vmgzyenvqsfhcuropzjd` and applied migration cleanly via `supabase db push --linked`.
- **UI Enhancements (`lib/gui/activity_log_page.dart`)**:
  - Added filter dropdown item `TICKET_RESCHEDULE` ("ปรับช่วงเวลาซ่อมตามช่าง") in `ActivityLogPage`.
- **Verification**:
  - `supabase db push --dry-run --linked`: verified 100% clean.
  - `supabase db push --linked`: migration applied successfully.
  - `flutter analyze lib/gui/activity_log_page.dart test/`: passed (0 issues).
  - `flutter test --no-pub`: all 66 tests passed.


## Friendly Network Error & Retry Refresh on TicketMonitor (2026-10-20)
- **Problem**: When a network hiccup or socket drop occurred during ticket loading (e.g., `FunctionsFetchException(status: 0, details: ClientException: Connection reset by peer)`), the raw exception object was printed directly to the screen. Users were confused and had no retry button, forcing an app restart.
- **Resolution**:
  - **Error Classification Helper (`lib/gui/ticket_load_error_message.dart`)**:
    - Created `TicketLoadErrorInfo` and `formatTicketLoadError(error)`:
      - **Network/Socket drops** (`FunctionsFetchException`, `ClientException`, `SocketException`, `status: 0`, timeout, peer reset): returns Title: `"ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้"`, Message: `"สัญญาณอินเทอร์เน็ตอาจขัดข้องหรือหลุดระหว่างดาวน์โหลดข้อมูล กรุณาตรวจสอบการเชื่อมต่อแล้วลองใหม่อีกครั้ง"`, `isNetworkError: true`.
      - **Server 5xx / Relay errors** (`FunctionsHttpException` 5xx, `FunctionsRelayException`): returns Title: `"ระบบเซิร์ฟเวอร์ขัดข้องชั่วคราว"`, Message: `"ระบบเซิร์ฟเวอร์ไม่สามารถตอบสนองได้ชั่วคราว กรุณาลองใหม่อีกครั้งภายหลัง"`.
      - **Format / Other errors**: returns Title: `"เกิดข้อผิดพลาดในการโหลดรายการ"`, Message: `"เกิดข้อผิดพลาดในการโหลดรายการ กรุณาลองใหม่อีกครั้ง"`.
      - Preserves full `rawDetails` string for diagnostics.
  - **User-Friendly Error Card UI (`lib/gui/ticketMonitor.dart`)**:
    - In `_buildTable()`, displays a clean centered card:
      - Icon: `Icons.wifi_off_rounded` (for network errors) or `Icons.cloud_off_rounded` (for server errors).
      - Prominent `FilledButton.icon` with `Icons.refresh` ("ลองใหม่อีกครั้ง") which immediately calls `_loadTickets()`.
      - Expandable `TextButton` ("ดูรายละเอียดข้อผิดพลาด" / "ซ่อนรายละเอียดทางเทคนิค") revealing the raw technical stack/message in a selectable monospace box.
  - **Widget Testing Support**:
    - Added optional `fetchTickets` callback on `TicketMonitor` for deterministic, offline testing of error states and retry behavior.
- **Testing & Verification**:
  - Added unit tests: `test/gui/ticket_load_error_message_test.dart` (6 test cases).
  - Added widget tests: `test/gui/ticket_monitor_error_ui_test.dart` (2 test cases verifying network error card, expand/collapse details, retry reload, and 500 server error).
  - `flutter analyze lib/gui/ticketMonitor.dart lib/gui/ticket_load_error_message.dart test/`: passed with 0 issues.
  - `flutter test --no-pub`: all 74 unit and widget tests passed 100%.








## Activity Logging System Refinement (2026-10-20)
- **Objective:** Strictly align Activity Logging with role-specific requirements across database functions/triggers, Edge Functions, and SuperAdmin UI (`lib/gui/activity_log_page.dart`).
- **Database Migration:**
  - Added and pushed migration `20261024000011_refine_activity_logging_rules.sql` to linked project `vmgzyenvqsfhcuropzjd`.
  - Removed `public.log_activity('system', ...)` from `check_and_expire_overdue_tickets()` and `sync_tickets_on_technician_schedule_update()`.
  - Purged all legacy and automated system activity logs (`actor_role ILIKE 'system'` or `action_type IN ('TICKET_AUTO_REVERT', 'TICKET_RESCHEDULE')`).
- **Edge Functions:**
  - `update-user-profile`: Records `CHANGE_DISPLAY_NAME` when user or admin modifies display name, logging `actor_username = user.uid`, `actor_role`, `actor_display_name = newName`, `description = 'ผู้ใช้งานเปลี่ยนชื่อที่แสดงเป็น [ชื่อใหม่]'` (or Admin/SuperAdmin equivalent), `target_id = user.uid`, and metadata `{ old_name, new_name }`.
  - `maintenance-teams`:
    - `create-technician`: records `CREATE_TECH_TEAM` with `target_id = techUid` and metadata `{ team_name, username }`.
    - `update-technician`: records `SCHEDULE_TECH_TEAM` when `dateRanges` is updated, logging `target_id = techUid` and metadata `{ team_name, date_ranges }`.
    - `delete-technician`: records `DELETE_TECH_TEAM` with `target_id = techUid` and metadata `{ team_name, username }`.
    - `update-assigned-ticket` & `update-assigned-device`: records `EDIT_TICKET` for Admin edits.
  - `list-public-tickets`:
    - `admin-update-ticket`: records `EDIT_TICKET` for Admin edits (ticket status, team assignment, schedule, location).
  - Deployed `update-user-profile`, `maintenance-teams`, and `list-public-tickets` to Supabase.
- **UI (`lib/gui/activity_log_page.dart`):**
  - Removed `'System'` from the Role filter dropdown (retained `ALL`, `SuperAdmin`, `Admin`, `Technician`, `User`).
  - Updated Action Type filter dropdown to include:
    - `'EDIT_TICKET'` ('แก้ไขคำร้องแจ้งซ่อม')
    - `'CREATE_TECH_TEAM,SCHEDULE_TECH_TEAM,DELETE_TECH_TEAM'` ('จัดการทีมช่าง')
    - `'CHANGE_DISPLAY_NAME'` ('เปลี่ยนชื่อที่แสดง')
    - Retained SuperAdmin & Technician actions: `'REPORT_APPROVE,REPORT_REJECT'`, `'TICKET_ASSIGN'`, `'ROLE_CHANGE,...'`, `'TECH_SUBMIT'`.
    - Removed `'TICKET_AUTO_REVERT'` and `'TICKET_RESCHEDULE'`.
  - Added dedicated role icon and badge styling for `User` role (`Icons.person_outline`, `Colors.green.shade700`).
  - Updated `_formatActorHeader` to support `User` role format: `[DisplayName] (uid)`.
- **Verification:**
  - `flutter analyze`: 0 errors.
  - `flutter test --no-pub`: all 74 unit/widget tests passed.


## Ticket Monitor Requester Info & Search System (2026-10-20)
- **Objective:** Display requester details and enable search by TicketId, Requester UID, or Requester Display Name in `TicketMonitor` for Admin and SuperAdmin roles.
- **Backend (`supabase/functions/list-public-tickets/index.ts`):**
  - Updated `action === "admin-tickets"`:
    - Queries `requester` from `FixList`.
    - Looks up `"Display Name"` from `public."Users"` where `Users.uid = FixList.requester`.
    - Returns `requester_uid` and `requester_display_name` on each ticket object.
  - Search logic update:
    - Replaced numeric-only constraint (`!/^\d*$/.test(ticketId)`) with generic search string (length <= 100).
    - Queries `public."Users"` in parallel for matching `uid` or `"Display Name"` (`ilike %search%`), gathering `matchedRequesterUids`.
    - Filters `FixList` where `TicketId ilike %search%` OR `requester ilike %search%` OR `requester in (matchedRequesterUids)`.
  - Deployed `list-public-tickets` function to Supabase.
- **Frontend:**
  - `lib/gui/layout.dart`:
    - Updated `TicketMonitor` instantiation for SuperAdmin: `TicketMonitor(adminMode: role == 'Admin' || role == 'SuperAdmin')`.
  - `lib/gui/ticketMonitor.dart`:
    - Extended `_Ticket` class with `final String? requesterUid` and `final String? requesterDisplayName`.
    - Updated `_Ticket.fromJson` parser with validation and extraction.
    - Updated `_buildTicketDetailsHeading` to display:
      `ผู้ส่งคำร้อง ${widget.ticket.requesterDisplayName ?? '-'}(${widget.ticket.requesterUid ?? '-'})`
      beside "อุปกรณ์ย่อย" when `widget.adminMode` is true.
    - Search text field updates:
      - `labelText`: `widget.adminMode ? 'ค้นหา TicketId, UID หรือชื่อผู้ส่งคำร้อง' : 'ค้นหา TicketId'`
      - `hintText`: `widget.adminMode ? 'กรอก TicketId, UID หรือชื่อผู้ส่งคำร้อง' : 'กรอก TicketId'`
      - `keyboardType`: `widget.adminMode ? TextInputType.text : TextInputType.number`
- **Testing & Verification:**
  - Added `test/gui/ticket_monitor_requester_test.dart` testing admin vs non-admin mode requester display and search UI.
  - Updated `test/widget_test.dart` search expectation for Admin role.
  - `flutter analyze`: 0 errors.
  - `flutter test --no-pub`: all 76 tests passed.


## Admin Change Other User Display Name Logging (2026-10-20)
- **Objective:** Record activity log in `public.activity_logs` when Admin updates another user's Display Name (`action === "submit-change"` in `superadmin-users`).
- **Backend (`supabase/functions/superadmin-users/index.ts`):**
  - In `action === "submit-change"`:
    - Extracted Admin's UID (`requesterUid`).
    - When `claims.role === "Admin"` successfully updates user's display name:
      - Inserts log with `action_type: 'CHANGE_USER_DISPLAY_NAME'`, `action_title: 'แอดมินเปลี่ยนชื่อที่แสดงของผู้ใช้อื่น'`, `target_id: target.uid`, `description: แอดมินเปลี่ยนชื่อที่แสดงของ ${target.uid} จาก "${target["Display Name"]}" เป็น "${requestedDisplayName}"`, and metadata `{ target_uid, old_display_name, new_display_name }`.
  - Deployed `superadmin-users` function to Supabase.
- **Frontend (`lib/gui/activity_log_page.dart`):**
  - Updated Action Type dropdown filter item:
    `DropdownMenuItem(value: 'CHANGE_DISPLAY_NAME,CHANGE_USER_DISPLAY_NAME', child: Text('เปลี่ยนชื่อที่แสดง (ตนเอง/ผู้อื่น)'))`
  - Added action icon mapping `_getActionIcon(log.actionType)` displaying `Icons.badge_outlined` for `CHANGE_USER_DISPLAY_NAME` and `Icons.drive_file_rename_outline` for `CHANGE_DISPLAY_NAME`.
  - Log card displays action icon, action title, description, and target ID Chip (`#${log.targetId}`).
- **Testing & Verification:**
  - Updated `test/gui/activity_log_page_test.dart` to cover `CHANGE_USER_DISPLAY_NAME` rendering.
  - `flutter analyze`: 0 errors.
  - `flutter test --no-pub`: all 76 tests passed.
