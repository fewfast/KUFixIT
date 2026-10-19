alter table public."FixList"
  add column if not exists next_fix_date_start timestamptz,
  add column if not exists next_fix_date_end timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public."FixList"'::pg_catalog.regclass
      and conname = 'fixlist_next_fix_date_range_check'
  ) then
    alter table public."FixList"
      add constraint fixlist_next_fix_date_range_check
      check (
        (next_fix_date_start is null and next_fix_date_end is null)
        or (
          next_fix_date_start is not null
          and next_fix_date_end is not null
          and next_fix_date_start <= next_fix_date_end
        )
      ) not valid;
  end if;
end;
$$;

alter table public."FixList"
  validate constraint fixlist_next_fix_date_range_check;

alter table public.technician_work_reports
  add column if not exists device_results jsonb not null default '[]'::jsonb;

-- The original single-photo checks and path shape predate per-device results.
alter table public.technician_work_reports
  drop constraint if exists technician_work_reports_check,
  drop constraint if exists technician_work_reports_check1,
  drop constraint if exists technician_work_reports_check2,
  drop constraint if exists technician_work_reports_check3,
  drop constraint if exists technician_work_reports_check4,
  drop constraint if exists technician_work_reports_comment_check,
  drop constraint if exists technician_work_reports_photo_path_check,
  drop constraint if exists technician_work_reports_photo_name_check;

alter table public.technician_work_reports
  add constraint technician_work_reports_outcome_photo_check
    check (outcome <> 'success' or photo_path is not null),
  add constraint technician_work_reports_comment_check
    check (outcome <> 'failure' or nullif(pg_catalog.btrim(comment), '') is not null),
  add constraint technician_work_reports_comment_length_check
    check (comment is null or pg_catalog.length(comment) <= 5000),
  add constraint technician_work_reports_photo_path_check
    check (
      photo_path is null
      or photo_path ~ '^[0-9]{10}/t_[0-9]{10}/[0-9a-f-]+(/[1-9][0-9]*)?\.(jpg|png|webp)$'
    ),
  add constraint technician_work_reports_photo_name_check
    check (photo_name is null or pg_catalog.length(photo_name) <= 128);

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.technician_work_reports'::pg_catalog.regclass
      and conname = 'technician_work_reports_device_results_array_check'
  ) then
    alter table public.technician_work_reports
      add constraint technician_work_reports_device_results_array_check
      check (pg_catalog.jsonb_typeof(device_results) = 'array') not valid;
  end if;
end;
$$;

alter table public.technician_work_reports
  validate constraint technician_work_reports_device_results_array_check;

