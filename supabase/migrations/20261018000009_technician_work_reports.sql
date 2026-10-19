create table public.technician_work_reports (
  id uuid primary key default gen_random_uuid(),
  "TicketId" text not null
    references public."FixList" ("TicketId") on delete cascade,
  "technicianUid" text not null
    check ("technicianUid" ~ '^t_[0-9]{10}$'),
  outcome text not null check (outcome in ('success', 'failure')),
  status text not null default 'under_review'
    check (status in ('under_review', 'approved', 'rejected')),
  comment text,
  photo_path text,
  photo_name text,
  submitted_at timestamptz not null default pg_catalog.now(),
  reviewed_at timestamptz,
  check (outcome <> 'success' or photo_path is not null),
  check (outcome <> 'failure' or nullif(pg_catalog.btrim(comment), '') is not null),
  check (comment is null or pg_catalog.length(comment) <= 5000),
  check (photo_path is null or photo_path ~ '^[0-9]{10}/t_[0-9]{10}/[0-9a-f-]+\.(jpg|png|webp)$'),
  check (photo_name is null or pg_catalog.length(photo_name) <= 128)
);

create index technician_work_reports_ticket_latest_idx
  on public.technician_work_reports ("TicketId", submitted_at desc);

create index technician_work_reports_review_queue_idx
  on public.technician_work_reports (submitted_at asc)
  where status = 'under_review';

create unique index technician_work_reports_one_pending_per_ticket_idx
  on public.technician_work_reports ("TicketId")
  where status = 'under_review';

alter table public.technician_work_reports enable row level security;
revoke all on table public.technician_work_reports from public, anon, authenticated;
grant select, insert, update, delete on table public.technician_work_reports
  to service_role;

create or replace function public.validate_technician_work_report_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  is_assigned boolean;
begin
  if new."TicketId" is null or new."TicketId" !~ '^[0-9]{10}$'
    or new."technicianUid" is null
    or new."technicianUid" !~ '^t_[0-9]{10}$' then
    raise exception 'Invalid technician work report assignment.';
  end if;

  perform 1
  from public."FixList"
  where "TicketId" = new."TicketId"
  for update;
  if not found then
    raise exception 'Technician work report ticket was not found.';
  end if;

  if exists (
    select 1
    from public.technician_work_reports
    where "TicketId" = new."TicketId"
      and outcome = 'success'
      and status = 'approved'
  ) then
    raise exception 'Ticket already has an approved success report.';
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

drop trigger if exists validate_technician_work_report_submission
  on public.technician_work_reports;
create trigger validate_technician_work_report_submission
  before insert on public.technician_work_reports
  for each row
  execute function public.validate_technician_work_report_submission();

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'technician-work-results',
  'technician-work-results',
  false,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists technician_work_results_service_role_only
  on storage.objects;
create policy technician_work_results_service_role_only
  on storage.objects
  as restrictive
  for all
  to public
  using (
    bucket_id <> 'technician-work-results'
    or auth.role() = 'service_role'
  )
  with check (
    bucket_id <> 'technician-work-results'
    or auth.role() = 'service_role'
  );

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
  assignment_table record;
begin
  if p_report_id is null or p_decision is null
    or p_decision not in ('approve', 'reject') then
    raise exception 'Invalid technician work report review.';
  end if;

  select report."TicketId"
    into report_ticket_id
  from public.technician_work_reports as report
  where report.id = p_report_id;

  if not found then
    raise exception 'Technician work report is not awaiting review.';
  end if;

  perform 1
  from public."FixList"
  where "TicketId" = report_ticket_id
  for update;
  if not found then
    raise exception 'Technician work report ticket was not found.';
  end if;

  select report.outcome
    into report_outcome
  from public.technician_work_reports as report
  where report.id = p_report_id
    and report.status = 'under_review'
  for update;
  if not found then
    raise exception 'Technician work report is not awaiting review.';
  end if;

  update public.technician_work_reports
  set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
      reviewed_at = pg_catalog.now()
  where id = p_report_id;

  if p_decision = 'approve' and report_outcome = 'success' then
    update public."FixList"
    set status = 'finish'
    where "TicketId" = report_ticket_id;

    if not found then
      raise exception 'Technician work report ticket was not found.';
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
