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

## Realtime refresh

The app uses a private Supabase Broadcast channel for invalidation-only
updates. Database triggers publish a constant marker, never ticket, user, or
other row data. The Flutter pages then reload through their existing
authorization-checked Edge Functions; Realtime does not grant access to app
data. Migration `20261019000001_realtime_invalidation.sql` adds the `anon`
select policy for this single private topic and statement-level triggers for
the app tables, ticket tables, technician assignment tables, and Storage
objects. Newly added tables or dynamic table-creation functions must also
install the invalidation trigger.

The `anon` role can subscribe to this one private topic with the app's public
key. It can observe only that a database change occurred and when; the
broadcast contains no row data, and the policy does not grant permission to
publish or access application tables.

Apply the migration before expecting cross-client updates. It has not been
applied to the remote project. The current local migration history has
conflicting/unreconciled versions, so inspect and reconcile that history before
using `supabase db push`; do not push the pending migration set blindly.

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

The technician manager uses the `maintenance-teams` Edge Function and the
`20261016000000_maintenance_teams.sql`,
`20261016000001_maintenance_users_team_ids.sql`, and
`20261016000002_maintenance_legacy_time_nullable.sql`,
`20261016000003_users_prefixed_uids.sql`, and
`20261016000004_maintenance_technician_uids.sql` migrations. The
`20261017000000_maintenance_user_profiles_and_date_windows.sql` migration adds
technician comments and date-based login windows;
`20261017000001_maintenance_technician_ticket_uid_format.sql` aligns ticket
table validation with technician UIDs;
`20261017000002_maintenance_users_flat_technicians.sql` removes obsolete
time-of-day fields, team grouping, and the technician status flag; and
`20261017000003_unique_maintenance_technician_display_names.sql` enforces
unique technician display names. The flat account table uses the unique
technician UID as its primary key. User UIDs are `u_` followed by 10 random
digits, assigned by a database trigger with a unique constraint; old ticket
requester references are updated to preserve their link to existing users.
Technician UIDs are `t_` followed by 10 random digits. Each technician gets a
private table
named after that UID, with ticket assignment, report, result, and a generated
bucket name field (`result_<TicketId>`). Result-photo object names use the same
one-based numeric names as repair request photos (`1`, `2`, ...).

Technician accounts remain in the single `Maintenance_Users` table without
team grouping. Each technician is created with an Admin-provided `teamName`,
`username`, and required non-empty `comment`; the server generates a unique
`t_` plus 10-digit UID and a 10-character password. `created_at` is assigned
by the database. The UID is the technician row's primary key. Technician names
must be unique regardless of letter case or surrounding whitespace; a database
unique index enforces this rule for both account creation and name changes.
Technician login windows are paired `timestamptz[]` values in `start_time` and
`end_time`. The Admin UI selects inclusive calendar dates in the
`Asia/Bangkok` timezone; past start dates are rejected. An empty date-window
array denies technician login until an Admin assigns at least one range.
Technician account expiry is checked through `Systems_Users.endtime`; there is
no separate enabled/disabled status column for technicians.

New technician passwords are stored encrypted with AES-GCM in
`Maintenance_Users`, while `Systems_Users` stores only the bcrypt hash used for
technician sign-in. The Admin manager can decrypt and view the stored password.
Configure a separate random encryption secret on Supabase before deploying:

```sh
npx --yes supabase secrets set MAINTENANCE_CREDENTIALS_KEY="<random secret of at least 32 characters>"
npx --yes supabase functions deploy maintenance-teams
```

Keep this key in a password manager and in the ignored local `.env.server`
backup. It is required to display generated passwords; losing or rotating it
without re-encrypting the stored credentials makes them unreadable. The
function verifies the signed temporary session and current database role, and
allows only `Admin` and `SuperAdmin` accounts.

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
existing accounts are backfilled as active. The account `uid` uses the format
`u_` followed by 10 random digits; Google Auth UUID remains the authentication
identity. The register and login responses include this `uid` and `status`.
Existing username/password accounts are not
linked to Google automatically; remove old rows manually before their users
register again. Public registration always assigns `User`; elevated roles
must be granted through a trusted administrative process. Never grant roles
from `user_metadata` or expose the service role key in the Flutter app.

Migration `20261008000008_sync_google_auth_users.sql` creates `Users` rows
directly from verified Google Auth users, backfills Google users that already
exist, removes legacy `Users` triggers that referenced columns absent from the
current table, and installs a database trigger for future Google registrations.
Migration `20261008000009_users_unique_ten_digit_uid.sql` initially added the
legacy numeric `uid`; migration `20261016000003_users_prefixed_uids.sql`
converts it to the current prefixed 10-digit format while preserving
historical ticket requester links.
Migration `20261008000011_users_status.sql` adds the `status` column, marks
existing accounts active, and keeps new Google registrations active.

