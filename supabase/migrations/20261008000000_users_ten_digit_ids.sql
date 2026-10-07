do $$
declare
  id_sequence regclass;
  max_id bigint;
  first_id bigint;
begin
  lock table public."Users" in access exclusive mode;

  id_sequence := pg_get_serial_sequence('public."Users"', 'id')::regclass;
  if id_sequence is null then
    raise exception 'public."Users".id must have an identity or serial sequence';
  end if;

  select coalesce(max(id), 0)
    into max_id
    from public."Users";

  if max_id >= 9999999999 then
    raise exception 'Cannot generate a unique 10-digit user id because the id range is exhausted';
  end if;

  first_id := greatest(1000000000, max_id + 1);

  execute format(
    'alter sequence %s maxvalue 9999999999 no cycle',
    id_sequence
  );
  perform setval(id_sequence, first_id, false);
end;
$$;
