create temporary table users_uid_migration (
  previous_uid text primary key,
  new_uid text unique
);

insert into users_uid_migration (previous_uid)
select uid::text
from public."Users";

do $$
declare
  user_uid text;
  candidate_uid text;
begin
  perform pg_catalog.pg_advisory_xact_lock(192837465, 564738291);

  for user_uid in
    select previous_uid from users_uid_migration
  loop
    loop
      candidate_uid := 'u_' || (
        1000000000 +
        pg_catalog.floor(pg_catalog.random() * 9000000000)::bigint
      )::text;
      exit when not exists (
        select 1
        from users_uid_migration
        where new_uid = candidate_uid
      );
    end loop;

    update users_uid_migration
    set new_uid = candidate_uid
    where previous_uid = user_uid;
  end loop;
end;
$$;

alter table public."FixList"
  drop constraint if exists "FixList_requester_check",
  drop constraint if exists fixlist_requester_uid_format;

update public."FixList" as ticket
set requester = migration.new_uid
from users_uid_migration as migration
where ticket.requester = migration.previous_uid;

do $$
declare
  check_name text;
begin
  for check_name in
    select constraint_row.conname
    from pg_catalog.pg_constraint as constraint_row
    where constraint_row.conrelid = 'public."Users"'::pg_catalog.regclass
      and constraint_row.contype = 'c'
      and pg_catalog.strpos(
        pg_catalog.pg_get_constraintdef(constraint_row.oid),
        'uid'
      ) > 0
  loop
    execute pg_catalog.format(
      'alter table public."Users" drop constraint %I',
      check_name
    );
  end loop;
end;
$$;

drop trigger if exists assign_random_ten_digit_uid on public."Users";
drop function if exists public.assign_random_ten_digit_uid();

alter table public."Users"
  alter column uid type text using uid::text;

update public."Users" as account
set uid = migration.new_uid
from users_uid_migration as migration
where account.uid = migration.previous_uid;

create function public.assign_prefixed_user_uid()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  loop
    new.uid := 'u_' || (
      1000000000 +
      pg_catalog.floor(pg_catalog.random() * 9000000000)::bigint
    )::text;
    exit when not exists (
      select 1
      from public."Users" as existing
      where existing.uid = new.uid
    );
  end loop;
  return new;
end;
$$;

revoke all on function public.assign_prefixed_user_uid()
  from public, anon, authenticated;

create trigger assign_prefixed_user_uid
before insert on public."Users"
for each row
execute function public.assign_prefixed_user_uid();

alter table public."Users"
  add constraint users_uid_prefixed_ten_digits
  check (uid ~ '^u_[0-9]{10}$');

alter table public."FixList"
  add constraint fixlist_requester_uid_format
    check (
      requester is null
      or requester ~ '^[0-9]{10}$'
      or requester ~ '^u_[0-9]{10}$'
    );

do $migration$
declare
  function_definition text;
  old_uid_check constant text := $$'^[0-9]{10}$'$$;
  new_uid_check constant text := $$'^(u_[0-9]{10}|[0-9]{10})$'$$;
begin
  function_definition := pg_catalog.pg_get_functiondef(
    'public.create_fix_request(text,text,text,double precision,double precision,jsonb)'
      ::pg_catalog.regprocedure
  );
  if pg_catalog.strpos(function_definition, old_uid_check) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      old_uid_check,
      new_uid_check
    );
    execute function_definition;
  elsif pg_catalog.strpos(function_definition, new_uid_check) = 0 then
    raise exception
      'Could not update create_fix_request requester UID validation.';
  end if;
end;
$migration$;

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;

drop table users_uid_migration;
