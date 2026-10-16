do $$
begin
  if exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = 'public."FixList"'::pg_catalog.regclass
      and attname = 'fix_history_time'
      and not attisdropped
  ) and not exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = 'public."FixList"'::pg_catalog.regclass
      and attname = 'fix_history_time_start'
      and not attisdropped
  ) then
    alter table public."FixList"
      rename column fix_history_time to fix_history_time_start;
  elsif exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = 'public."FixList"'::pg_catalog.regclass
      and attname = 'fix_history_time'
      and not attisdropped
  ) and exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = 'public."FixList"'::pg_catalog.regclass
      and attname = 'fix_history_time_start'
      and not attisdropped
  ) then
    update public."FixList"
    set fix_history_time_start = coalesce(
      fix_history_time_start,
      fix_history_time
    );
    alter table public."FixList" drop column fix_history_time;
  end if;
end;
$$;

alter table public."FixList"
  add column if not exists fix_history_time_start timestamptz[] default null,
  add column if not exists fix_history_time_end timestamptz[] default null;

select pg_catalog.pg_notify('pgrst', 'reload schema');
