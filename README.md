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

## App navigation and roles

The shared navigation displays role-specific menu items for `Unsign` (not
signed in), `User`, `Technician`, `Admin`, and `SuperAdmin`. Set the signed-in
user's `role` in Supabase `app_metadata`; the app falls back to
`user_metadata.role` when it is not present. A signed-in account without a role
is treated as `User`.

The account button signs in with Supabase email and password. The centered
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
