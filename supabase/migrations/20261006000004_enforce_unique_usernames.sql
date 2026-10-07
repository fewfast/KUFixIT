create or replace function public.enforce_unique_users_username()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_username text;
  username_exists boolean;
begin
  normalized_username := pg_catalog.lower(pg_catalog.btrim(new.username));

  if tg_op = 'UPDATE'
    and normalized_username = pg_catalog.lower(pg_catalog.btrim(old.username))
  then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(normalized_username, 0)
  );

  if tg_op = 'UPDATE' then
    select exists (
      select 1
      from public."Users" existing
      where pg_catalog.lower(pg_catalog.btrim(existing.username)) = normalized_username
        and existing.id <> old.id
    ) into username_exists;
  else
    select exists (
      select 1
      from public."Users" existing
      where pg_catalog.lower(pg_catalog.btrim(existing.username)) = normalized_username
    ) into username_exists;
  end if;

  if username_exists then
    raise exception using
      errcode = '23505',
      message = 'Username is already registered',
      constraint = 'users_username_normalized_uidx';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_unique_users_username() from public, anon, authenticated;

drop trigger if exists enforce_unique_users_username on public."Users";

create trigger enforce_unique_users_username
before insert or update on public."Users"
for each row
execute function public.enforce_unique_users_username();
