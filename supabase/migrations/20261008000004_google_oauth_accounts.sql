alter table public."Users"
  drop column if exists password,
  add column if not exists google_auth_user_id uuid
    references auth.users (id) on delete cascade,
  add column if not exists email text;

create unique index if not exists users_google_auth_user_id_unique
  on public."Users" (google_auth_user_id)
  where google_auth_user_id is not null;

create unique index if not exists users_email_normalized_unique
  on public."Users" (pg_catalog.lower(pg_catalog.btrim(email)))
  where email is not null;
