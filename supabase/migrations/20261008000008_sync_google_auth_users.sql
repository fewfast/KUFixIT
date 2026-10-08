create or replace function public.sync_google_auth_user_to_users()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  provider text;
  email_address text;
  account_display_name text;
begin
  provider := new.raw_app_meta_data ->> 'provider';
  if provider is distinct from 'google' and not exists (
    select 1
    from auth.identities
    where user_id = new.id
      and auth.identities.provider = 'google'
  ) then
    return new;
  end if;

  email_address := pg_catalog.lower(pg_catalog.btrim(coalesce(new.email, '')));
  account_display_name := coalesce(
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'given_name'), ''),
    nullif(pg_catalog.split_part(email_address, '@', 1), ''),
    'Google User'
  );
  insert into public."Users" (
    google_auth_user_id,
    "Display Name",
    role,
    created_at
  )
  values (
    new.id,
    account_display_name,
    'User',
    new.created_at
  )
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists enforce_unique_users_username on public."Users";
drop trigger if exists assign_random_ten_digit_user_id on public."Users";

drop trigger if exists on_google_auth_user_created on auth.users;
create trigger on_google_auth_user_created
  after insert on auth.users
  for each row
  execute function public.sync_google_auth_user_to_users();

insert into public."Users" (
  google_auth_user_id,
  "Display Name",
  role,
  created_at
)
select
  auth_user.id,
  coalesce(
    nullif(pg_catalog.btrim(auth_user.raw_user_meta_data ->> 'full_name'), ''),
    nullif(pg_catalog.btrim(auth_user.raw_user_meta_data ->> 'name'), ''),
    nullif(pg_catalog.btrim(auth_user.raw_user_meta_data ->> 'display_name'), ''),
    nullif(pg_catalog.btrim(auth_user.raw_user_meta_data ->> 'given_name'), ''),
    nullif(
      pg_catalog.split_part(
        pg_catalog.lower(pg_catalog.btrim(coalesce(auth_user.email, ''))),
        '@',
        1
      ),
      ''
    ),
    'Google User'
  ),
  'User',
  auth_user.created_at
from auth.users as auth_user
where auth_user.raw_app_meta_data ->> 'provider' = 'google'
   or exists (
     select 1
     from auth.identities
     where user_id = auth_user.id
       and auth.identities.provider = 'google'
   )
on conflict do nothing;
