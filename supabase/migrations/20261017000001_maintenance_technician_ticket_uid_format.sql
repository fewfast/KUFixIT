create or replace function public.create_technician_ticket_table(p_uid text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_uid is null or p_uid !~ '^t_[0-9]{10}$' then
    raise exception 'Invalid technician UID.';
  end if;

  execute pg_catalog.format(
    'create table if not exists public.%I (
      "ticketId" text primary key
        references public."FixList" ("TicketId") on delete cascade
    )',
    p_uid
  );
  execute pg_catalog.format(
    'alter table public.%I enable row level security',
    p_uid
  );
  execute pg_catalog.format(
    'revoke all on table public.%I from public, anon, authenticated',
    p_uid
  );
  execute pg_catalog.format(
    'grant select, insert, update, delete on table public.%I to service_role',
    p_uid
  );
end;
$$;

revoke all on function public.create_technician_ticket_table(text)
  from public, anon, authenticated;
grant execute on function public.create_technician_ticket_table(text)
  to service_role;