create or replace function public.create_technician_work_report(
  p_report_id uuid,
  p_ticket_id text,
  p_technician_uid text,
  p_comment text,
  p_work_period_start timestamptz,
  p_work_period_end timestamptz,
  p_device_results jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket_table regclass;
  ticket_status text;
  pending_count integer;
  device_count integer;
  mismatch_count integer;
  row_count integer := 0;
  successful_count integer := 0;
  total_bytes bigint;
  max_bytes bigint;
  device_result jsonb;
  device_id integer;
  row_index integer;
  success boolean;
  photo_path text;
  photo_size integer;
  assignment_exists boolean;
  effective_comment text := nullif(pg_catalog.btrim(p_comment), '');
begin
  if p_report_id is null
    or p_ticket_id is null or p_ticket_id !~ '^[0-9]{10}$'
    or p_technician_uid is null or p_technician_uid !~ '^t_[0-9]{10}$'
    or p_work_period_start is null or p_work_period_end is null
    or p_work_period_start > p_work_period_end
    or p_device_results is null
    or pg_catalog.jsonb_typeof(p_device_results) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_device_results) = 0 then
    raise exception 'Invalid technician work report.';
  end if;

  perform 1
  from public."FixList"
  where "TicketId" = p_ticket_id
  for update;
  if not found then
    raise exception 'Technician work report ticket was not found.';
  end if;

  select status into ticket_status
  from public."FixList"
  where "TicketId" = p_ticket_id;
  if ticket_status in ('finish', 'cancel', 'rejected') then
    raise exception 'Ticket cannot accept a technician work report.';
  end if;

  ticket_table := pg_catalog.to_regclass(
    pg_catalog.format('public.%I', p_ticket_id)
  );
  if ticket_table is null then
    raise exception 'Technician work report device table was not found.';
  end if;
  if pg_catalog.to_regclass(
    pg_catalog.format('public.%I', p_technician_uid)
  ) is null then
    raise exception 'Technician assignment table was not found.';
  end if;
  execute pg_catalog.format(
    'select exists (select 1 from public.%I where "ticketId" = $1)',
    p_technician_uid
  ) into assignment_exists using p_ticket_id;
  if not assignment_exists then
    raise exception 'Ticket is not assigned to this technician.';
  end if;

  execute pg_catalog.format(
    'select count(*)::integer from %s',
    ticket_table
  ) into device_count;
  execute pg_catalog.format(
    'select count(*)::integer from %s where status = %L',
    ticket_table,
    'pending'
  ) into pending_count;
  if pending_count <> pg_catalog.jsonb_array_length(p_device_results) then
    raise exception 'Report must include each pending device exactly once.';
  end if;

  execute pg_catalog.format(
    'select count(*)::integer
       from (
         select deviceid,
                status,
                pg_catalog.row_number() over (order by deviceid)::integer as row_index
         from %s
       ) as pending_device
       where pending_device.status = %L
         and not exists (
        select 1
        from pg_catalog.jsonb_array_elements($1) as result(value)
        where result.value ->> ''deviceid'' = pending_device.deviceid::text
          and result.value ->> ''row_index'' = pending_device.row_index::text
      )',
    ticket_table,
    'pending'
  ) into mismatch_count using p_device_results;
  if mismatch_count <> 0 then
    raise exception 'Report device rows do not match the current ticket.';
  end if;

  for device_result in
    select value from pg_catalog.jsonb_array_elements(p_device_results)
  loop
    if pg_catalog.jsonb_typeof(device_result) is distinct from 'object'
      or pg_catalog.jsonb_typeof(device_result -> 'deviceid') is distinct from 'number'
      or pg_catalog.jsonb_typeof(device_result -> 'row_index') is distinct from 'number'
      or pg_catalog.jsonb_typeof(device_result -> 'success') is distinct from 'boolean' then
      raise exception 'Invalid technician work report device result.';
    end if;
    device_id := (device_result ->> 'deviceid')::integer;
    row_index := (device_result ->> 'row_index')::integer;
    success := (device_result ->> 'success')::boolean;
    photo_path := nullif(device_result ->> 'photo_path', '');
    photo_size := nullif(device_result ->> 'photo_size', '')::integer;
    row_count := row_count + 1;
    if success then successful_count := successful_count + 1; end if;

    if success and (
      photo_path is null
      or photo_size is null or photo_size < 1 or photo_size > 2097152
      or photo_path !~ (
        '^' || p_ticket_id || '/' || p_technician_uid || '/'
          || p_report_id::text || '/' || row_index::text
          || '\.(jpg|png|webp)$'
      )
    ) then
      raise exception 'Each successful device requires one valid result photo.';
    elsif not success and (photo_path is not null or photo_size is not null) then
      raise exception 'Unsuccessful devices cannot include a result photo.';
    end if;
  end loop;

  if successful_count = 0 then
    effective_comment := 'ซ่อมไม่สำเร็จ';
  elsif successful_count < row_count and effective_comment is null then
    raise exception 'A comment is required when a device was not repaired.';
  end if;

  select coalesce(sum((object.metadata ->> 'size')::bigint), 0)
    into total_bytes
  from storage.objects as object
  where object.bucket_id = 'technician-work-results'
    and object.name like p_ticket_id || '/%';
  max_bytes := device_count::bigint * 2097152;
  if total_bytes > max_bytes then
    raise exception 'Technician work result photos exceed the ticket quota.';
  end if;

  insert into public.technician_work_reports (
    id, "TicketId", "technicianUid", outcome, status, comment,
    photo_path, photo_name, work_period_start, work_period_end, device_results
  ) values (
    p_report_id,
    p_ticket_id,
    p_technician_uid,
    case when successful_count > 0 then 'success' else 'failure' end,
    'under_review',
    effective_comment,
    (select result.value ->> 'photo_path'
     from pg_catalog.jsonb_array_elements(p_device_results) as result(value)
     where result.value ->> 'success' = 'true'
     order by (result.value ->> 'row_index')::integer
     limit 1),
    (select result.value ->> 'photo_name'
     from pg_catalog.jsonb_array_elements(p_device_results) as result(value)
     where result.value ->> 'success' = 'true'
     order by (result.value ->> 'row_index')::integer
     limit 1),
    p_work_period_start,
    p_work_period_end,
    p_device_results
  );
