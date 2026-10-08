alter table public."Users"
  add column if not exists "Display Name" text,
  add column if not exists displayname text,
  add column if not exists username text;

update public."Users"
set username = coalesce(
  nullif(pg_catalog.btrim(username), ''),
  'u_' || pg_catalog.substr(
    pg_catalog.md5(coalesce(google_auth_user_id::text, pg_catalog.gen_random_uuid()::text)),
    1,
    28
  )
)
where username is null or pg_catalog.btrim(username) = '';

update public."Users"
set
  "Display Name" = coalesce(
    nullif(pg_catalog.btrim("Display Name"), ''),
    nullif(pg_catalog.btrim(displayname), ''),
    username
  ),
  displayname = coalesce(
    nullif(pg_catalog.btrim(displayname), ''),
    nullif(pg_catalog.btrim("Display Name"), ''),
    username
  )
where "Display Name" is null
  or pg_catalog.btrim("Display Name") = ''
  or displayname is null
  or pg_catalog.btrim(displayname) = '';

alter table public."Users"
  alter column "Display Name" set not null,
  alter column displayname set not null,
  alter column username set not null;

create unique index if not exists users_username_unique
  on public."Users" (username);
