-- The Realtime SDK changes its socket JWT from anon to authenticated on
-- Google sign-in. Keep the private invalidation topic family readable for
-- either role while denying client broadcast publishing.
drop policy if exists kufixit_receive_invalidation
  on realtime.messages;

create policy kufixit_receive_invalidation
  on realtime.messages
  for select
  to anon, authenticated
  using (
    realtime.topic() in (
      'kufixit:invalidate',
      'kufixit:invalidate:accounts',
      'kufixit:invalidate:tickets',
      'kufixit:invalidate:technicians',
      'kufixit:invalidate:reports',
      'kufixit:invalidate:storage'
    )
  );

-- No INSERT policy exists. Revoke the table privilege as an explicit guard
-- against clients publishing broadcasts; server-side trigger sends continue
-- through the security-definer database function.
revoke insert on table realtime.messages from anon, authenticated;