end;
$$;

revoke all on function public.create_technician_work_report(
  uuid, text, text, text, timestamptz, timestamptz, jsonb
) from public, anon, authenticated;
grant execute on function public.create_technician_work_report(
  uuid, text, text, text, timestamptz, timestamptz, jsonb
) to service_role;

-- Old technician-work deployments insert the legacy single-photo report
-- shape directly. Block that write until the RPC-based function is deployed.
revoke insert on table public.technician_work_reports from service_role;

create or replace function public.admin_update_fixlist_and_assign_team(
  p_ticket_id text,
  p_building text,
  p_latitude double precision,
  p_longtitude double precision,
  p_area text,
  p_floor text,
  p_room text,
  p_status text,
  p_technician_team text,
  p_next_fix_date_start timestamptz,
  p_next_fix_date_end timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_team_name text;
  should_assign boolean := p_status = 'pending';
  has_access_period boolean;
begin
  if p_ticket_id is null or p_ticket_id !~ '^[0-9]{10}$'
    or (should_assign and (
      p_technician_team is null
      or pg_catalog.btrim(p_technician_team) = ''
      or p_next_fix_date_start is null
      or p_next_fix_date_end is null
      or p_next_fix_date_start > p_next_fix_date_end
    ))
    or (not should_assign and (
      p_technician_team is not null
      or p_next_fix_date_start is not null
      or p_next_fix_date_end is not null
    )) then
    raise exception 'Invalid repair request assignment.';
  end if;

  if should_assign then
    select exists (
      select 1
      from public."Maintenance_Users" as maintenance_user
      cross join lateral unnest(
        maintenance_user.start_time,
        maintenance_user.end_time
      ) as access_period(start_time, end_time)
      where maintenance_user.status
        and pg_catalog.lower(pg_catalog.btrim(maintenance_user."teamName")) =
            pg_catalog.lower(pg_catalog.btrim(p_technician_team))
        and p_next_fix_date_start >= access_period.start_time
        and p_next_fix_date_end <= access_period.end_time
    ) into has_access_period;
    if not has_access_period then
      raise exception 'The selected team does not have that access period.';
    end if;
  end if;

  select ticket.technician_team into old_team_name
  from public."FixList" as ticket
  where ticket."TicketId" = p_ticket_id
  for update;
  if not found then
    raise exception 'Repair request was not found.';
  end if;

  update public."FixList"
  set building = p_building,
      latitude = p_latitude,
      longtitude = p_longtitude,
      area = p_area,
      floor = p_floor,
      room = p_room,
      status = p_status,
      technician_team = p_technician_team,
      next_fix_date_start = p_next_fix_date_start,
      next_fix_date_end = p_next_fix_date_end
  where "TicketId" = p_ticket_id;

  perform public.sync_maintenance_team_ticket_assignment(
    p_ticket_id,
    old_team_name,
    p_technician_team,
    should_assign
  );
end;
$$;

revoke all on function public.admin_update_fixlist_and_assign_team(
  text, text, double precision, double precision, text, text, text, text, text,
  timestamptz, timestamptz
) from public, anon, authenticated;
grant execute on function public.admin_update_fixlist_and_assign_team(
  text, text, double precision, double precision, text, text, text, text, text,
  timestamptz, timestamptz
) to service_role;

-- The old Edge Function contract omitted the repair range. Prevent stale
-- server code from bypassing the required schedule fields after rollout.
revoke all on function public.admin_update_fixlist_and_assign_team(
  text, text, double precision, double precision, text, text, text, text, text
) from public, anon, authenticated, service_role;

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
  order by maintenance_user.id
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
