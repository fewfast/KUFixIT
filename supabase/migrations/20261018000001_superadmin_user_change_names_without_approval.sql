create or replace function public.submit_superadmin_user_change(
  p_target_uid text,
  p_requester_id text,
  p_requester_is_system boolean,
  p_requester_display_name text,
  p_display_name text,
  p_role text,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user public."Users"%rowtype;
  requester_role text;
  requester_status text;
  requester_endtime timestamptz;
  display_name_changed boolean;
  role_changed boolean;
  status_changed boolean;
  request_id uuid;
begin
  if p_target_uid is null or p_target_uid !~ '^u_[0-9]{10}$'
    or p_requester_id is null or p_requester_id = ''
    or p_requester_is_system is null
    or p_requester_display_name is null
    or pg_catalog.btrim(p_requester_display_name) = ''
    or p_display_name is not null and (
      pg_catalog.btrim(p_display_name) = ''
      or pg_catalog.length(p_display_name) > 160
    )
    or p_role is not null and p_role not in ('User', 'Admin')
    or p_status is not null and p_status not in ('active', 'unactive') then
    raise exception 'Invalid user change request.';
  end if;

  if p_requester_is_system then
    select account.role, account.endtime
    into requester_role, requester_endtime
    from public."Systems_Users" as account
    where account."Username" = p_requester_id;
    if not found or requester_role <> 'SuperAdmin'
      or (requester_endtime is not null and requester_endtime <= now()) then
      raise exception 'An active SuperAdmin account is required.';
    end if;
  else
    select account.role, account.status
    into requester_role, requester_status
    from public."Users" as account
    where account.google_auth_user_id::text = p_requester_id;
    if not found or requester_role <> 'SuperAdmin'
      or requester_status <> 'active' then
      raise exception 'An active SuperAdmin account is required.';
    end if;
  end if;

  select *
  into target_user
  from public."Users"
  where uid = p_target_uid
  for update;
  if not found then
    raise exception 'The target user no longer exists.';
  end if;

  display_name_changed := p_display_name is not null
    and p_display_name is distinct from target_user."Display Name";
  role_changed := p_role is not null and p_role is distinct from target_user.role;
  status_changed := p_status is not null
    and p_status is distinct from target_user.status;
  if not display_name_changed and not role_changed and not status_changed then
    raise exception 'There are no user changes to save.';
  end if;

  if display_name_changed then
    update public."Users"
    set "Display Name" = p_display_name
    where uid = p_target_uid;
    target_user."Display Name" := p_display_name;
  end if;

  if not role_changed and not status_changed then
    return pg_catalog.jsonb_build_object(
      'status', 'updated',
      'displayNameUpdated', display_name_changed
    );
  end if;

  insert into public.superadmin_user_change_requests (
    target_uid,
    target_display_name,
    current_display_name,
    old_role,
    current_status,
    requested_role,
    requested_status,
    requester_id,
    requester_is_system,
    requester_display_name
  )
  values (
    target_user.uid,
    target_user."Display Name",
    target_user."Display Name",
    target_user.role,
    target_user.status,
    case when role_changed then p_role else null end,
    case when status_changed then p_status else null end,
    p_requester_id,
    p_requester_is_system,
    p_requester_display_name
  )
  returning id into request_id;

  return pg_catalog.jsonb_build_object(
    'status', 'pending',
    'displayNameUpdated', display_name_changed,
    'requestId', request_id
  );
end;
$$;

revoke all on function public.submit_superadmin_user_change(
  text, text, boolean, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.submit_superadmin_user_change(
  text, text, boolean, text, text, text, text
) to service_role;
