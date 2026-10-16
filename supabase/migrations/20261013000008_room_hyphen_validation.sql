do $$
declare
  function_definition text;
  old_room_pattern constant text := E'^[a-zA-Z0-9]{1,8}$';
  new_room_pattern constant text := E'^[a-zA-Z0-9-]{1,8}$';
  old_error_message constant text :=
    'Room must contain up to 8 letters or digits';
  new_error_message constant text :=
    'Room must contain up to 8 letters, digits, or hyphens';
begin
  function_definition := pg_catalog.pg_get_functiondef(
    'public.create_fix_request(text,text,text,double precision,double precision,jsonb)'
      ::pg_catalog.regprocedure
  );

  if pg_catalog.strpos(function_definition, old_room_pattern) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_room_pattern,
      new_room_pattern
    );
  elsif pg_catalog.strpos(function_definition, new_room_pattern) = 0 then
    raise exception 'Could not allow hyphens in room validation.';
  end if;

  if pg_catalog.strpos(function_definition, old_error_message) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_error_message,
      new_error_message
    );
  elsif pg_catalog.strpos(function_definition, new_error_message) = 0 then
    raise exception 'Could not update the room validation error message.';
  end if;

  execute function_definition;
end;
$$;
