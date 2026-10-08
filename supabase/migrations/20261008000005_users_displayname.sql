alter table public."Users"
  add column if not exists displayname text;

update public."Users"
set displayname = username
where displayname is null;

alter table public."Users"
  alter column displayname set not null;
