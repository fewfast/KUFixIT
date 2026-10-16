alter table public."FixList"
  add column if not exists fix_history_time timestamptz[] default null;

do $$
declare
  ticket_id text;
  ticket_table regclass;
  column_type oid;
  migrated_history timestamptz[];
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
      and attribute.attname = 'fix_history_time'
      and not attribute.attisdropped;

    if column_type = 'timestamptz[]'::pg_catalog.regtype then
      execute pg_catalog.format(
        'select array_agg(
           (
             select min(device.fix_history_time[history.ordinality])
             from public.%I as device
           )
           order by history.ordinality
         )
         from generate_series(
           1,
           (
             select greatest(
               coalesce(max(array_length(fix_history_time, 1)), 0),
               coalesce(max(array_length(fix_history_progress, 1)), 0)
             )
             from public.%I
           )
         ) as history(ordinality)',
        ticket_id,
        ticket_id
      )
      into migrated_history;

      update public."FixList"
      set fix_history_time = coalesce(fix_history_time, migrated_history)
      where "TicketId" = ticket_id;

      execute pg_catalog.format(
        'alter table public.%I drop column fix_history_time',
        ticket_id
      );
    elsif column_type is not null then
      raise exception 'Unexpected fix_history_time type in ticket table %: %',
        ticket_id, column_type::pg_catalog.regtype;
    end if;
  end loop;

  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;

do $$
declare
  function_definition text;
  old_history_definition constant text :=
    E'      fix_history_time timestamptz[] default null,\n';
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

  if pg_catalog.strpos(function_definition, old_history_definition) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_history_definition,
      ''
    );
  elsif pg_catalog.strpos(function_definition, 'fix_history_time timestamptz[]') > 0 then
    raise exception 'Could not remove fix_history_time from ticket tables.';
  end if;

  execute function_definition;
end;
$$;
