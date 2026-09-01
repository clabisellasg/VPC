import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/supabase_player_realtime_source.dart';
import 'event_setup_writers.dart';

final class EventSetupRealtimeRuntime {
  EventSetupRealtimeRuntime({
    required this.client,
    required this.synchronizer,
    this.debounce = const Duration(milliseconds: 300),
  });

  final SupabaseClient client;
  final EventSetupSynchronizer synchronizer;
  final Duration debounce;
  late final RefreshHintDebouncer _debouncer = RefreshHintDebouncer(debounce);
  RealtimeChannel? _channel;

  Future<void> start() async {
    if (_channel != null) return;
    final channel = client.channel('vpc-event-setup-refresh');
    void hint(PostgresChangePayload _) =>
        _debouncer.add(() => unawaited(synchronizer.synchronize()));
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'events',
          callback: hint,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'event_divisions',
          callback: hint,
        )
        .subscribe();
    _channel = channel;
    unawaited(synchronizer.synchronize());
  }

  Future<void> dispose() async {
    _debouncer.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) await client.removeChannel(channel);
  }
}
