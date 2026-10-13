do $$
declare
  ticket_id text;
  column_type oid;
  function_definition text;
  old_column_definition constant text :=
    'next_fix_date timestamptz[] default null';
begin
  for ticket_id in
    select "TicketId" from public."FixList"
  loop
    if pg_catalog.to_regclass(
      pg_catalog.format('public.%I', ticket_id)
    ) is null then
      continue;
    end if;

    select attribute.atttypid
      into column_type
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid =
      pg_catalog.to_regclass(pg_catalog.format('public.%I', ticket_id))
      and attribute.attname = 'next_fix_date'
      and not attribute.attisdropped;

    if column_type = 'timestamptz[]'::pg_catalog.regtype then
      execute pg_catalog.format(
        'alter table public.%I
         alter column next_fix_date type timestamptz
         using next_fix_date[pg_catalog.array_upper(next_fix_date, 1)]',
        ticket_id
      );
    elsif column_type is not null
      and column_type <> 'timestamptz'::pg_catalog.regtype then
      raise exception 'Unexpected next_fix_date type in ticket table %: %',
        ticket_id, column_type::pg_catalog.regtype;
    end if;
  end loop;

  function_definition := pg_catalog.pg_get_functiondef(
    'public.create_fix_request(text,text,text,double precision,double precision,jsonb)'
      ::pg_catalog.regprocedure
  );

  if pg_catalog.strpos(function_definition, old_column_definition) > 0 then
    execute pg_catalog.replace(
      function_definition,
      old_column_definition,
      'next_fix_date timestamptz default null'
    );
  elsif pg_catalog.strpos(
    function_definition,
    'next_fix_date timestamptz default null'
  ) = 0 then
    raise exception 'Could not update create_fix_request next_fix_date type.';
  end if;
end;
$$;
