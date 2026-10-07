create or replace function public.assign_random_ten_digit_user_id()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate_id bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(192837465, 564738291);

  loop
    candidate_id :=
      1000000000 + pg_catalog.floor(pg_catalog.random() * 9000000000)::bigint;

    if not exists (
      select 1
      from public."Users" existing
      where existing.id = candidate_id
    ) then
      new.id := candidate_id;
      return new;
    end if;
  end loop;
end;
$$;

revoke all on function public.assign_random_ten_digit_user_id()
  from public, anon, authenticated;

drop trigger if exists assign_random_ten_digit_user_id on public."Users";

create trigger assign_random_ten_digit_user_id
before insert on public."Users"
for each row
execute function public.assign_random_ten_digit_user_id();
