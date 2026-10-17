create or replace function public.create_maintenance_technician(
  p_technician_uid text,
  p_team_name text,
  p_username text,
  p_password text,
  p_encrypted_password text,
  p_comment text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  team_name text := pg_catalog.btrim(p_team_name);
begin
  if p_technician_uid is null
    or p_technician_uid !~ '^t_[0-9]{10}$'
    or team_name is null
    or team_name = ''
    or pg_catalog.length(team_name) > 100
    or p_username is null
    or p_username !~ '^[A-Za-z0-9_]{3,10}$'
    or p_password is null
    or pg_catalog.octet_length(p_password) > 72
    or p_encrypted_password is null
    or p_comment is null
    or pg_catalog.btrim(p_comment) = ''
    or pg_catalog.length(p_comment) > 1000 then
    raise exception 'Invalid maintenance technician details.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(pg_catalog.lower(p_username), 0)
  );

  if exists (
    select 1
    from public."Maintenance_Users"
    where uid = p_technician_uid
  ) then
    raise exception 'Technician UID already exists.'
      using errcode = '23505';
  end if;

  insert into public."Maintenance_Users" (
    uid,
    "teamName",
    username,
    comment,
    password,
    start_time,
    end_time
  )
  values (
    p_technician_uid,
    team_name,
    p_username,
    p_comment,
    p_encrypted_password,
    array[]::timestamptz[],
    array[]::timestamptz[]
  );

  insert into public."Systems_Users" ("Username", "Password", role)
  values (
    p_username,
    extensions.crypt(p_password, extensions.gen_salt('bf', 12)),
    'Technician'
  );

  perform public.create_technician_ticket_table(p_technician_uid);
  return p_technician_uid;
end;
$$;

create or replace function public.update_maintenance_technician_username(
  p_technician_uid text,
  p_username text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_username text;
  updated_login_count integer;
begin
  if p_technician_uid is null
    or p_technician_uid !~ '^t_[0-9]{10}$'
    or p_username is null
    or p_username !~ '^[A-Za-z0-9_]{3,10}$' then
    raise exception 'Invalid technician UID or username.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(pg_catalog.lower(p_username), 0)
  );

  select technician.username
  into current_username
  from public."Maintenance_Users" as technician
  where technician.uid = p_technician_uid
  for update;

  if not found then
    return false;
  end if;

  perform 1
  from public."Systems_Users" as login_account
  where login_account.role = 'Technician'
    and pg_catalog.lower(pg_catalog.btrim(login_account."Username")) =
      pg_catalog.lower(pg_catalog.btrim(current_username))
  for update;

  if not found then
    raise exception 'Technician login account could not be found.';
  end if;

  update public."Systems_Users" as login_account
  set "Username" = p_username
  where login_account.role = 'Technician'
    and pg_catalog.lower(pg_catalog.btrim(login_account."Username")) =
      pg_catalog.lower(pg_catalog.btrim(current_username));
  get diagnostics updated_login_count = row_count;

  if updated_login_count <> 1 then
    raise exception 'Technician login account could not be updated.';
  end if;

  update public."Maintenance_Users" as technician
  set username = p_username
  where technician.uid = p_technician_uid;

  if not found then
    raise exception 'Technician profile could not be updated.';
  end if;

  return true;
end;
$$;

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;
