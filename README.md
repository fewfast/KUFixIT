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

Registration and sign-in use Google OAuth through Supabase Auth. Registration
shows only the Google sign-in action; after Google authentication succeeds,
the app automatically creates the KUFixIT account. The Google profile name is
stored as both `"Display Name"` and `displayname`, `created_at` is assigned by
the database, and every account is assigned the `User` role. A generated username is stored for compatibility with the
app. Each Google Auth user ID can register one KUFixIT account. The
`register-user` and `login-user` Edge Functions verify the Google-authenticated
Supabase session and issue an 8-hour signed temporary session, held in app
memory.

Technicians and elevated staff use the separate username/password action in
the login dialog. Migration `20261008000010_systems_users_login.sql` creates
`public."Systems_Users"` with `"Username"`, bcrypt-hashed `"Password"`, `role`,
`created_at`, and optional `endtime`. Allowed staff roles are `Technician`,
`Admin`, and `SuperAdmin`; a null `endtime` means the account does not expire.
Staff login sessions expire at the earlier of the normal 8-hour session limit
or the account's `endtime`. The Edge Function verifies the hash in a protected
database function and never returns the password hash.

Create staff accounts only through a trusted administrative SQL session. For
example, replace the username and password below with the new account values;
the database stores only the bcrypt hash:

```sql
insert into public."Systems_Users" (
  "Username", "Password", role, endtime
)
values (
  'technician1',
  extensions.crypt('REPLACE_WITH_A_STRONG_PASSWORD', extensions.gen_salt('bf', 12)),
  'Technician',
  null
);
```

Never grant staff roles from public registration or expose the service role
key in the Flutter app.

Before using Google sign-in, enable Google as a provider in Supabase Auth and
configure its Google OAuth client credentials. Add
`io.supabase.flutter://login-callback/` to the Supabase Auth redirect URL
allowlist for Android and iOS. For Flutter Web, add the app's origin (for local
development, for example, `http://localhost:3000`) to the Supabase Auth
redirect URL allowlist; the app redirects back to the origin where it is
running. Keep the web app running on that address while completing sign-in.
Use the Supabase Auth callback URL shown in the dashboard as an authorized
redirect URI in the Google OAuth client.
If sign-in returns `Unsupported provider: provider is not enabled`, Google is
not enabled in the Supabase project's Authentication > Sign In / Providers
settings, or the provider credentials have not been configured.

The account row stores `created_at`, `"Display Name"`, `role`, `status`, and
`google_auth_user_id`. New registrations default to `status = 'active'`;
existing accounts are backfilled as active. A separate `uid` is generated as
a unique 10-digit number for each account; Google Auth UUID remains the
authentication identity. The register and login responses include this `uid`
and `status`. Existing username/password accounts are not
linked to Google automatically; remove old rows manually before their users
register again. Public registration always assigns `User`; elevated roles
must be granted through a trusted administrative process. Never grant roles
from `user_metadata` or expose the service role key in the Flutter app.

Migration `20261008000008_sync_google_auth_users.sql` creates `Users` rows
directly from verified Google Auth users, backfills Google users that already
exist, removes legacy `Users` triggers that referenced columns absent from the
current table, and installs a database trigger for future Google registrations.
Migration `20261008000009_users_unique_ten_digit_uid.sql` adds and backfills the
unique 10-digit `uid` and generates one for every new account.
Migration `20261008000011_users_status.sql` adds the `status` column, marks
existing accounts active, and keeps new Google registrations active.

Profile photos are stored in private Storage buckets named for the account
Google Auth UID. The `profile-avatar` Edge Function creates a bucket on first
upload, replaces the previous `avatar` image on later uploads, and limits
images to 5 MB. The app uses a signed URL to display the current image.
Google registration, sign-in, and profile updates do not use the
application-level per-IP rate limit. Migration
`20261008000007_remove_rate_limit.sql` removes the shared counter table and
database function.
Gateway JWT verification is disabled so clients can reach the functions.
Google account functions verify the Google Supabase Auth token; `staff-login`
checks credentials via the restricted database function. Both login flows
issue signed temporary session tokens. Any future API that accepts these
tokens must verify their signature and enforce permissions on the server.
Client-side role state alone is not authorization, and Supabase RLS does not
recognize this custom session as a Supabase Auth session.

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

Supabase injects its server-side secret API key into Edge Functions as
`SUPABASE_SECRET_KEYS`; the functions read its `default` key automatically.
Do not add a `SUPABASE_*` secret manually or put a server-side key in `.env` or
the Flutter app. Remove obsolete `RESEND_API_KEY` and `EMAIL_FROM` secrets
from the Supabase Dashboard. If the old `change-account-email` Edge Function
is deployed, delete it from the project's Edge Functions dashboard.
Confirm the linked project ref matches the host in
`SUPABASE_URL`. If the function endpoint responds with `404 Not Found`, the
function has not been deployed to that project (or the project ref is wrong);
deploy it before retrying registration.

## App navigation and roles

The shared navigation displays role-specific menu items for `Unsign` (not
signed in), `User`, `Technician`, `Admin`, and `SuperAdmin`. New accounts
receive the `User` role and an 8-hour signed temporary session. Supabase Auth
keeps the Google session so the app can issue a new temporary session on a
later launch.

The account button signs in through Google OAuth.
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
