-- Use a unique RPC name to avoid PostgREST overload ambiguity. The ticket,
-- dynamic child-device rows, and technician assignment are committed together.
-- Older dynamic ticket tables may predate the scalar device schedule column.
-- The schedule is nullable and existing table data is preserved by this add.
do $$
declare
  ticket_id text;
begin
  for ticket_id in
    select ticket."TicketId" from public."FixList" as ticket
  loop
    if pg_catalog.to_regclass(
      pg_catalog.format('public.%I', ticket_id)
    ) is not null then
      execute pg_catalog.format(
        'alter table public.%I add column if not exists next_fix_date timestamptz',
        ticket_id
      );
    end if;
  end loop;
end;
$$;

create or replace function public.admin_update_ticket_assignment_atomic(
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
  p_next_fix_date_end timestamptz,
  p_devices jsonb
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
  existing_device_count integer;
  provided_device_count integer;
  distinct_device_count integer;
  missing_device_count integer;
begin
  if p_ticket_id is null or p_ticket_id !~ '^[0-9]{10}$'
    or p_status is null
    or p_status not in ('pending', 'finish', 'rejected', 'cancel')
    or pg_catalog.jsonb_typeof(p_devices) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_devices) > 50
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

  if exists (
    select 1
    from pg_catalog.jsonb_to_recordset(p_devices) as device(
      deviceid integer,
      status text
    )
    where device.status is null
      or device.status not in ('pending', 'rejected', 'finish')
  ) or (p_status = 'pending' and not exists (
    select 1
    from pg_catalog.jsonb_to_recordset(p_devices) as device(
      deviceid integer,
      status text
    )
    where device.status = 'pending'
  )) or (p_status = 'rejected' and exists (
    select 1
    from pg_catalog.jsonb_to_recordset(p_devices) as device(
      deviceid integer,
      status text
    )
    where device.status <> 'rejected'
  )) or (p_status = 'finish' and exists (
    select 1
    from pg_catalog.jsonb_to_recordset(p_devices) as device(
      deviceid integer,
      status text
    )
    where device.status not in ('rejected', 'finish')
  )) then
    raise exception 'Invalid ticket or device status combination.';
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

  execute pg_catalog.format(
    'select count(*) from public.%I', p_ticket_id
  ) into existing_device_count;
  select count(*), count(distinct device.deviceid)
  into provided_device_count, distinct_device_count
  from pg_catalog.jsonb_to_recordset(p_devices) as device(
    deviceid integer,
    device text,
    discription text,
    status text,
    next_fix_date timestamptz,
    technician_comment text[]
  );
  if provided_device_count <> existing_device_count
    or provided_device_count <> distinct_device_count then
    raise exception 'Ticket device list does not match.';
  end if;

  execute pg_catalog.format(
    'select count(*) from public.%I as current_device
     where not exists (
       select 1 from pg_catalog.jsonb_to_recordset($1) as submitted(deviceid integer)
       where submitted.deviceid = current_device.deviceid
     )',
    p_ticket_id
  ) into missing_device_count using p_devices;
  if missing_device_count <> 0 then
    raise exception 'Ticket device list does not match.';
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

  execute pg_catalog.format(
    'update public.%I as current_device
     set device = submitted.device,
         discription = submitted.discription,
         status = submitted.status,
         next_fix_date = submitted.next_fix_date,
         technician_comment = submitted.technician_comment
     from pg_catalog.jsonb_to_recordset($1) as submitted(
       deviceid integer,
       device text,
       discription text,
       status text,
       next_fix_date timestamptz,
       technician_comment text[]
     )
     where current_device.deviceid = submitted.deviceid',
    p_ticket_id
  ) using p_devices;

  perform public.sync_maintenance_team_ticket_assignment(
    p_ticket_id,
    old_team_name,
    p_technician_team,
    should_assign
  );
end;
$$;

revoke all on function public.admin_update_ticket_assignment_atomic(
  text, text, double precision, double precision, text, text, text, text,
  text, timestamptz, timestamptz, jsonb
) from public, anon, authenticated;
grant execute on function public.admin_update_ticket_assignment_atomic(
  text, text, double precision, double precision, text, text, text, text,
  text, timestamptz, timestamptz, jsonb
) to service_role;

notify pgrst, 'reload schema';
