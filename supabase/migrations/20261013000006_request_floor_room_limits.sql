do $$
declare
  function_definition text;
  old_validation constant text :=
    E'      raise exception ''Each repair request must include an equipment name'';\n    end if;\n  end loop;\n\n  first_device := p_devices -> 0;';
  new_validation constant text :=
    E'      raise exception ''Each repair request must include an equipment name'';\n    end if;\n\n    if nullif(pg_catalog.btrim(device_record ->> ''floor''), '''') is not null then\n      if pg_catalog.jsonb_typeof(device_record -> ''floor'') <> ''string''\n         or pg_catalog.btrim(device_record ->> ''floor'') !~ ''^[0-9]+$'' then\n        raise exception ''Floor must contain digits only'';\n      end if;\n      if pg_catalog.length(pg_catalog.btrim(device_record ->> ''floor'')) > 2\n         or pg_catalog.btrim(device_record ->> ''floor'')::integer > 50 then\n        raise exception ''Floor must be 50 or less'';\n      end if;\n    end if;\n\n    if nullif(pg_catalog.btrim(device_record ->> ''room''), '''') is not null\n       and (\n         pg_catalog.jsonb_typeof(device_record -> ''room'') <> ''string''\n         or pg_catalog.btrim(device_record ->> ''room'') !~ ''^[a-zA-Z0-9]{1,8}$''\n       ) then\n      raise exception ''Room must contain up to 8 letters or digits'';\n    end if;\n  end loop;\n\n  first_device := p_devices -> 0;';
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

  if pg_catalog.strpos(function_definition, old_validation) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_validation,
      new_validation
    );
  elsif pg_catalog.strpos(function_definition, 'Room must contain up to 8 letters or digits') = 0 then
    raise exception 'Could not add floor and room validation to create_fix_request.';
  end if;

  execute function_definition;
end;
$$;
