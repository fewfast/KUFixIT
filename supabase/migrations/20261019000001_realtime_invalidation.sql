create or replace function public.broadcast_app_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    '{"type":"invalidate"}'::jsonb,
    'invalidate',
    'kufixit:invalidate',
    true
  );
  return null;
end;
$$;

revoke all on function public.broadcast_app_invalidation()
  from public, anon, authenticated;

create or replace function public.install_realtime_invalidation_trigger(
  p_schema_name text,
  p_table_name text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_table pg_catalog.regclass;
begin
  if p_schema_name not in ('public', 'storage') then
    raise exception 'Realtime invalidation trigger schema is not allowed.';
  end if;

  target_table := pg_catalog.to_regclass(
    pg_catalog.format('%I.%I', p_schema_name, p_table_name)
  );
  if target_table is null then
    raise exception 'Realtime invalidation table %.% was not found.',
      p_schema_name, p_table_name;
  end if;

  execute pg_catalog.format(
    'drop trigger if exists kufixit_realtime_invalidation on %s',
    target_table
  );
  execute pg_catalog.format(
    'create trigger kufixit_realtime_invalidation
     after insert or update or delete on %s
     for each statement
     execute function public.broadcast_app_invalidation()',
    target_table
  );
end;
$$;

revoke all on function public.install_realtime_invalidation_trigger(text, text)
  from public, anon, authenticated;

drop policy if exists kufixit_receive_invalidation
  on realtime.messages;
create policy kufixit_receive_invalidation
  on realtime.messages
  for select
  to anon
  using (realtime.topic() = 'kufixit:invalidate');

do $$
declare
  relation record;
begin
  for relation in
    select schema.nspname as schema_name, table_relation.relname as table_name
    from pg_catalog.pg_class as table_relation
    join pg_catalog.pg_namespace as schema
      on schema.oid = table_relation.relnamespace
    where table_relation.relkind in ('r', 'p')
      and (
        (schema.nspname = 'public' and table_relation.relname in (
          'Users',
          'Systems_Users',
          'Maintenance_Users',
          'Deleted_Maintenance_Technicians',
          'FixList',
          'email_change_requests',
          'superadmin_user_change_requests',
          'technician_work_reports'
        ))
        or (
          schema.nspname = 'public'
          and table_relation.relname ~ '^[0-9]{10}$'
        )
        or (
          schema.nspname = 'public'
          and table_relation.relname ~ '^t_[0-9]{10}$'
        )
        or (
          schema.nspname = 'storage'
          and table_relation.relname = 'objects'
        )
      )
  loop
    perform public.install_realtime_invalidation_trigger(
      relation.schema_name,
      relation.table_name
    );
  end loop;
end;
$$;

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
      "ticketId" text primary key
        references public."FixList" ("TicketId") on delete cascade
    )',
    p_uid
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
  perform public.install_realtime_invalidation_trigger('public', p_uid);
end;
$$;

revoke all on function public.create_technician_ticket_table(text)
  from public, anon, authenticated;
grant execute on function public.create_technician_ticket_table(text)
  to service_role;

do $$
declare
  function_definition text;
  return_marker constant text := '  return candidate_id;';
  install_call constant text :=
    '  perform public.install_realtime_invalidation_trigger(''public'', candidate_id);';
begin
  function_definition := pg_catalog.pg_get_functiondef(
    'public.create_fix_request(text,text,text,double precision,double precision,jsonb)'
      ::pg_catalog.regprocedure
  );

  if pg_catalog.strpos(function_definition, install_call) = 0 then
    if pg_catalog.strpos(function_definition, return_marker) = 0 then
      raise exception 'Could not add invalidation trigger to create_fix_request.';
    end if;
    function_definition := pg_catalog.replace(
      function_definition,
      return_marker,
      install_call || E'\n' || return_marker
    );
  end if;
  execute function_definition;
end;
$$;