Profile photos are stored in private Storage buckets named with the account UID
(`u_` followed by 10 digits). Migration
`20261016000005_profile_avatar_buckets_use_user_uids.sql` converts existing
user UIDs to the 10-digit format, updates ticket requester references, and
migrates profile image buckets and objects from Google Auth IDs to account
UIDs. Registration creates a private bucket named after the new `u_` UID, with
a 2 MB file-size limit. The `profile-avatar` Edge Function resolves the
signed-in Google account to its account UID, enforces the same bucket limit,
replaces the previous `avatar` image on later uploads, and returns a signed
URL to display the image.
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

The Supabase CLI is not a Flutter dependency. Run it through `npx` (Node.js
and npm are required). Authenticate once, then link this checkout to the project
whose URL is configured in `.env`:

```sh
npx --yes supabase --version
npx --yes supabase login
npx --yes supabase link --project-ref <project-ref>
npx --yes supabase migration list --linked
```

Use the project ref from the hostname in `SUPABASE_URL` (the part before
`.supabase.co`). The CLI stores the link in local Supabase metadata; do not
commit access tokens or database passwords. `migration list --linked` compares
the local migration files with the linked database without applying changes.
Review pending migrations before running `npx --yes supabase db push`. The local
Supabase stack (`npx --yes supabase start` or `status`) additionally requires
Docker Desktop or Podman; linking and managing a hosted project do not require
the local stack.

The SuperAdmin user-change approval schema is in
`supabase/migrations/20261018000000_superadmin_user_change_approvals.sql`.
Display-name-only edits are saved immediately by
`supabase/migrations/20261018000001_superadmin_user_change_names_without_approval.sql`;
role and status changes still require a different active SuperAdmin's approval.
The linked project has an older local migration,
`20261017000003_unique_maintenance_technician_display_names.sql`, that is not
recorded remotely and blocks a normal `db push`; review and resolve that
migration-history difference before applying future migrations.

To deploy Edge Functions after reviewing the changes, run:

```sh
npx --yes supabase functions deploy register-user
npx --yes supabase functions deploy login-user
npx --yes supabase functions deploy superadmin-users
npx --yes supabase functions deploy staff-login
npx --yes supabase functions deploy update-user-profile
npx --yes supabase functions deploy profile-avatar
npx --yes supabase functions deploy create-fix-request
npx --yes supabase functions deploy list-public-tickets
npx --yes supabase functions deploy maintenance-teams
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
The Portal User repair request form is in `lib/gui/fixRequest.dart`; repair
request submission and photo uploads are not connected to a backend yet. Other
role-specific page content is still placeholder UI. Database operations
protected by Supabase RLS are not available to temporary sessions; future data
operations need server-side Edge Function endpoints that verify the signed
temporary session and authorize each role.
The centered
`KUFixIT` text in the app bar is a placeholder for the web logo. The public
ticket monitor page is in `lib/gui/ticketMonitor.dart`; it searches and pages
through ticket IDs using the `list-public-tickets` Edge Function, which returns
the ticket ID, building, area, floor, room, status, and the ticket's shared
request date. Expanding a ticket loads its equipment details from the child
table named for that ticket ID. `request_date` records when the repair request
was submitted; each child table stores one `next_fix_date` as a `timestamptz`.
The ticket list displays the latest scheduled date across its devices. Null
repair dates display as not scheduled; null floor and room values display as
unspecified. Repair history records approved technician reports, their team
access period, device successes, comments, and result photos. A ticket is
automatically finished when no device is pending or validating and at least one
device is finished; its device schedule dates are then cleared.

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

## Map location picker

The "อื่นๆ" repair location supports selecting a point on Google Maps on
Android and iOS. Windows, macOS, Linux, and web use OpenStreetMap because the
Google Maps Flutter plugin does not support native desktop platforms. The
selected latitude and longitude stay in the form state; repair submission is
not yet connected to a backend.

To enable Google Maps on Android and iOS, enable the Maps SDK for Android and
Maps SDK for iOS in Google Cloud Console, then create a restricted API key.
Keep the key out of source control:

- Android: add `MAPS_API_KEY=<your-key>` to `android/local.properties`.
- iOS: create the ignored file `ios/Flutter/MapsApiKey.xcconfig` containing
  `MAPS_API_KEY = <your-key>`.

Rebuild the app after adding the key. Restrict each platform's key to its
application identifier and only the required Maps SDK.
The desktop/web fallback uses the public OpenStreetMap tile server; review its
tile usage policy before deploying a high-traffic production app.
