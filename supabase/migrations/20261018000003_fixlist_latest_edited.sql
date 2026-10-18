alter table public."FixList"
  add column if not exists latest_edited timestamptz not null default pg_catalog.now();

create or replace function public.set_fixlist_latest_edited()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.latest_edited := pg_catalog.now();
  return new;
end;
$$;

drop trigger if exists fixlist_set_latest_edited on public."FixList";
create trigger fixlist_set_latest_edited
  before update on public."FixList"
  for each row
  execute function public.set_fixlist_latest_edited();
