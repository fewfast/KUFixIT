do $$
declare
  function_definition text;
  old_floor_validation constant text :=
    E'      if pg_catalog.length(pg_catalog.btrim(device_record ->> ''floor'')) > 2\n         or pg_catalog.btrim(device_record ->> ''floor'')::integer > 50 then\n        raise exception ''Floor must be 50 or less'';\n      end if;';
  new_floor_validation constant text :=
    E'      if pg_catalog.length(pg_catalog.ltrim(pg_catalog.btrim(device_record ->> ''floor''), ''0'')) > 2 then\n        raise exception ''Floor must be 50 or less'';\n      elsif coalesce(\n        nullif(pg_catalog.ltrim(pg_catalog.btrim(device_record ->> ''floor''), ''0''), '''')::integer,\n        0\n      ) > 50 then\n        raise exception ''Floor must be 50 or less'';\n      end if;';
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

  if pg_catalog.strpos(function_definition, old_floor_validation) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_floor_validation,
      new_floor_validation
    );
  elsif pg_catalog.strpos(
    function_definition,
    'pg_catalog.ltrim(pg_catalog.btrim(device_record ->> ''floor''), ''0'')'
  ) = 0 then
    raise exception 'Could not safely validate leading zeroes in floor values.';
  end if;

  execute function_definition;
end;
$$;
