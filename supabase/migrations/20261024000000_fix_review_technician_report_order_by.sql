-- Fix column "id" does not exist in Maintenance_Users table during admin report review
-- Maintenance_Users has columns (created_at, teamName, password, comment, username, uid, start_time, end_time, status)
-- Order by maintenance_user.created_at instead of maintenance_user.id

create or replace function public.admin_review_technician_work_report(
  p_report_id uuid,
  p_decision text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  report_ticket_id text;
  report_technician_uid text;
  report_comment text;
  report_results jsonb;
  report_submitted_at timestamptz;
  work_period_start timestamptz;
  work_period_end timestamptz;
  technician_name text;
  ticket_table regclass;
  history_index integer;
  review_timestamp timestamptz := pg_catalog.now();
  has_unfinished_devices boolean;
  has_finished_devices boolean;
  assignment_table record;
  updated_rows integer;
begin
  if p_report_id is null or p_decision is null
    or p_decision not in ('approve', 'reject') then
    raise exception 'Invalid technician work report review.';
  end if;

  select report."TicketId" into report_ticket_id
  from public.technician_work_reports as report
  where report.id = p_report_id and report.status = 'under_review';
  if not found then
    raise exception 'Technician work report is not awaiting review.';
  end if;

  ticket_table := pg_catalog.to_regclass(
    pg_catalog.format('public.%I', report_ticket_id)
  );
  if ticket_table is null then
    raise exception 'Technician work report device table was not found.';
  end if;
  perform 1 from public."FixList"
  where "TicketId" = report_ticket_id for update;
  if not found then
    raise exception 'Technician work report ticket was not found.';
  end if;

  select report."technicianUid", report.comment, report.device_results,
         report.submitted_at, report.work_period_start, report.work_period_end
    into report_technician_uid, report_comment, report_results,
         report_submitted_at, work_period_start, work_period_end
  from public.technician_work_reports as report
  where report.id = p_report_id and report.status = 'under_review'
  for update;
  if not found then
    raise exception 'Technician work report is not awaiting review.';
  end if;

  if p_decision = 'reject' then
    update public.technician_work_reports
    set status = 'rejected', reviewed_at = review_timestamp
    where id = p_report_id;
    return;
  end if;

  select coalesce(max(report.history_index) + 1, 0)
    into history_index
  from public.technician_work_reports as report
  where report."TicketId" = report_ticket_id
    and report.status = 'approved'
    and report.history_index is not null;

  select maintenance_user."teamName" into technician_name
  from public."Maintenance_Users" as maintenance_user
  where maintenance_user.uid = report_technician_uid
  order by maintenance_user.created_at
  limit 1;
  technician_name := coalesce(technician_name, report_technician_uid);

  execute pg_catalog.format(
    'select count(*)::integer
       from (
         select deviceid,
                status,
                pg_catalog.row_number() over (order by deviceid)::integer as row_index
         from %s
       ) as pending_device
       where pending_device.status = %L
         and exists (
           select 1 from pg_catalog.jsonb_array_elements($1) as result(value)
           where result.value ->> ''deviceid'' = pending_device.deviceid::text
             and result.value ->> ''row_index'' = pending_device.row_index::text
         )',
    ticket_table,
    'pending'
  ) into updated_rows using report_results;
  if updated_rows <> pg_catalog.jsonb_array_length(report_results) then
    raise exception 'A reported device is no longer pending.';
  end if;

  -- Append one result per approved work period to every device row so the
  -- history arrays stay aligned across partial repairs.
  execute pg_catalog.format(
    'update %s as device
        set fix_history_progress =
              coalesce(device.fix_history_progress, array[]::boolean[])
              || coalesce((
                   select (result.value ->> ''success'')::boolean
                   from pg_catalog.jsonb_array_elements($1) as result(value)
                   where result.value ->> ''deviceid'' = device.deviceid::text
                 ), false),
            technician_comment =
              coalesce(device.technician_comment, array[]::text[]) || $2::text,
            status = case
              when device.status = %L and exists (
                select 1 from pg_catalog.jsonb_array_elements($1) as result(value)
                where result.value ->> ''deviceid'' = device.deviceid::text
                  and result.value ->> ''success'' = ''true''
              ) then %L
              else device.status
            end',
    ticket_table,
    'pending',
    'finish'
  ) using report_results, report_comment;

  update public.technician_work_reports
  set status = 'approved',
      reviewed_at = review_timestamp,
      history_index = history_index
  where id = p_report_id;

  update public."FixList"
  set technician_history =
        coalesce(technician_history, array[]::text[]) || technician_name,
      fix_history_time_start =
        coalesce(fix_history_time_start, array[]::timestamptz[]) || work_period_start,
      fix_history_time_end =
        coalesce(fix_history_time_end, array[]::timestamptz[]) || work_period_end,
      technician_comment =
        coalesce(technician_comment, array[]::text[]) || array[report_comment],
      next_fix_date_start = null,
      next_fix_date_end = null
  where "TicketId" = report_ticket_id;

  execute pg_catalog.format(
    'select exists (select 1 from %s where status in (%L, %L))',
    ticket_table, 'pending', 'validating'
  ) into has_unfinished_devices;
  execute pg_catalog.format(
    'select exists (select 1 from %s where status = %L)',
    ticket_table, 'finish'
  ) into has_finished_devices;

  if not has_unfinished_devices and has_finished_devices then
    update public."FixList"
    set status = 'finish'
    where "TicketId" = report_ticket_id;
  end if;

  for assignment_table in
    select relation.relname
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as schema
      on schema.oid = relation.relnamespace
    where schema.nspname = 'public'
      and relation.relkind = 'r'
      and relation.relname ~ '^t_[0-9]{10}$'
  loop
    execute pg_catalog.format(
      'delete from public.%I where "ticketId" = $1',
      assignment_table.relname
    ) using report_ticket_id;
  end loop;
end;
$$;

revoke all on function public.admin_review_technician_work_report(uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_review_technician_work_report(uuid, text)
  to service_role;

select pg_catalog.pg_notify('pgrst', 'reload schema');

