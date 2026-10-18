create or replace function public.sync_maintenance_team_ticket_assignment(
  p_ticket_id text,
  p_old_team_name text,
  p_new_team_name text,
  p_should_assign boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  technician_uid text;
  target_team_exists boolean := false;
begin
  if p_ticket_id is null or p_ticket_id !~ '^[0-9]{10}$' then
    raise exception 'Invalid ticket ID.';
  end if;

  if p_should_assign then
    if p_new_team_name is null or pg_catalog.btrim(p_new_team_name) = '' then
      raise exception 'A maintenance team is required for this assignment.';
    end if;

    for technician_uid in
      select maintenance_user.uid
      from public."Maintenance_Users" as maintenance_user
      where maintenance_user.status
        and pg_catalog.lower(pg_catalog.btrim(maintenance_user."teamName")) =
          pg_catalog.lower(pg_catalog.btrim(p_new_team_name))
    loop
      if technician_uid is null or technician_uid !~ '^t_[0-9]{10}$' then
        raise exception 'Invalid maintenance team UID.';
      end if;
      target_team_exists := true;

      execute pg_catalog.format(
        'insert into public.%I ("ticketId") values ($1)
         on conflict ("ticketId") do nothing',
        technician_uid
      ) using p_ticket_id;
    end loop;

    if not target_team_exists then
      raise exception 'The selected maintenance team was not found.';
    end if;
  end if;

  if p_old_team_name is not null then
    for technician_uid in
      select maintenance_user.uid
      from public."Maintenance_Users" as maintenance_user
      where pg_catalog.lower(pg_catalog.btrim(maintenance_user."teamName")) =
          pg_catalog.lower(pg_catalog.btrim(p_old_team_name))
        and (
          not p_should_assign
          or not maintenance_user.status
          or pg_catalog.lower(pg_catalog.btrim(maintenance_user."teamName")) <>
            pg_catalog.lower(pg_catalog.btrim(p_new_team_name))
        )
    loop
      if technician_uid is null or technician_uid !~ '^t_[0-9]{10}$' then
        raise exception 'Invalid maintenance team UID.';
      end if;

      execute pg_catalog.format(
        'delete from public.%I where "ticketId" = $1',
        technician_uid
      ) using p_ticket_id;
    end loop;
  end if;
end;
$$;

revoke all on function public.sync_maintenance_team_ticket_assignment(
  text, text, text, boolean
) from public, anon, authenticated;
grant execute on function public.sync_maintenance_team_ticket_assignment(
  text, text, text, boolean
) to service_role;

create or replace function public.admin_update_fixlist_and_assign_team(
  p_ticket_id text,
  p_building text,
  p_latitude double precision,
  p_longtitude double precision,
  p_area text,
  p_floor text,
  p_room text,
  p_status text,
  p_technician_team text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_team_name text;
  should_assign boolean := p_status = 'pending';
begin
  if p_ticket_id is null or p_ticket_id !~ '^[0-9]{10}$'
    or (should_assign and
      (p_technician_team is null or pg_catalog.btrim(p_technician_team) = ''))
    or (not should_assign and p_technician_team is not null) then
    raise exception 'Invalid repair request assignment.';
  end if;

  select ticket.technician_team
    into old_team_name
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
      technician_team = p_technician_team
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
  text, text, double precision, double precision, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.admin_update_fixlist_and_assign_team(
  text, text, double precision, double precision, text, text, text, text, text
) to service_role;
