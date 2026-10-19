alter table public."FixList"
  add column if not exists technician_comment text[] default array[]::text[];

alter table public.technician_work_reports
  add column if not exists work_period_start timestamptz,
  add column if not exists work_period_end timestamptz,
  add column if not exists history_index integer;

do $$
declare
  ticket_id text;
  ticket_table regclass;
  column_type oid;
  function_definition text;
  array_definition constant text :=
    'next_fix_date timestamptz[] default null';
  scalar_definition constant text :=
    'next_fix_date timestamptz default null';
begin
  for ticket_id in
    select "TicketId" from public."FixList"
  loop
    ticket_table := pg_catalog.to_regclass(
      pg_catalog.format('public.%I', ticket_id)
    );
    if ticket_table is null then
      continue;
    end if;

    select attribute.atttypid
      into column_type
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = ticket_table
      and attribute.attname = 'next_fix_date'
      and not attribute.attisdropped;

    if column_type = 'timestamptz[]'::pg_catalog.regtype then
      execute pg_catalog.format(
        'alter table %s
         alter column next_fix_date type timestamptz
         using next_fix_date[pg_catalog.array_upper(next_fix_date, 1)]',
        ticket_table
      );
    elsif column_type is not null
      and column_type <> 'timestamptz'::pg_catalog.regtype then
      raise exception 'Unexpected next_fix_date type in ticket table %: %',
        ticket_id, column_type::pg_catalog.regtype;
    end if;
  end loop;

  function_definition := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'public.create_fix_request(text,text,text,double precision,double precision,jsonb)'
        ::pg_catalog.regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  if pg_catalog.strpos(function_definition, array_definition) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      array_definition,
      scalar_definition
    );
  elsif pg_catalog.strpos(function_definition, scalar_definition) = 0 then
    raise exception 'Could not update create_fix_request next_fix_date type.';
  end if;
  execute function_definition;
end;
$$;

create unique index if not exists technician_work_reports_history_index_idx
  on public.technician_work_reports ("TicketId", history_index)
  where history_index is not null;

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
    report.comment,
    report.submitted_at,
    report.work_period_start,
    report.work_period_end
    into
      report_outcome,
      report_technician_uid,
      report_comment,
      report_submitted_at,
      work_period_start,
      work_period_end
  from public.technician_work_reports as report
  where report.id = p_report_id
    and report.status = 'under_review'
  for update;
  if not found then
    raise exception 'Technician work report is not awaiting review.';
  end if;

  select pg_catalog.cardinality(technician_history)
    into history_index
  from public."FixList"
  where "TicketId" = report_ticket_id;
  history_index := coalesce(history_index, 0);
  work_period_start := coalesce(work_period_start, report_submitted_at);
  work_period_end := coalesce(work_period_end, review_timestamp);
  if work_period_end < work_period_start then
    work_period_start := report_submitted_at;
    work_period_end := review_timestamp;
  end if;

  update public.technician_work_reports
  set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
      reviewed_at = review_timestamp,
      history_index = case when p_decision = 'approve' then history_index else null end
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
           coalesce(technician_comment, array[]::text[]) || array[$2::text],
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
        coalesce(fix_history_time_start, array[]::timestamptz[]) || work_period_start,
      fix_history_time_end =
        coalesce(fix_history_time_end, array[]::timestamptz[]) || work_period_end,
      technician_comment =
        coalesce(technician_comment, array[]::text[]) || array[report_comment]
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
  execute pg_catalog.format(
    'select exists (
       select 1
       from %s
       where status = %L
     )',
    ticket_table,
    'finish'
  )
  into has_finished_devices;

  if not has_unfinished_devices and has_finished_devices then
    update public."FixList"
    set status = 'finish'
    where "TicketId" = report_ticket_id;

    execute pg_catalog.format(
      'update %s set next_fix_date = null',
      ticket_table
    );

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