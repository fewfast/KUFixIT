alter table public."FixList"
  add column if not exists request_date timestamptz not null
    default pg_catalog.now();

do $$
declare
  ticket_id text;
  ticket_table regclass;
  column_type oid;
  function_definition text;
  scalar_definition constant text :=
    'next_fix_date timestamptz default null';
  array_definition constant text :=
    'next_fix_date timestamptz[] default null';
  old_insert_columns constant text :=
    E'    "TicketId",\n    requester,';
  new_insert_columns constant text :=
    E'    "TicketId",\n    request_date,\n    requester,';
  old_insert_values constant text :=
    E'    candidate_id,\n    p_requester,';
  new_insert_values constant text :=
    E'    candidate_id,\n    pg_catalog.now(),\n    p_requester,';
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
      and attribute.attname = 'next_fix_date'
      and not attribute.attisdropped;

    if column_type = 'timestamptz'::pg_catalog.regtype then
      execute pg_catalog.format(
        'alter table public.%I
         alter column next_fix_date type timestamptz[]
         using case
           when next_fix_date is null then null
           else array[next_fix_date]
         end',
        ticket_id
      );
    elsif column_type is not null
      and column_type <> 'timestamptz[]'::pg_catalog.regtype then
      raise exception 'Unexpected next_fix_date type in ticket table %: %',
        ticket_id, column_type::pg_catalog.regtype;
    end if;
  end loop;
  perform pg_catalog.pg_notify('pgrst', 'reload schema');

  function_definition := pg_catalog.pg_get_functiondef(
    'public.create_fix_request(text,text,text,double precision,double precision,jsonb)'
      ::pg_catalog.regprocedure
  );
  function_definition := pg_catalog.replace(
    function_definition,
    E'\r\n',
    E'\n'
  );

  if pg_catalog.strpos(function_definition, scalar_definition) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      scalar_definition,
      array_definition
    );
  elsif pg_catalog.strpos(function_definition, array_definition) = 0 then
    raise exception 'Could not restore create_fix_request next_fix_date array.';
  end if;

  if pg_catalog.strpos(function_definition, old_insert_columns) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_insert_columns,
      new_insert_columns
    );
  elsif pg_catalog.strpos(function_definition, new_insert_columns) = 0 then
    raise exception 'Could not add request_date to create_fix_request insert.';
  end if;

  if pg_catalog.strpos(function_definition, old_insert_values) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_insert_values,
      new_insert_values
    );
  elsif pg_catalog.strpos(function_definition, new_insert_values) = 0 then
    raise exception 'Could not add request timestamp to create_fix_request.';
  end if;

  execute function_definition;
end;
$$;
