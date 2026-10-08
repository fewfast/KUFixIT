create extension if not exists pgcrypto with schema extensions;

create table public."Systems_Users" (
  "Username" text not null check (pg_catalog.btrim("Username") <> ''),
  "Password" text not null
    check ("Password" ~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$'),
  role text not null check (role in ('Technician', 'Admin', 'SuperAdmin')),
  created_at timestamptz not null default now(),
  endtime timestamptz
);

create unique index systems_users_username_lower_unique_idx
  on public."Systems_Users" (pg_catalog.lower(pg_catalog.btrim("Username")));

alter table public."Systems_Users" enable row level security;
revoke all on table public."Systems_Users" from public, anon, authenticated;
grant select, insert, update, delete on table public."Systems_Users" to service_role;

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
  limit 1;
$$;

revoke all on function public.authenticate_system_user(text, text)
  from public, anon, authenticated;
grant execute on function public.authenticate_system_user(text, text)
  to service_role;
