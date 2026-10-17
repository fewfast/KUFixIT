do $$
begin
  if exists (
    select 1
    from public."Maintenance_Users"
    group by pg_catalog.lower(pg_catalog.btrim("teamName"))
    having pg_catalog.count(*) > 1
  ) then
    raise exception
      'Duplicate technician display names exist. Rename duplicates before enforcing uniqueness.';
  end if;
end;
$$;

create unique index maintenance_users_display_name_key
  on public."Maintenance_Users" (
    pg_catalog.lower(pg_catalog.btrim("teamName"))
  );
