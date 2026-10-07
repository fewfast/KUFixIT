drop table if exists public.email_change_requests;

alter table public."Users"
  drop column if exists email,
  add column if not exists realid text
    check (realid is null or realid ~ '^[a-f0-9]{64}$');

create unique index if not exists users_realid_unique
  on public."Users" (realid)
  where realid is not null;
