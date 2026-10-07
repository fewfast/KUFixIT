create table if not exists public.registration_rate_limits (
  ip_hash text primary key,
  attempts integer not null default 0 check (attempts >= 0),
  window_started_at timestamptz not null default now()
);

alter table public.registration_rate_limits enable row level security;
revoke all on table public.registration_rate_limits from anon, authenticated;
grant all on table public.registration_rate_limits to service_role;

create or replace function public.consume_registration_rate_limit(
  p_ip_hash text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_attempts integer;
begin
  if p_ip_hash is null or p_limit < 1 or p_window_seconds < 1 then
    raise exception 'Invalid rate limit parameters';
  end if;

  delete from public.registration_rate_limits
  where window_started_at <= now() - make_interval(secs => p_window_seconds * 2);

  insert into public.registration_rate_limits as limits (
    ip_hash,
    attempts,
    window_started_at
  )
  values (p_ip_hash, 1, now())
  on conflict (ip_hash) do update
  set
    attempts = case
      when limits.window_started_at <= now() - make_interval(secs => p_window_seconds)
        then 1
      else limits.attempts + 1
    end,
    window_started_at = case
      when limits.window_started_at <= now() - make_interval(secs => p_window_seconds)
        then now()
      else limits.window_started_at
    end
  returning attempts into current_attempts;

  return current_attempts <= p_limit;
end;
$$;

revoke all on function public.consume_registration_rate_limit(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_registration_rate_limit(text, integer, integer)
  to service_role;
