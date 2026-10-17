do $$
declare
  technician_table record;
  has_legacy_ticket_id boolean;
  has_ticket_id boolean;
begin
  for technician_table in
    select relation.relname
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as schema
      on schema.oid = relation.relnamespace
    where schema.nspname = 'public'
      and relation.relkind = 'r'
      and relation.relname ~ '^t_[0-9]{10}$'
  loop
    select exists (
      select 1
      from pg_catalog.pg_attribute as attribute
      where attribute.attrelid = pg_catalog.to_regclass(
        pg_catalog.format('public.%I', technician_table.relname)
      )
        and attribute.attname = 'ticket_id'
        and not attribute.attisdropped
    )
    into has_legacy_ticket_id;

    select exists (
      select 1
      from pg_catalog.pg_attribute as attribute
      where attribute.attrelid = pg_catalog.to_regclass(
        pg_catalog.format('public.%I', technician_table.relname)
      )
        and attribute.attname = 'ticketId'
        and not attribute.attisdropped
    )
    into has_ticket_id;

    if has_legacy_ticket_id then
      if has_ticket_id then
        execute pg_catalog.format(
          'alter table public.%I drop column "ticketId"',
          technician_table.relname
        );
      end if;

      execute pg_catalog.format(
        'alter table public.%I
         drop column if exists assigned_at,
         drop column if exists status,
         drop column if exists report,
         drop column if exists result,
         drop column if exists bucket',
        technician_table.relname
      );
      execute pg_catalog.format(
        'alter table public.%I rename column ticket_id to "ticketId"',
        technician_table.relname
      );
    elsif has_ticket_id then
      execute pg_catalog.format(
        'alter table public.%I
         drop column if exists assigned_at,
         drop column if exists status,
         drop column if exists report,
         drop column if exists result,
         drop column if exists bucket',
        technician_table.relname
      );
    else
      raise exception 'Technician table % has no ticket ID column.',
        technician_table.relname;
    end if;
  end loop;
end;
$$;

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

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;
