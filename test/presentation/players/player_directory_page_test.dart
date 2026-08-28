import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/app/app.dart';
import 'package:vpc/src/application/players/player_directory_models.dart';
import 'package:vpc/src/application/players/player_directory_reader.dart';
import 'package:vpc/src/core/config/app_environment.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';
import 'package:vpc/src/infrastructure/players/player_directory_providers.dart';

void main() {
  testWidgets('guest opens directory, searches, and opens a basic profile', (
    tester,
  ) async {
    final reader = _Reader([profile()]);
    final app = await pumpApp(tester, reader);
    app.router.go('/players');
    await tester.pumpAndSettle();

    expect(find.text('Community players'), findsOneWidget);
    expect(find.text('VPC M8 Sample Player'), findsOneWidget);
    expect(find.text('Add permanent player'), findsNothing);
    expect(find.textContaining('email'), findsNothing);
    expect(find.textContaining(playerId), findsNothing);

    await tester.enterText(find.byType(TextField), 'm8 sample');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(reader.lastQuery, 'm8 sample');

    await tester.tap(find.text('VPC M8 Sample Player'));
    await tester.pumpAndSettle();
    expect(find.text('Permanent community player record'), findsOneWidget);
    expect(find.text('wins'), findsNothing);
    expect(find.text('skill'), findsNothing);
  });

  testWidgets('unknown player route shows a safe missing state', (
    tester,
  ) async {
    final app = await pumpApp(tester, _Reader(const []));
    app.router.go('/players/84000000-0000-4000-8000-000000000099');
    await tester.pumpAndSettle();
    expect(find.text('Player not available'), findsOneWidget);
  });

  testWidgets('guest cannot expose organizer player creation', (tester) async {
    final app = await pumpApp(tester, _Reader([profile()]));
    app.router.go('/organizer/players/new');
    await tester.pumpAndSettle();
    expect(find.text('Organizer access required'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('directory remains usable at narrow and wide sizes', (
    tester,
  ) async {
    for (final size in [const Size(360, 700), const Size(1100, 800)]) {
      await tester.binding.setSurfaceSize(size);
      final app = await pumpApp(tester, _Reader([profile()]));
      app.router.go('/players');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Community players'), findsOneWidget);
    }
    await tester.binding.setSurfaceSize(null);
  });
}

Future<VpcApp> pumpApp(
  WidgetTester tester,
  PlayerDirectoryReader reader,
) async {
  final app = VpcApp(environment: AppEnvironment.test);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.web,
        ),
        playerDirectoryReaderProvider.overrideWithValue(reader),
      ],
      child: app,
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

const playerId = '84000000-0000-4000-8000-000000000001';

PublicPlayerProfile profile() => PublicPlayerProfile(
  id: PlayerId(playerId),
  displayName: 'VPC M8 Sample Player',
  metadata: RecordMetadata(
    createdAt: DateTime.utc(2026, 8, 29),
    updatedAt: DateTime.utc(2026, 8, 29),
    recordVersion: 0,
  ),
);

class _Reader implements PlayerDirectoryReader {
  _Reader(this.players);
  final List<PublicPlayerProfile> players;
  String? lastQuery;

  @override
  Future<RepositoryResult<PlayerDirectoryEntry>> getById(PlayerId id) async {
    final matches = players.where((player) => player.id == id);
    if (matches.isEmpty) {
      return RepositoryFailure(
        NotFoundFailure(entity: 'Player', identifier: id.value),
      );
    }
    return RepositorySuccess(PlayerDirectoryEntry(profile: matches.single));
  }

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery query,
  ) async {
    lastQuery = query.searchText;
    return RepositorySuccess(
      PlayerDirectoryPage(
        entries: players
            .where(
              (player) =>
                  normalizePlayerName(player.displayName)
                      .contains(query.searchText),
            )
            .map((player) => PlayerDirectoryEntry(profile: player)),
        hasMore: false,
        origin: PlayerDirectoryOrigin.remote,
      ),
    );
  }

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> refreshPage(
    PlayerDirectoryQuery query,
  ) => readPage(query);
}
