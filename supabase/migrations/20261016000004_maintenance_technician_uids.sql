alter table public."Maintenance_Users"
  add column if not exists uid text;

update public."Maintenance_Users"
set uid = null;

do $$
declare
  technician_row record;
  candidate_uid text;
begin
  perform pg_catalog.pg_advisory_xact_lock(192837465, 564738292);

  for technician_row in
    select ctid
    from public."Maintenance_Users"
  loop
    loop
      candidate_uid := 't_' || (
        1000000000 +
        pg_catalog.floor(pg_catalog.random() * 9000000000)::bigint
      )::text;
      exit when not exists (
        select 1
        from public."Maintenance_Users"
        where uid = candidate_uid
      );
    end loop;

    update public."Maintenance_Users"
    set uid = candidate_uid
    where ctid = technician_row.ctid;
  end loop;
end;
$$;

alter table public."Maintenance_Users"
  alter column uid set not null;

create unique index if not exists maintenance_users_uid_key
  on public."Maintenance_Users" (uid);

alter table public."Maintenance_Users"
  add constraint maintenance_users_uid_format
  check (uid ~ '^t_[0-9]{10}$');

create or replace function public.create_technician_ticket_table(p_uid text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_uid is null or p_uid !~ '^t_[0-9]{10}$' then
    raise exception 'Invalid technician UID.';
  end if;

  execute pg_catalog.format(
    'create table if not exists public.%I (
      ticket_id text primary key
        references public."FixList" ("TicketId") on delete cascade,
      assigned_at timestamptz not null default pg_catalog.now(),
      status text not null default %L,
      "ticketId" text generated always as (ticket_id) stored,
      report text,
      result boolean not null default false,
      bucket text generated always as (%L || ticket_id) stored
    )',
    p_uid,
    'assigned',
    'result_'
  );
  execute pg_catalog.format(
    'alter table public.%I enable row level security',
    p_uid
  );
  execute pg_catalog.format(
    'revoke all on table public.%I from public, anon, authenticated',
    p_uid
  );
  execute pg_catalog.format(
    'grant select, insert, update, delete on table public.%I to service_role',
    p_uid
  );
end;
$$;

revoke all on function public.create_technician_ticket_table(text)
  from public, anon, authenticated;
grant execute on function public.create_technician_ticket_table(text)
  to service_role;

do $$
declare
  technician_uid text;
begin
  for technician_uid in
    select uid from public."Maintenance_Users"
  loop
    perform public.create_technician_ticket_table(technician_uid);
  end loop;
end;
$$;

drop function if exists public.create_maintenance_team(
  uuid, text, text, text, text
);

create function public.create_maintenance_team(
  p_id_team uuid,
  p_technician_uid text,
  p_team_name text,
  p_username text,
  p_password text,
  p_encrypted_password text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  team_name text := pg_catalog.btrim(p_team_name);
  resolved_team_id uuid;
  resolved_technician_uid text := p_technician_uid;
begin
  if p_id_team is null
    or p_technician_uid is null
    or p_technician_uid !~ '^t_[0-9]{10}$'
    or team_name is null
    or team_name = ''
    or pg_catalog.length(team_name) > 100
    or p_username is null
    or p_username !~ '^[A-Za-z0-9_]{3,64}$'
    or p_password is null
    or pg_catalog.octet_length(p_password) > 72
    or p_encrypted_password is null then
    raise exception 'Invalid maintenance team details.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(pg_catalog.lower(team_name), 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(192837465, 564738292);

  while exists (
    select 1
    from public."Maintenance_Users"
    where uid = resolved_technician_uid
  )
  loop
    resolved_technician_uid := 't_' || (
      1000000000 +
      pg_catalog.floor(pg_catalog.random() * 9000000000)::bigint
    )::text;
  end loop;

  select maintenance_user.id_team
    into resolved_team_id
  from public."Maintenance_Users" as maintenance_user
  where pg_catalog.lower(pg_catalog.btrim(maintenance_user."teamName")) =
    pg_catalog.lower(team_name)
  order by maintenance_user.created_at asc
  limit 1;

  if resolved_team_id is null then
    resolved_team_id := p_id_team;
  end if;

  insert into public."Maintenance_Users" (
    id_team,
    uid,
    "teamName",
    username,
    password,
    start_time,
    end_time,
    status
  )
  values (
    resolved_team_id,
    resolved_technician_uid,
    team_name,
    p_username,
    p_encrypted_password,
    array[]::time[],
    array[]::time[],
    true
  );

  insert into public."Systems_Users" ("Username", "Password", role)
  values (
    p_username,
    extensions.crypt(p_password, extensions.gen_salt('bf', 12)),
    'Technician'
  );

  perform public.create_technician_ticket_table(resolved_technician_uid);

  return pg_catalog.jsonb_build_object(
    'id_team',
    resolved_team_id,
    'uid',
    resolved_technician_uid
  );
end;
$$;

revoke all on function public.create_maintenance_team(
  uuid, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_maintenance_team(
  uuid, text, text, text, text, text
) to service_role;

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;
