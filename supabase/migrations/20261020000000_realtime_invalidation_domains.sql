create or replace function public.broadcast_app_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  invalidation_domain text;
  marker constant jsonb := '{"type":"invalidate"}'::jsonb;
begin
  if tg_table_schema = 'storage' and tg_table_name = 'objects' then
    invalidation_domain := 'storage';
  elsif tg_table_schema = 'public' and tg_table_name in (
    'Users',
    'Systems_Users',
    'email_change_requests',
    'superadmin_user_change_requests'
  ) then
    invalidation_domain := 'accounts';
  elsif tg_table_schema = 'public' and tg_table_name in (
    'Maintenance_Users',
    'Deleted_Maintenance_Technicians'
  ) then
    invalidation_domain := 'technicians';
  elsif tg_table_schema = 'public'
    and tg_table_name ~ '^t_[0-9]{10}$' then
    invalidation_domain := 'technicians';
  elsif tg_table_schema = 'public'
    and tg_table_name = 'technician_work_reports' then
    invalidation_domain := 'reports';
  elsif tg_table_schema = 'public'
    and (tg_table_name = 'FixList' or tg_table_name ~ '^[0-9]{10}$') then
    invalidation_domain := 'tickets';
  else
    raise exception 'No invalidation domain is configured for %.%.',
      tg_table_schema, tg_table_name;
  end if;

  perform realtime.send(
    marker,
    'invalidate',
    'kufixit:invalidate:' || invalidation_domain,
    true
  );

  -- Keep the original topic live for older app versions during rollout.
  perform realtime.send(
    marker,
    'invalidate',
    'kufixit:invalidate',
    true
  );
  return null;
end;
$$;

revoke all on function public.broadcast_app_invalidation()
  from public, anon, authenticated;

drop policy if exists kufixit_receive_invalidation
  on realtime.messages;
create policy kufixit_receive_invalidation
  on realtime.messages
  for select
  to anon
  using (
    realtime.topic() in (
      'kufixit:invalidate',
      'kufixit:invalidate:accounts',
      'kufixit:invalidate:tickets',
      'kufixit:invalidate:technicians',
      'kufixit:invalidate:reports',
      'kufixit:invalidate:storage'
    )
  );
