# mobileproject

A new Flutter project.

## Supabase setup

Pass your Supabase project URL and publishable (anon) key when running the app:

```sh
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

Use the publishable/anon key in the client, never the `service_role` key. Protect
tables with Supabase Row Level Security (RLS) policies.

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
