create table public."Deleted_Maintenance_Technicians" (
  uid text primary key check (uid ~ '^t_[0-9]{10}$'),
  deleted_at timestamptz not null default pg_catalog.now()
);

alter table public."Deleted_Maintenance_Technicians" enable row level security;
revoke all on table public."Deleted_Maintenance_Technicians"
  from public, anon, authenticated;

create function public.prevent_deleted_technician_uid_reuse()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public."Deleted_Maintenance_Technicians" as deleted
    where deleted.uid = new.uid
  ) then
    raise exception 'Deleted technician UID cannot be reused.'
      using errcode = '23505',
        constraint = 'deleted_maintenance_technician_uid_key';
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_deleted_technician_uid_reuse()
  from public, anon, authenticated;

create trigger prevent_deleted_technician_uid_reuse_on_insert
before insert on public."Maintenance_Users"
for each row
execute function public.prevent_deleted_technician_uid_reuse();

create trigger prevent_deleted_technician_uid_reuse_on_update
before update of uid on public."Maintenance_Users"
for each row
execute function public.prevent_deleted_technician_uid_reuse();

create function public.delete_maintenance_technician(p_technician_uid text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  technician_username text;
  deleted_login_count integer;
begin
  if p_technician_uid is null
    or p_technician_uid !~ '^t_[0-9]{10}$' then
    raise exception 'Invalid technician UID.';
  end if;

  select technician.username
  into technician_username
  from public."Maintenance_Users" as technician
  where technician.uid = p_technician_uid
  for update;

  if not found then
    return false;
  end if;

  perform 1
  from public."Systems_Users" as system_user
  where system_user.role = 'Technician'
    and pg_catalog.lower(pg_catalog.btrim(system_user."Username")) =
      pg_catalog.lower(pg_catalog.btrim(technician_username))
  for update;
  if not found then
    raise exception 'Technician login account could not be found.';
  end if;

  insert into public."Deleted_Maintenance_Technicians" (uid)
  values (p_technician_uid)
  on conflict (uid) do nothing;

  delete from public."Systems_Users" as system_user
  where system_user.role = 'Technician'
    and pg_catalog.lower(pg_catalog.btrim(system_user."Username")) =
      pg_catalog.lower(pg_catalog.btrim(technician_username));
  get diagnostics deleted_login_count = row_count;
  if deleted_login_count <> 1 then
    raise exception 'Technician login account could not be deleted.';
  end if;

  delete from public."Maintenance_Users" as technician
  where technician.uid = p_technician_uid;
  if not found then
    raise exception 'Technician profile could not be deleted.';
  end if;

  return true;
end;
$$;

revoke all on function public.delete_maintenance_technician(text)
  from public, anon, authenticated;
grant execute on function public.delete_maintenance_technician(text)
  to service_role;

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;
