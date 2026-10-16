alter table public."FixList"
  add column if not exists technician_history text[] default null;

do $$
declare
  ticket_id text;
  ticket_table regclass;
  column_type oid;
  migrated_history text[];
begin
  for ticket_id in
    select "TicketId" from public."FixList"
  loop
    ticket_table := pg_catalog.to_regclass(
      pg_catalog.format('public.%I', ticket_id)
    );
    if ticket_table is null then
      continue;
    end if;

    select attribute.atttypid
      into column_type
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = ticket_table
      and attribute.attname = 'fix_history_progress'
      and not attribute.attisdropped;

    if column_type = 'text[]'::pg_catalog.regtype then
      execute pg_catalog.format(
        'alter table public.%I
         alter column fix_history_progress type boolean[]
         using case
           when fix_history_progress is null then null
           else pg_catalog.array_fill(
             false,
             array[coalesce(array_length(fix_history_progress, 1), 0)]
           )
         end',
        ticket_id
      );
    elsif column_type is not null
      and column_type <> 'boolean[]'::pg_catalog.regtype then
      raise exception 'Unexpected fix_history_progress type in ticket table %: %',
        ticket_id, column_type::pg_catalog.regtype;
    end if;

    select attribute.atttypid
      into column_type
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = ticket_table
      and attribute.attname = 'technician_history'
      and not attribute.attisdropped;

    if column_type = 'text[]'::pg_catalog.regtype then
      execute pg_catalog.format(
        'select array_agg(
           schedule.technician
           order by schedule.fix_time nulls last, device.deviceid, history.ordinality
         )
         from public.%I as device
         cross join lateral generate_series(
           1,
           greatest(
             coalesce(array_length(device.fix_history_time, 1), 0),
             coalesce(array_length(device.fix_history_progress, 1), 0),
             coalesce(array_length(device.technician_history, 1), 0),
             coalesce(array_length(device.technician_comment, 1), 0)
           )
         ) as history(ordinality)
         left join lateral (
           select
             device.technician_history[history.ordinality] as technician,
             device.fix_history_time[history.ordinality] as fix_time
         ) as schedule on true',
        ticket_id
      )
      into migrated_history;

      update public."FixList"
      set technician_history = coalesce(technician_history, migrated_history)
      where "TicketId" = ticket_id;

      execute pg_catalog.format(
        'alter table public.%I drop column technician_history',
        ticket_id
      );
    elsif column_type is not null then
      raise exception 'Unexpected technician_history type in ticket table %: %',
        ticket_id, column_type::pg_catalog.regtype;
    end if;
  end loop;

  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;

do $$
declare
  function_definition text;
  old_progress_definition constant text :=
    'fix_history_progress text[] default null';
  new_progress_definition constant text :=
    'fix_history_progress boolean[] default null';
  old_technician_definition constant text :=
    E'      technician_history text[] default null,\n';
begin
  function_definition := pg_catalog.pg_get_functiondef(
    'public.create_fix_request(text,text,text,double precision,double precision,jsonb)'
      ::pg_catalog.regprocedure
  );
  function_definition := pg_catalog.replace(
    function_definition,
    E'\r\n',
    E'\n'
  );

  if pg_catalog.strpos(function_definition, old_progress_definition) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_progress_definition,
      new_progress_definition
    );
  elsif pg_catalog.strpos(function_definition, new_progress_definition) = 0 then
    raise exception 'Could not change fix_history_progress to boolean[].';
  end if;

  if pg_catalog.strpos(function_definition, old_technician_definition) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_technician_definition,
      ''
    );
  elsif pg_catalog.strpos(function_definition, 'technician_history text[]') > 0 then
    raise exception 'Could not remove technician_history from ticket tables.';
  end if;

  execute function_definition;
end;
$$;
