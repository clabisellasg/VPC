import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/infrastructure/sync/supabase_player_realtime_source.dart';

void main() {
  test(
    'Realtime bursts coalesce into one authoritative refresh hint',
    () async {
      final debouncer = RefreshHintDebouncer(Duration.zero);
      var refreshes = 0;

      debouncer.add(() => refreshes++);
      debouncer.add(() => refreshes++);
      debouncer.add(() => refreshes++);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(refreshes, 1);
      debouncer.dispose();
    },
  );

  test('disposing the Realtime debouncer cancels pending refresh', () async {
    final debouncer = RefreshHintDebouncer(const Duration(milliseconds: 5));
    var refreshes = 0;
    debouncer.add(() => refreshes++);
    debouncer.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(refreshes, 0);
  });
}
