create table public.superadmin_user_change_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  target_uid text not null,
  target_display_name text not null,
  current_display_name text not null,
  old_role text not null,
  current_status text not null,
  requested_display_name text,
  requested_role text,
  requested_status text,
  requester_id text not null,
  requester_is_system boolean not null,
  requester_display_name text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  decided_at timestamptz,
  decided_by text,
  decided_by_is_system boolean,
  constraint superadmin_user_change_requests_changes_check check (
    requested_display_name is not null
    or requested_role is not null
    or requested_status is not null
  ),
  constraint superadmin_user_change_requests_display_name_check check (
    requested_display_name is null
    or (
      pg_catalog.btrim(requested_display_name) <> ''
      and pg_catalog.length(requested_display_name) <= 160
    )
  ),
  constraint superadmin_user_change_requests_role_check check (
    requested_role is null or requested_role in ('User', 'Admin')
  ),
  constraint superadmin_user_change_requests_user_status_check check (
    requested_status is null or requested_status in ('active', 'unactive')
  )
);

create index superadmin_user_change_requests_status_created_at_idx
  on public.superadmin_user_change_requests (status, created_at desc);

alter table public.superadmin_user_change_requests enable row level security;
revoke all on table public.superadmin_user_change_requests
  from public, anon, authenticated;
grant select, insert, update on table public.superadmin_user_change_requests
  to service_role;

create or replace function public.resolve_superadmin_user_change_request(
  p_request_id uuid,
  p_actor_id text,
  p_actor_is_system boolean,
  p_decision text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  change_request public.superadmin_user_change_requests%rowtype;
  actor_role text;
  actor_status text;
  actor_endtime timestamptz;
  affected_rows integer;
begin
  if p_actor_id is null or p_actor_id = '' or p_actor_is_system is null
    or p_decision is null
    or p_decision not in ('approved', 'rejected') then
    raise exception 'Invalid approval decision.';
  end if;

  if p_actor_is_system then
    select account.role, account.endtime
    into actor_role, actor_endtime
    from public."Systems_Users" as account
    where account."Username" = p_actor_id;
    if not found or actor_role <> 'SuperAdmin'
      or (actor_endtime is not null and actor_endtime <= now()) then
      raise exception 'An active SuperAdmin account is required.';
    end if;
  else
    select account.role, account.status
    into actor_role, actor_status
    from public."Users" as account
    where account.google_auth_user_id::text = p_actor_id;
    if not found or actor_role <> 'SuperAdmin' or actor_status <> 'active' then
      raise exception 'An active SuperAdmin account is required.';
    end if;
  end if;

  select *
  into change_request
  from public.superadmin_user_change_requests
  where id = p_request_id
  for update;
  if not found then
    raise exception 'The user change request was not found.';
  end if;
  if change_request.status <> 'pending' then
    raise exception 'This user change request has already been resolved.';
  end if;
  if change_request.requester_id = p_actor_id
    and change_request.requester_is_system = p_actor_is_system then
    raise exception 'A different SuperAdmin must review this request.';
  end if;

  if p_decision = 'approved' then
    update public."Users"
    set
      "Display Name" = coalesce(
        change_request.requested_display_name,
        "Display Name"
      ),
      role = coalesce(change_request.requested_role, role),
      status = coalesce(change_request.requested_status, status)
    where uid = change_request.target_uid;
    get diagnostics affected_rows = row_count;
    if affected_rows = 0 then
      raise exception 'The target user no longer exists.';
    end if;
  end if;

  update public.superadmin_user_change_requests
  set
    status = p_decision,
    decided_at = now(),
    decided_by = p_actor_id,
    decided_by_is_system = p_actor_is_system
  where id = p_request_id;

  return p_decision;
end;
$$;

revoke all on function public.resolve_superadmin_user_change_request(
  uuid, text, boolean, text
) from public, anon, authenticated;
grant execute on function public.resolve_superadmin_user_change_request(
  uuid, text, boolean, text
) to service_role;
