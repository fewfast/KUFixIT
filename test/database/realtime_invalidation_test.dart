import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/database/realtime_invalidation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('channel failures disconnect and successful resubscribe recovers', () {
    final domains = RealtimeInvalidationDomain.values.toSet();
    final tracker = RealtimeConnectionTracker(domains);
    tracker.markConnecting();
    expect(tracker.state, RealtimeConnectionState.connecting);

    for (final domain in domains) {
      tracker.update(domain, RealtimeSubscribeStatus.subscribed);
    }
    expect(tracker.state, RealtimeConnectionState.connected);

    for (final failure in [
      RealtimeSubscribeStatus.channelError,
      RealtimeSubscribeStatus.timedOut,
      RealtimeSubscribeStatus.closed,
    ]) {
      tracker.update(RealtimeInvalidationDomain.tickets, failure);
      expect(tracker.state, RealtimeConnectionState.disconnected);
      tracker.update(
        RealtimeInvalidationDomain.tickets,
        RealtimeSubscribeStatus.subscribed,
      );
      expect(tracker.state, RealtimeConnectionState.connected);
    }

    tracker.reset();
    expect(tracker.state, RealtimeConnectionState.disconnected);
  });

  test('reconnect delay grows exponentially and is capped', () {
    expect(
      RealtimeReconnectBackoff.delayForAttempt(0),
      const Duration(seconds: 1),
    );
    expect(
      RealtimeReconnectBackoff.delayForAttempt(1),
      const Duration(seconds: 2),
    );
    expect(
      RealtimeReconnectBackoff.delayForAttempt(4),
      const Duration(seconds: 16),
    );
    expect(
      RealtimeReconnectBackoff.delayForAttempt(20),
      const Duration(seconds: 30),
    );
  });

  test(
    'Realtime diagnostics classify auth errors without exposing details',
    () {
      expect(
        realtimeFailureCategory(
          RealtimeSubscribeStatus.channelError,
          Exception('permission denied; bearer secret-value'),
        ),
        'authorization_rejected',
      );
      expect(
        realtimeFailureCategory(RealtimeSubscribeStatus.timedOut, null),
        'subscribe_timeout',
      );
      expect(
        realtimeFailureCategory(RealtimeSubscribeStatus.closed, null),
        'channel_closed',
      );
      expect(
        realtimeFailureCategory(
          RealtimeSubscribeStatus.channelError,
          Exception('network failure'),
        ),
        'channel_error',
      );
    },
  );

  test(
    'refresh binding ignores unrelated domains and coalesces a burst',
    () async {
      final events = StreamController<RealtimeInvalidationDomain>.broadcast();
      var refreshCount = 0;
      final binding = RealtimeRefreshBinding(
        domains: const {RealtimeInvalidationDomain.tickets},
        onRefresh: () async {
          refreshCount++;
        },
        isMounted: () => true,
        invalidations: events.stream,
      );

      events
        ..add(RealtimeInvalidationDomain.accounts)
        ..add(RealtimeInvalidationDomain.tickets)
        ..add(RealtimeInvalidationDomain.tickets)
        ..add(RealtimeInvalidationDomain.reports);
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(refreshCount, 1);
      binding.dispose();
      await events.close();
    },
  );

  test('disposed refresh binding does not run queued work', () async {
    final events = StreamController<RealtimeInvalidationDomain>.broadcast();
    var refreshCount = 0;
    final binding = RealtimeRefreshBinding(
      domains: const {RealtimeInvalidationDomain.accounts},
      onRefresh: () async {
        refreshCount++;
      },
      isMounted: () => true,
      invalidations: events.stream,
    );

    events.add(RealtimeInvalidationDomain.accounts);
    binding.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(refreshCount, 0);
    await events.close();
  });
}
