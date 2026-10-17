create function public.update_maintenance_technician_username(
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

revoke all on function public.update_maintenance_technician_username(text, text)
  from public, anon, authenticated;
grant execute on function public.update_maintenance_technician_username(text, text)
  to service_role;

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;
