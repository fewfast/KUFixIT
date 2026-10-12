create table public."FixList" (
  "TicketId" text primary key
    check ("TicketId" ~ '^[0-9]{10}$'),
  requester text
    check (requester is null or requester ~ '^[0-9]{10}$'),
  building text not null,
  area text,
  longtitude double precision not null
    check (longtitude between -180 and 180),
  latitude double precision not null
    check (latitude between -90 and 90),
  floor text,
  room text,
  status text not null default 'validating',
  technician_team text,
  constraint fixlist_building_format
    check (building = 'other' or building ~ '^[0-9]{1,2}$'),
  constraint fixlist_area_matches_building
    check ((building = 'other' and area is not null) or
      (building <> 'other' and area is null))
);

alter table public."FixList" enable row level security;
revoke all on public."FixList" from public, anon, authenticated;
grant select, insert, update, delete on public."FixList" to service_role;

create or replace function public.create_fix_request(
  p_requester text,
  p_building text,
  p_area text,
  p_longtitude double precision,
  p_latitude double precision,
  p_devices jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate_id text;
  device_record jsonb;
  device_number integer := 0;
  first_device jsonb;
begin
  if p_requester is null or p_requester !~ '^[0-9]{10}$'
     or p_building is null
     or (p_building <> 'other' and p_building !~ '^[0-9]{1,2}$')
     or (p_building = 'other' and nullif(pg_catalog.btrim(p_area), '') is null)
     or (p_building <> 'other' and p_area is not null)
     or p_longtitude is null
     or p_longtitude < -180
     or p_longtitude > 180
     or p_latitude is null
     or p_latitude < -90
     or p_latitude > 90 then
    raise exception 'Invalid repair request data';
  end if;

  if p_devices is null
     or pg_catalog.jsonb_typeof(p_devices) is distinct from 'array' then
    raise exception 'Repair request must contain an equipment array';
  end if;
  if pg_catalog.jsonb_array_length(p_devices) = 0 then
    raise exception 'Repair request must contain at least one device';
  end if;

  for device_record in
    select value from pg_catalog.jsonb_array_elements(p_devices) as items(value)
  loop
    if pg_catalog.jsonb_typeof(device_record) <> 'object'
       or nullif(pg_catalog.btrim(device_record ->> 'device'), '') is null then
      raise exception 'Each repair request must include an equipment name';
    end if;
  end loop;

  first_device := p_devices -> 0;
  perform pg_catalog.pg_advisory_xact_lock(918273645, 564738291);
  loop
    candidate_id :=
      (1000000000 + pg_catalog.floor(pg_catalog.random() * 9000000000)::bigint)::text;
    exit when not exists (
      select 1 from public."FixList" where "TicketId" = candidate_id
    ) and pg_catalog.to_regclass(
      pg_catalog.format('public.%I', candidate_id)
    ) is null;
  end loop;

  insert into public."FixList" (
    "TicketId",
    requester,
    building,
    area,
    longtitude,
    latitude,
    floor,
    room
  )
  values (
    candidate_id,
    p_requester,
    p_building,
    p_area,
    p_longtitude,
    p_latitude,
    nullif(pg_catalog.btrim(first_device ->> 'floor'), ''),
    nullif(pg_catalog.btrim(first_device ->> 'room'), '')
  );

  execute pg_catalog.format(
    'create table public.%I (
      deviceid integer primary key,
      device text not null,
      discription text,
      status text not null default %L,
      fix_history_time timestamptz[] default null,
      fix_history_progress text[] default null,
      technician_history text[] default null,
      technician_comment text[] default null,
      next_fix_date timestamptz[] default null
    )',
    candidate_id,
    'validating'
  );
  execute pg_catalog.format(
    'alter table public.%I enable row level security',
    candidate_id
  );
  execute pg_catalog.format(
    'grant select, insert, update, delete on table public.%I to service_role',
    candidate_id
  );
  perform pg_catalog.pg_notify('pgrst', 'reload schema');

  for device_record in
    select value from pg_catalog.jsonb_array_elements(p_devices) as items(value)
  loop
    device_number := device_number + 1;
    execute pg_catalog.format(
      'insert into public.%I
        (deviceid, device, discription)
       values ($1, $2, $3)',
      candidate_id
    )
    using
      device_number,
      pg_catalog.btrim(device_record ->> 'device'),
      nullif(pg_catalog.btrim(device_record ->> 'description'), '');
  end loop;

  return candidate_id;
end;
$$;

revoke all on function public.create_fix_request(
  text, text, text, double precision, double precision, jsonb
) from public, anon, authenticated;
grant execute on function public.create_fix_request(
  text, text, text, double precision, double precision, jsonb
) to service_role;

create or replace function public.discard_fix_request(p_ticket_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_ticket_id !~ '^[0-9]{10}$' then
    raise exception 'Invalid ticket ID';
  end if;

  execute pg_catalog.format('drop table if exists public.%I', p_ticket_id);
  delete from public."FixList" where "TicketId" = p_ticket_id;
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;

revoke all on function public.discard_fix_request(text)
  from public, anon, authenticated;
grant execute on function public.discard_fix_request(text) to service_role;
