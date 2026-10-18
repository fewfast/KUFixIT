create or replace function public.prevent_cancelled_fixlist_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'cancel' then
    raise exception 'Cancelled repair requests cannot be edited.';
  end if;
  return new;
end;
$$;

drop trigger if exists fixlist_prevent_cancelled_update on public."FixList";
create trigger fixlist_prevent_cancelled_update
  before update on public."FixList"
  for each row
  execute function public.prevent_cancelled_fixlist_update();
