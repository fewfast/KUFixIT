alter table public."Maintenance_Users"
  add column if not exists status boolean not null default true;
