import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/players/player_directory_models.dart';
import 'package:vpc/src/application/players/player_directory_reader.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/infrastructure/players/player_directory_providers.dart';
import 'package:vpc/src/presentation/players/player_directory_controller.dart';

void main() {
  test('duplicate refresh requests are coalesced', () async {
    final reader = _ControlledReader();
    final container = ProviderContainer(
      overrides: [playerDirectoryReaderProvider.overrideWithValue(reader)],
    );
    addTearDown(container.dispose);
    container.listen(playerDirectoryControllerProvider, (_, _) {});
    await pumpEvents();
    final controller = container.read(
      playerDirectoryControllerProvider.notifier,
    );
    final before = reader.refreshCalls;

    final first = controller.refresh();
    final second = controller.refresh();
    await Future.wait([first, second]);
    expect(reader.refreshCalls, before + 1);
  });

  test('a stale query response cannot replace a newer query', () async {
    final reader = _ControlledReader();
    final container = ProviderContainer(
      overrides: [playerDirectoryReaderProvider.overrideWithValue(reader)],
    );
    addTearDown(container.dispose);
    container.listen(playerDirectoryControllerProvider, (_, _) {});
    await pumpEvents();

    final controller = container.read(
      playerDirectoryControllerProvider.notifier,
    );
    final old = controller.setQuery('old');
    await pumpEvents();
    final newer = controller.setQuery('new');
    await newer;
    reader.oldRefresh.complete(RepositorySuccess(page('Old Player')));
    await old;

    final state = container.read(playerDirectoryControllerProvider);
    expect(state.query, 'new');
    expect(state.entries.single.profile.displayName, 'New Player');
  });
}

Future<void> pumpEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

PlayerDirectoryPage page(String name) => PlayerDirectoryPage(
  entries: [
    PlayerDirectoryEntry(
      profile: PublicPlayerProfile(
        id: PlayerId('85000000-0000-4000-8000-000000000001'),
        displayName: name,
        metadata: RecordMetadata(
          createdAt: DateTime.utc(2026, 8, 29),
          updatedAt: DateTime.utc(2026, 8, 29),
          recordVersion: 0,
        ),
      ),
    ),
  ],
  hasMore: false,
  origin: PlayerDirectoryOrigin.remote,
);

class _ControlledReader implements PlayerDirectoryReader {
  final oldRefresh = Completer<RepositoryResult<PlayerDirectoryPage>>();
  int refreshCalls = 0;

  @override
  Future<RepositoryResult<PlayerDirectoryEntry>> getById(PlayerId id) async =>
      RepositorySuccess(page('Player').entries.single);

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery query,
  ) async => RepositorySuccess(
    page('${query.searchText.isEmpty ? 'Initial' : query.searchText} Player'),
  );

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> refreshPage(
    PlayerDirectoryQuery query,
  ) {
    refreshCalls++;
    if (query.searchText == 'old') return oldRefresh.future;
    return Future.value(
      RepositorySuccess(
        page(query.searchText == 'new' ? 'New Player' : 'Initial Player'),
      ),
    );
  }
}
