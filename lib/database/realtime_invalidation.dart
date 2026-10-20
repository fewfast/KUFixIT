import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connect.dart';

enum RealtimeInvalidationDomain {
  accounts,
  tickets,
  technicians,
  reports,
  storage,
  activityLogs,
}

extension on RealtimeInvalidationDomain {
  String get topic => switch (this) {
        RealtimeInvalidationDomain.activityLogs =>
          'kufixit:invalidate:activity_logs',
        _ => 'kufixit:invalidate:$name',
      };
}

enum RealtimeConnectionState { connecting, connected, disconnected }

class RealtimeConnectionTracker {
  RealtimeConnectionTracker(this.domains);

  final Set<RealtimeInvalidationDomain> domains;
  final Set<RealtimeInvalidationDomain> _connectedDomains = {};

  RealtimeConnectionState state = RealtimeConnectionState.disconnected;

  bool update(
    RealtimeInvalidationDomain domain,
    RealtimeSubscribeStatus status,
  ) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      _connectedDomains.add(domain);
    } else {
      _connectedDomains.remove(domain);
    }
    final wasConnected = state == RealtimeConnectionState.connected;
    state = _connectedDomains.length == domains.length
        ? RealtimeConnectionState.connected
        : RealtimeConnectionState.disconnected;
    return !wasConnected && state == RealtimeConnectionState.connected;
  }

  void markConnecting() => state = RealtimeConnectionState.connecting;

  void reset() {
    _connectedDomains.clear();
    state = RealtimeConnectionState.disconnected;
  }
}

class RealtimeReconnectBackoff {
  const RealtimeReconnectBackoff._();

  static Duration delayForAttempt(int attempt) {
    final seconds = 1 << attempt.clamp(0, 5).toInt();
    return Duration(seconds: seconds > 30 ? 30 : seconds);
  }
}

String realtimeFailureCategory(RealtimeSubscribeStatus status, Object? error) {
  switch (status) {
    case RealtimeSubscribeStatus.subscribed:
      return 'none';
    case RealtimeSubscribeStatus.timedOut:
      return 'subscribe_timeout';
    case RealtimeSubscribeStatus.closed:
      return 'channel_closed';
    case RealtimeSubscribeStatus.channelError:
      final safeMessage = error?.toString().toLowerCase() ?? '';
      if (safeMessage.contains('permission') ||
          safeMessage.contains('unauthor') ||
          safeMessage.contains('policy') ||
          safeMessage.contains('jwt') ||
          safeMessage.contains('forbidden')) {
        return 'authorization_rejected';
      }
      return 'channel_error';
  }
}

class RealtimeInvalidationService {
  RealtimeInvalidationService._();

  static final instance = RealtimeInvalidationService._();

  static const _event = 'invalidate';
  static const _domains = RealtimeInvalidationDomain.values;
  static const _subscribeTimeout = Duration(seconds: 12);

  final _invalidations =
      StreamController<RealtimeInvalidationDomain>.broadcast();
  final Map<RealtimeInvalidationDomain, RealtimeChannel> _channels = {};
  final _tracker = RealtimeConnectionTracker(_domains.toSet());
  final ValueNotifier<RealtimeConnectionState> _connectionState = ValueNotifier(
    RealtimeConnectionState.disconnected,
  );
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  int _generation = 0;
  bool _running = false;
  bool _reconnecting = false;

  Stream<RealtimeInvalidationDomain> get invalidations => _invalidations.stream;
  ValueListenable<RealtimeConnectionState> get connectionState =>
      _connectionState;

