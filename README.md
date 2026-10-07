# mobileproject

A new Flutter project.

## Supabase setup

Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in `.env`, then run the app
normally:

```sh
flutter run
```

`connect.dart` loads `.env` at startup and initializes the Supabase client. The
Flutter `.env` is bundled with the app, so it must contain only `SUPABASE_URL`
and a publishable/anon key. Keep database passwords and Supabase secret keys in
`.env.server` or another server-only secret store; never bundle them with the
client app. Protect tables with Supabase Row Level Security (RLS) policies.
At startup, the app checks the Supabase Auth health endpoint and displays a
retry page if the connection check fails.

## Registration and roles

The registration screen asks for first and last name, Thai national ID,
username, password, and role. National IDs must be exactly 13 ASCII digits;
there is no checksum validation. IDs are stored only as a keyed HMAC-SHA-256
digest in `public."Users".realid`; the raw ID is not stored or returned by the
Edge Function. Passwords must be 8-128
characters and include lowercase, uppercase, numeric, and symbol characters.
Registration does not create a Supabase Auth user. Passwords are PBKDF2-SHA-256
hashed in the `register-user` Edge Function and the encoded hash is stored in
`public."Users".password`; plaintext is never stored. The `login-user` Edge
Function verifies the password hash and issues an 8-hour signed temporary
session, held in app memory. Profile edits and password changes require the
same national ID entered at registration. Password changes are optional in the
profile edit form. A legacy plaintext password is replaced with a PBKDF2 hash
immediately after a successful login.

National IDs are highly sensitive personal data. Use this feature only with a
clear purpose and appropriate notice/consent, access controls, retention
limits, and incident procedures under applicable privacy law. A keyed HMAC
supports equality checks but does not verify identity against a government
source. Keep `REALID_HMAC_SECRET` private and stable; changing it prevents
existing IDs from matching. Existing accounts without a stored digest cannot
edit their profiles and must register a new account, as the app does not
silently enroll an unverified ID for an existing account.

Email collection, display, sign-in, and change-verification flows have been
removed from the app. Existing Supabase Auth accounts are not migrated to the
temporary username/password system. The migration removes
`public."Users".email` and pending email-change requests but does not delete
Supabase Auth users or other historical records automatically.

Apply the SQL migrations in `supabase/migrations`, then deploy the
`supabase/functions/register-user`, `supabase/functions/login-user`, and
`supabase/functions/update-user-profile` and
`supabase/functions/profile-avatar` Edge Functions and set their
`SUPABASE_SERVICE_ROLE_KEY` and `REALID_HMAC_SECRET` secrets before using
registration or profile edits. The registration
function inserts the account details directly into `public."Users"`; `id` is
assigned as a random, unique 10-digit bigint. Migration
`20261006000002_fix_existing_users_identity.sql` repairs older tables by
adding an auto-generated `id` and allowing a legacy `password` column to be
nullable. **Temporary development setting:** public registration currently
permits anyone to select `User`,
`Admin`, or `SuperAdmin`. Anyone can grant themselves elevated access while
this is enabled. Restore server-side SuperAdmin authorization before production.
Never grant roles from `user_metadata` or expose the service role key in the
Flutter app.
User and Admin profile photos are stored in private Storage buckets named for
the account UID. The `profile-avatar` Edge Function creates a bucket on the
first upload, replaces the previous `avatar` image on later uploads, and limits
images to 5 MB. The app uses a signed URL to display the current image.
The registration and sign-in functions use the configured per-IP rate limit.
Gateway JWT verification is disabled so signed-out clients can call them; the
login function issues its own signed temporary session token. Any future API
that accepts this token must verify its signature and enforce permissions on
the server. Client-side role state alone is not authorization, and Supabase RLS
does not recognize this custom session as a Supabase Auth session.
Migration `20261006000004_enforce_unique_usernames.sql` prevents new duplicate
usernames, ignoring case and surrounding whitespace. Existing duplicate rows
are not changed, and their username cannot be registered again. Temporary
login can resolve an existing duplicate username only when exactly one row has
a matching PBKDF2 password hash; otherwise it asks the user to contact an
administrator.
Migration `20261008000000_users_ten_digit_ids.sql` configures new user IDs to
use the 10-digit range. Migration
`20261008000001_users_random_ten_digit_ids.sql` assigns a random unused ID to
each new account; IDs already assigned to existing users are not changed.

To deploy to the same Supabase project configured in `.env`, install the
Supabase CLI, authenticate with `supabase login`, and run:

```sh
supabase link --project-ref <project-ref>
supabase db push
supabase functions deploy register-user
supabase functions deploy login-user
supabase functions deploy update-user-profile
supabase functions deploy profile-avatar
```

Set `SUPABASE_SERVICE_ROLE_KEY` for the Edge Function from the Supabase
Dashboard's Edge Function secrets settings. Do not put this key in `.env` or
the Flutter app. Generate a separate random secret of at least 32 characters
and add it as the `REALID_HMAC_SECRET` Edge Function secret. Keep a secure
backup and do not rotate it without a planned re-hash process. Remove the
obsolete `RESEND_API_KEY` and `EMAIL_FROM` secrets from the Supabase Dashboard.
If the old
`change-account-email` Edge Function is deployed, delete it from the project's
Edge Functions dashboard. Migration
`20261008000003_realid_and_remove_email.sql` removes the email-change table and
the `Users.email` column, and adds unique HMAC storage for new citizen IDs.
Confirm the linked project ref matches the host in
`SUPABASE_URL`. If the function endpoint responds with `404 Not Found`, the
function has not been deployed to that project (or the project ref is wrong);
deploy it before retrying registration.

## App navigation and roles

The shared navigation displays role-specific menu items for `Unsign` (not
signed in), `User`, `Technician`, `Admin`, and `SuperAdmin`. New accounts
receive their role from the login Edge Function and keep the signed session
in memory until sign-out, app restart, or its 8-hour expiry. Existing Supabase
Auth accounts are not supported by the username/password login flow.

The account button signs in through the temporary username/password endpoint.
At this stage, the role-specific page content is still placeholder UI. Database
operations protected by Supabase RLS are not available to temporary sessions;
future data operations need server-side Edge Function endpoints that verify
the signed temporary session and authorize each role.
The centered
`KUFixIT` text in the app bar is a placeholder for the web logo. The public
ticket monitor page is in `lib/gui/tickerMonitor.dart`.

Access the initialized client with `SupabaseConnection.client`, for example:

```dart
final rows = await SupabaseConnection.client.from('your_table').select();
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
