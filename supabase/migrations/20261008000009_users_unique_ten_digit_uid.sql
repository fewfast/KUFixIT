alter table public."Users"
  add column if not exists uid bigint;

alter table public."Users"
  alter column uid type bigint using uid::bigint;

create or replace function public.assign_random_ten_digit_uid()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate_uid bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(192837465, 564738291);

  loop
    candidate_uid :=
      1000000000 + pg_catalog.floor(pg_catalog.random() * 9000000000)::bigint;

    if not exists (
      select 1
      from public."Users" existing
      where existing.uid = candidate_uid
    ) then
      new.uid := candidate_uid;
      return new;
    end if;
  end loop;
end;
$$;

revoke all on function public.assign_random_ten_digit_uid()
  from public, anon, authenticated;

drop trigger if exists assign_random_ten_digit_uid on public."Users";

create trigger assign_random_ten_digit_uid
before insert on public."Users"
for each row
execute function public.assign_random_ten_digit_uid();

do $$
declare
  user_row record;
  candidate_uid bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(192837465, 564738291);

  for user_row in
    select ctid
    from (
      select
        ctid,
        uid,
        pg_catalog.row_number() over (partition by uid order by ctid) as duplicate_number
      from public."Users"
    ) existing_users
    where uid is null
       or uid < 1000000000
       or uid > 9999999999
       or duplicate_number > 1
  loop
    loop
      candidate_uid :=
        1000000000 + pg_catalog.floor(pg_catalog.random() * 9000000000)::bigint;

      if not exists (
        select 1
        from public."Users" existing
        where existing.uid = candidate_uid
      ) then
        update public."Users"
        set uid = candidate_uid
        where ctid = user_row.ctid;
        exit;
      end if;
    end loop;
  end loop;
end;
$$;

create unique index users_uid_key
  on public."Users" (uid);

alter table public."Users"
  alter column uid set not null;

alter table public."Users"
  add constraint users_uid_ten_digits
  check (uid between 1000000000 and 9999999999);
