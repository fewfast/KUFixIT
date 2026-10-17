create temporary table users_uid_migration (
  previous_uid text primary key,
  new_uid text unique
);

insert into users_uid_migration (previous_uid, new_uid)
select
  uid::text,
  case when uid::text ~ '^u_[0-9]{10}$' then uid::text end
from public."Users";

do $$
declare
  old_uid_value text;
  candidate_uid text;
begin
  perform pg_catalog.pg_advisory_xact_lock(192837465, 564738291);

  for old_uid_value in
    select old_uid.previous_uid
    from users_uid_migration as old_uid
    where old_uid.new_uid is null
  loop
    loop
      candidate_uid := 'u_' || (
        1000000000 +
        pg_catalog.floor(pg_catalog.random() * 9000000000)::bigint
      )::text;
      exit when not exists (
        select 1
        from users_uid_migration as mapping
        where mapping.new_uid = candidate_uid
      ) and not exists (
        select 1
        from public."Users" as account
        where account.uid::text = candidate_uid
      );
    end loop;

    update users_uid_migration
    set new_uid = candidate_uid
    where users_uid_migration.previous_uid = old_uid_value;
  end loop;
end;
$$;

alter table public."FixList"
  drop constraint if exists "FixList_requester_check",
  drop constraint if exists fixlist_requester_uid_format;

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

update public."FixList" as ticket
set requester = mapping.new_uid
from users_uid_migration as mapping
where ticket.requester = mapping.previous_uid
  and ticket.requester <> mapping.new_uid;

update public."Users" as account
set uid = mapping.new_uid
from users_uid_migration as mapping
where account.uid::text = mapping.previous_uid
  and mapping.previous_uid <> mapping.new_uid;

create or replace function public.assign_prefixed_user_uid()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(192837465, 564738291);

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

drop trigger if exists assign_prefixed_user_uid on public."Users";

create trigger assign_prefixed_user_uid
before insert on public."Users"
for each row
execute function public.assign_prefixed_user_uid();

create unique index if not exists users_uid_key
  on public."Users" (uid);

alter table public."Users"
  add constraint users_uid_prefixed_ten_digits
  check (uid ~ '^u_[0-9]{10}$');

alter table public."FixList"
  add constraint fixlist_requester_uid_format
  check (
    requester is null
    or requester ~ '^[0-9]{10}$'
    or requester ~ '^u_[0-9]{10}$'
    or requester ~ '^u_[0-9a-f]{32}$'
  );

do $migration$
declare
  function_definition text;
  legacy_numeric_pattern constant text := '''^[0-9]{10}$''';
  legacy_uuid_pattern constant text :=
    '''^(u_[0-9a-f]{32}|[0-9]{10})$''';
  numeric_user_pattern constant text :=
    '''^(u_[0-9]{10}|u_[0-9a-f]{32}|[0-9]{10})$''';
  function_signature constant text :=
    'public.create_fix_request(text,text,text,double precision,double precision,jsonb)';
begin
  function_definition := pg_catalog.pg_get_functiondef(
    function_signature::pg_catalog.regprocedure
  );

  if pg_catalog.strpos(function_definition, legacy_numeric_pattern) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      legacy_numeric_pattern,
      numeric_user_pattern
    );
    execute function_definition;
  elsif pg_catalog.strpos(function_definition, legacy_uuid_pattern) > 0 then
    function_definition := pg_catalog.replace(
      function_definition,
      legacy_uuid_pattern,
      numeric_user_pattern
    );
    execute function_definition;
  elsif pg_catalog.strpos(function_definition, numeric_user_pattern) = 0 then
    raise exception 'Could not update create_fix_request UID validation.';
  end if;
end;
$migration$;

create temporary table profile_avatar_bucket_uid_migration as
select
  account.google_auth_user_id::text as previous_bucket_id,
  account.uid::text as new_bucket_id
from public."Users" as account
where account.google_auth_user_id is not null;

do $$
begin
  if exists (
    select 1
    from profile_avatar_bucket_uid_migration as mapping
    join storage.objects as old_object
      on old_object.bucket_id = mapping.previous_bucket_id
    join storage.objects as new_object
      on new_object.bucket_id = mapping.new_bucket_id
     and new_object.name = old_object.name
    where mapping.previous_bucket_id <> mapping.new_bucket_id
  ) then
    raise exception
      'Cannot migrate profile avatar buckets: old and new buckets contain objects with the same name.';
  end if;
end;
$$;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
select
  account.uid,
  account.uid,
  false,
  2097152,
  array['image/gif', 'image/jpeg', 'image/png', 'image/webp']
from public."Users" as account
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop table profile_avatar_bucket_uid_migration;
drop table users_uid_migration;

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;
