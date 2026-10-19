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
  report_outcome text;
  report_technician_uid text;
  report_comment text;
  technician_name text;
  ticket_table regclass;
  review_timestamp timestamptz := pg_catalog.now();
  has_unfinished_devices boolean;
  assignment_table record;
begin
  if p_report_id is null or p_decision is null
    or p_decision not in ('approve', 'reject') then
    raise exception 'Invalid technician work report review.';
  end if;

  select report."TicketId"
    into report_ticket_id
  from public.technician_work_reports as report
  where report.id = p_report_id
    and report.status = 'under_review';
  if not found then
    raise exception 'Technician work report is not awaiting review.';
  end if;

  select pg_catalog.to_regclass(
    pg_catalog.format('public.%I', report_ticket_id)
  )
    into ticket_table;
  if ticket_table is null then
    raise exception 'Technician work report ticket table was not found.';
  end if;

  perform 1
  from public."FixList"
  where "TicketId" = report_ticket_id
  for update;
  if not found then
    raise exception 'Technician work report ticket was not found.';
  end if;

  select
    report.outcome,
    report."technicianUid",
    report.comment
    into report_outcome, report_technician_uid, report_comment
  from public.technician_work_reports as report
  where report.id = p_report_id
    and report.status = 'under_review'
  for update;
  if not found then
    raise exception 'Technician work report is not awaiting review.';
  end if;

  update public.technician_work_reports
  set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
      reviewed_at = review_timestamp
  where id = p_report_id;

  if p_decision = 'reject' then
    return;
  end if;

  select maintenance_user."teamName"
    into technician_name
  from public."Maintenance_Users" as maintenance_user
  where maintenance_user.uid = report_technician_uid
  order by maintenance_user.id
  limit 1;
  technician_name := coalesce(technician_name, report_technician_uid);

  execute pg_catalog.format(
    'update %s
     set fix_history_progress =
           coalesce(fix_history_progress, array[]::boolean[])
             || ($1 and status = %L),
         technician_comment =
           coalesce(technician_comment, array[]::text[]) || $2::text,
         status = case
           when $1 and status = %L then %L
           else status
         end',
    ticket_table,
    'pending',
    'pending',
    'finish'
  )
  using report_outcome = 'success', report_comment;

  update public."FixList"
  set technician_history =
        coalesce(technician_history, array[]::text[]) || technician_name,
      fix_history_time_start =
        coalesce(fix_history_time_start, array[]::timestamptz[]) || review_timestamp,
      fix_history_time_end =
        coalesce(fix_history_time_end, array[]::timestamptz[]) || review_timestamp
  where "TicketId" = report_ticket_id;

  execute pg_catalog.format(
    'select exists (
       select 1
       from %s
       where status in (%L, %L)
     )',
    ticket_table,
    'validating',
    'pending'
  )
  into has_unfinished_devices;

  if not has_unfinished_devices then
    update public."FixList"
    set status = 'finish'
    where "TicketId" = report_ticket_id;

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
  end if;
end;
$$;

revoke all on function public.admin_review_technician_work_report(uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_review_technician_work_report(uuid, text)
  to service_role;

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;

create or replace function public.validate_technician_work_report_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  is_assigned boolean;
  ticket_status text;
begin
  if new."TicketId" is null or new."TicketId" !~ '^[0-9]{10}$'
    or new."technicianUid" is null
    or new."technicianUid" !~ '^t_[0-9]{10}$' then
    raise exception 'Invalid technician work report assignment.';
  end if;

  select status
    into ticket_status
  from public."FixList"
  where "TicketId" = new."TicketId"
  for update;
  if not found then
    raise exception 'Technician work report ticket was not found.';
  end if;
  if ticket_status = 'finish' then
    raise exception 'Ticket is already finished.';
  end if;

  if pg_catalog.to_regclass(
    pg_catalog.format('public.%I', new."technicianUid")
  ) is null then
    raise exception 'Technician assignment table was not found.';
  end if;
  execute pg_catalog.format(
    'select exists (select 1 from public.%I where "ticketId" = $1)',
    new."technicianUid"
  )
  into is_assigned
  using new."TicketId";
  if not is_assigned then
    raise exception 'Ticket is not assigned to this technician.';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_technician_work_report_submission()
  from public, anon, authenticated;
