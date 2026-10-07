alter table public."Users"
  add column if not exists password text;

alter table public."Users"
  alter column password drop not null;
