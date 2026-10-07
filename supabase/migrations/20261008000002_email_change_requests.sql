create table if not exists public.email_change_requests (
  id uuid primary key default gen_random_uuid(),
  account_type text not null check (account_type in ('temporary', 'supabase_auth')),
  account_id text not null,
  old_email text,
  new_email text not null,
  stage text not null check (stage in ('pending_old', 'pending_new')),
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  unique (account_type, account_id)
);

alter table public.email_change_requests enable row level security;
revoke all on table public.email_change_requests from anon, authenticated;
grant all on table public.email_change_requests to service_role;
