import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/sync/sync_contracts.dart';

final class SupabasePlayerRealtimeSource implements RealtimeRefreshSource {
  SupabasePlayerRealtimeSource(
    this.client, {
    this.debounce = const Duration(milliseconds: 300),
  });

  final SupabaseClient client;
  final Duration debounce;
  final StreamController<void> _controller = StreamController<void>.broadcast();
  late final RefreshHintDebouncer _debouncer = RefreshHintDebouncer(debounce);
  RealtimeChannel? _channel;

  @override
  Stream<void> get hints => _controller.stream;

  @override
  Future<void> start() async {
    if (_channel != null) {
      return;
    }
    final channel = client.channel('vpc-player-sync-refresh');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'players',
          callback: (_) => _debouncer.add(() {
            if (!_controller.isClosed) {
              _controller.add(null);
            }
          }),
        )
        .subscribe();
    _channel = channel;
  }

  @override
  Future<void> dispose() async {
    _debouncer.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await client.removeChannel(channel);
    }
    await _controller.close();
  }
}

final class RefreshHintDebouncer {
  RefreshHintDebouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  void add(void Function() callback) {
    _timer?.cancel();
    _timer = Timer(duration, callback);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
