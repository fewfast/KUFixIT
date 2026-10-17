drop function if exists public.create_maintenance_team(
  uuid, text, text, text, text, text, text
);
drop function if exists public.create_maintenance_team(
  uuid, text, text, text, text, text
);
drop function if exists public.rename_maintenance_team(uuid, text);

alter table public."Maintenance_Users"
  drop constraint if exists maintenance_users_time_pairs_check,
  drop constraint if exists maintenance_users_pkey;

drop index if exists public.maintenance_users_uid_key;

alter table public."Maintenance_Users"
  drop column if exists legacy_time_of_day_start,
  drop column if exists legacy_time_of_day_end,
  drop column if exists id,
  drop column if exists id_team,
  drop column if exists status;

alter table public."Maintenance_Users"
  add constraint maintenance_users_pkey primary key (uid);

create function public.create_maintenance_technician(
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
    or p_username !~ '^[A-Za-z0-9_]{3,64}$'
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

revoke all on function public.create_maintenance_technician(
  text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_maintenance_technician(
  text, text, text, text, text, text
) to service_role;

create or replace function public.authenticate_system_user(
  p_username text,
  p_password text
)
returns table (
  username text,
  role text,
  endtime timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select
    staff_account."Username",
    staff_account.role,
    staff_account.endtime
  from public."Systems_Users" as staff_account
  where pg_catalog.lower(pg_catalog.btrim(staff_account."Username")) =
      pg_catalog.lower(pg_catalog.btrim(p_username))
    and staff_account."Password" =
      extensions.crypt(p_password, staff_account."Password")
    and (
      staff_account.endtime is null
      or staff_account.endtime > pg_catalog.now()
    )
    and (
      staff_account.role <> 'Technician'
      or exists (
        select 1
        from public."Maintenance_Users" as technician
        where pg_catalog.lower(pg_catalog.btrim(technician.username)) =
            pg_catalog.lower(pg_catalog.btrim(staff_account."Username"))
          and pg_catalog.cardinality(technician.start_time) > 0
          and exists (
            select 1
            from pg_catalog.generate_subscripts(technician.start_time, 1)
              as schedule(index)
            where pg_catalog.timezone(
                    'Asia/Bangkok',
                    pg_catalog.now()
                  )::date between
                  pg_catalog.timezone(
                    'Asia/Bangkok',
                    technician.start_time[schedule.index]
                  )::date
                  and pg_catalog.timezone(
                    'Asia/Bangkok',
                    technician.end_time[schedule.index]
                  )::date
          )
      )
    )
  limit 1;
$$;

revoke all on function public.authenticate_system_user(text, text)
  from public, anon, authenticated;
grant execute on function public.authenticate_system_user(text, text)
  to service_role;

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;
