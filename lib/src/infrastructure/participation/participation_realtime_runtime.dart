import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/supabase_player_realtime_source.dart';
import 'participation_writers.dart';

final class ParticipationRealtimeRuntime {
  ParticipationRealtimeRuntime({
    required this.client,
    required this.synchronizer,
    this.debounce = const Duration(milliseconds: 300),
  });
  final SupabaseClient client;
  final ParticipationSynchronizer synchronizer;
  final Duration debounce;
  late final RefreshHintDebouncer _debouncer = RefreshHintDebouncer(debounce);
  RealtimeChannel? _channel;

  Future<void> start() async {
    if (_channel != null) return;
    final channel = client.channel('vpc-participation-refresh');
    void hint(PostgresChangePayload _) =>
        _debouncer.add(() => unawaited(synchronizer.synchronize()));
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'event_participants',
          callback: hint,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'division_participants',
          callback: hint,
        )
        .subscribe();
    _channel = channel;
  }

  Future<void> dispose() async {
    _debouncer.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) await client.removeChannel(channel);
  }
}
