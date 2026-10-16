do $$
declare
  demo_ticket_id constant text := '9000000001';
begin
  if exists (
    select 1
    from public."FixList"
    where "TicketId" = demo_ticket_id
  ) then
    return;
  end if;

  insert into public."FixList" (
    "TicketId",
    building,
    area,
    longtitude,
    latitude,
    floor,
    room,
    status,
    technician_team
  )
  values (
    demo_ticket_id,
    '25',
    null,
    100.9190,
    13.1205,
    '2',
    '201',
    'validating',
    null
  );

  execute pg_catalog.format(
    'create table public.%I (
      deviceid integer primary key,
      device text not null,
      discription text,
      status text not null default %L,
      fix_history_progress boolean[] default null,
      technician_comment text[] default null,
      next_fix_date timestamptz[] default null
    )',
    demo_ticket_id,
    'validating'
  );
  execute pg_catalog.format(
    'alter table public.%I enable row level security',
    demo_ticket_id
  );
  execute pg_catalog.format(
    'grant select, insert, update, delete on table public.%I to service_role',
    demo_ticket_id
  );

  execute pg_catalog.format(
    'insert into public.%I
      (deviceid, device, discription, status)
     values
      (1, $1, $2, %L),
      (2, $3, $4, %L),
      (3, $5, $6, %L)',
    demo_ticket_id,
    'validating',
    'validating',
    'validating'
  )
  using
    'เครื่องปรับอากาศ',
    'มีเสียงดังผิดปกติ',
    'โปรเจคเตอร์',
    'เปิดเครื่องไม่ติด',
    'หลอดไฟ LED',
    null;

  insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
  )
  values (
    demo_ticket_id,
    demo_ticket_id,
    false,
    6291456,
    array['image/gif', 'image/jpeg', 'image/png', 'image/webp']
  )
  on conflict (id) do update
    set name = excluded.name,
        public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;
end;
$$;