  Future<void> start() async {
    // SupabaseClient propagates auth.onAuthStateChange JWTs to Realtime with
    // realtime.setAuth(). Keep these app-wide channels alive across Google
    // sign-in/out; staff temporary sessions do not change Supabase Auth.
    _running = true;
    if (_channels.length == _domains.length) return;
    if (!SupabaseConnection.isInitialized) {
      _setState(RealtimeConnectionState.disconnected);
      _scheduleReconnect();
      return;
    }

    _authSubscription ??= SupabaseConnection.client.auth.onAuthStateChange
        .listen((authState) {
          final jwtRole = authState.session == null ? 'anon' : 'authenticated';
          debugPrint(
            'Supabase Realtime auth event=${authState.event.name}; '
            'jwtRole=$jwtRole.',
          );
        });

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _tracker.markConnecting();
    _setState(RealtimeConnectionState.connecting);
    final generation = ++_generation;
    try {
      for (final domain in _domains) {
        if (_channels.containsKey(domain)) continue;
        final channel = SupabaseConnection.client.channel(
          domain.topic,
          opts: const RealtimeChannelConfig(private: true),
        );
        _channels[domain] = channel;
        channel
            .onBroadcast(
              event: _event,
              callback: (_) => _invalidations.add(domain),
            )
            .subscribe((status, error) {
              if (generation != _generation || !_running) return;
              final justConnected = _tracker.update(domain, status);
              _setState(_tracker.state);
              if (status == RealtimeSubscribeStatus.subscribed) {
                debugPrint('Supabase Realtime ${domain.name}: subscribed.');
                if (justConnected) {
                  _reconnectAttempt = 0;
                  _reconnectTimer?.cancel();
                  _reconnectTimer = null;
                  _publishCatchUpInvalidations();
                }
              } else {
                debugPrint(
                  'Supabase Realtime ${domain.name}: ${status.name} '
                  '(${realtimeFailureCategory(status, error)}).',
                );
                _scheduleReconnect();
              }
            }, _subscribeTimeout);
      }
    } on Object catch (error) {
      debugPrint('Supabase Realtime setup failed (${error.runtimeType}).');
      _setState(RealtimeConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void _setState(RealtimeConnectionState state) {
    _connectionState.value = state;
  }

  void _scheduleReconnect() {
    if (!_running || _reconnecting || _reconnectTimer != null) return;
    _setState(RealtimeConnectionState.disconnected);
    final delay = RealtimeReconnectBackoff.delayForAttempt(_reconnectAttempt++);
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      await _replaceChannels();
    } finally {
      _reconnecting = false;
      if (_running && !SupabaseConnection.isInitialized) {
        _scheduleReconnect();
      }
    }
  }

  Future<void> _replaceChannels() async {
    if (!_running || !SupabaseConnection.isInitialized) {
      _scheduleReconnect();
      return;
    }
    final channels = _channels.values.toList(growable: false);
    _channels.clear();
    _generation++;
    _tracker.reset();
    _setState(RealtimeConnectionState.connecting);
    for (final channel in channels) {
      try {
        await SupabaseConnection.client
            .removeChannel(channel)
            .timeout(const Duration(seconds: 5));
      } on Object catch (error) {
        debugPrint(
          'Supabase Realtime channel cleanup failed (${error.runtimeType}).',
        );
      }
    }
    if (_running) await start();
  }

  void _publishCatchUpInvalidations() {
    for (final domain in _domains) {
      _invalidations.add(domain);
    }
  }

  Future<void> stop() async {
    _running = false;
    await _authSubscription?.cancel();
    _authSubscription = null;
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final channels = _channels.values.toList(growable: false);
    _channels.clear();
    _tracker.reset();
    _setState(RealtimeConnectionState.disconnected);
    for (final channel in channels) {
      try {
        final status = await SupabaseConnection.client
            .removeChannel(channel)
            .timeout(const Duration(seconds: 5));
        if (status != 'ok') {
          debugPrint('Supabase Realtime channel cleanup returned non-ok.');
        }
      } on Object catch (error) {
        debugPrint(
          'Supabase Realtime channel cleanup failed (${error.runtimeType}).',
        );
      }
    }
  }

  void onAppResumed() {
    if (_tracker.state == RealtimeConnectionState.connected) {
      _publishCatchUpInvalidations();
    } else if (_running) {
      _scheduleReconnect();
    }
  }
}

class RealtimeRefreshBinding {
  RealtimeRefreshBinding({
    required this.domains,
    required this.onRefresh,
    required this.isMounted,
    Stream<RealtimeInvalidationDomain>? invalidations,
  }) {
    _subscription =
        (invalidations ?? RealtimeInvalidationService.instance.invalidations)
            .where(domains.contains)
            .listen((_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), _refresh);
            });
  }

  final Set<RealtimeInvalidationDomain> domains;
  final Future<void> Function() onRefresh;
  final bool Function() isMounted;
  late final StreamSubscription<RealtimeInvalidationDomain> _subscription;
  Timer? _debounce;
  bool _refreshing = false;
  bool _refreshPending = false;
  bool _disposed = false;

  void _refresh() {
    if (_disposed || !isMounted()) return;
    if (_refreshing) {
      _refreshPending = true;
      return;
    }
    unawaited(_runRefresh());
  }

  Future<void> _runRefresh() async {
    _refreshing = true;
    try {
      do {
        _refreshPending = false;
        if (_disposed || !isMounted()) return;
        try {
          await onRefresh();
        } on Exception catch (error) {
          debugPrint('Realtime data refresh failed: $error');
        }
        if (_refreshPending) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      } while (_refreshPending);
    } finally {
      _refreshing = false;
    }
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_subscription.cancel());
  }
}
