import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/players/player_creation_service.dart';
import 'package:vpc/src/application/players/player_directory_models.dart';
import 'package:vpc/src/application/players/player_directory_reader.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';

void main() {
  test('normalization trims, collapses whitespace, and ignores case', () {
    expect(normalizePlayerName('  VPC   Sample  '), 'vpc sample');
    expect(preparePlayerDisplayName('  VPC   Sample  '), 'VPC Sample');
  });

  test('blank display name fails validation', () {
    expect(
      () => preparePlayerDisplayName('  '),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('query enforces the bounded 50-record page', () {
    expect(PlayerDirectoryQuery().limit, 50);
    expect(
      () => PlayerDirectoryQuery(limit: 51),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('directory page is immutable and provides a stable cursor', () {
    final page = PlayerDirectoryPage(
      entries: [PlayerDirectoryEntry(profile: profile())],
      hasMore: true,
      origin: PlayerDirectoryOrigin.remote,
    );
    expect(
      () => page.entries.add(PlayerDirectoryEntry(profile: profile())),
      throwsUnsupportedError,
    );
    expect(page.nextCursor!.normalizedName, 'vpc sample player');
  });

  test('public profile rejects account identity and tombstones', () {
    final deleted = metadata(deletedAt: DateTime.utc(2026, 8, 30));
    expect(
      () => PublicPlayerProfile(
        id: PlayerId(playerId),
        displayName: 'Player',
        metadata: deleted,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'duplicate warning is conservative and requires acknowledgement',
    () async {
      final reader = _Reader([profile(name: 'VPC Sample Player')]);
      final writer = _Writer();
      final service = PlayerCreationService(
        reader: reader,
        writer: writer,
        idFactory: _IdFactory(),
        clock: _Clock(),
      );
      final warning = await service.create(
        requestedDisplayName: '  vpc   SAMPLE player ',
        duplicateAcknowledged: false,
      );
      expect(warning, isA<PlayerDuplicateWarning>());
      expect(writer.calls, 0);

      final created = await service.create(
        requestedDisplayName: '  vpc   SAMPLE player ',
        duplicateAcknowledged: true,
      );
      expect(created, isA<PlayerCreated>());
      expect(writer.calls, 1);
      expect(writer.last!.displayName, 'vpc SAMPLE player');
    },
  );

  test('different people can share a name without automatic merging', () async {
    final writer = _Writer();
    final service = PlayerCreationService(
      reader: _Reader([profile()]),
      writer: writer,
      idFactory: _IdFactory(),
      clock: _Clock(),
    );
    final result = await service.create(
      requestedDisplayName: 'VPC Sample Player',
      duplicateAcknowledged: true,
    ) as PlayerCreated;
    expect(result.value.profile.id.value, createdPlayerId);
    expect(result.value.profile.id.value, isNot(playerId));
  });

  test(
    'creation preserves injected UUID, UTC time, and version zero',
    () async {
      final service = PlayerCreationService(
        reader: _Reader(const []),
        writer: _Writer(),
        idFactory: _IdFactory(),
        clock: _Clock(),
      );
      final result = await service.create(
        requestedDisplayName: 'VPC New Player',
        duplicateAcknowledged: false,
      ) as PlayerCreated;
      expect(result.value.profile.id.value, createdPlayerId);
      expect(result.value.profile.metadata.createdAt, testNow);
      expect(result.value.profile.metadata.recordVersion, 0);
    },
  );
}

const playerId = '81000000-0000-4000-8000-000000000001';
const createdPlayerId = '81000000-0000-4000-8000-000000000002';
final testNow = DateTime.utc(2026, 8, 29, 1);

RecordMetadata metadata({DateTime? deletedAt}) => RecordMetadata(
  createdAt: testNow,
  updatedAt: testNow,
  recordVersion: 0,
  deletedAt: deletedAt,
);

PublicPlayerProfile profile({String name = 'VPC Sample Player'}) =>
    PublicPlayerProfile(
      id: PlayerId(playerId),
      displayName: name,
      metadata: metadata(),
    );

class _Reader implements PlayerDirectoryReader {
  _Reader(this.players);
  final List<PublicPlayerProfile> players;

  @override
  Future<RepositoryResult<PlayerDirectoryEntry>> getById(PlayerId id) async =>
      RepositorySuccess(PlayerDirectoryEntry(profile: players.single));

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery query,
  ) async => RepositorySuccess(
    PlayerDirectoryPage(
      entries: players
          .where(
            (p) =>
                normalizePlayerName(p.displayName).contains(query.searchText),
          )
          .map((p) => PlayerDirectoryEntry(profile: p)),
      hasMore: false,
      origin: PlayerDirectoryOrigin.remote,
    ),
  );

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> refreshPage(
    PlayerDirectoryQuery query,
  ) => readPage(query);
}

class _Writer implements PlayerCreationWriter {
  int calls = 0;
  PublicPlayerProfile? last;

  @override
  Future<RepositoryResult<CreatedPlayer>> create(
    PublicPlayerProfile player,
  ) async {
    calls++;
    last = player;
    return RepositorySuccess(
      CreatedPlayer(
        profile: player,
        disposition: PlayerCreationDisposition.synchronized,
      ),
    );
  }
}

class _IdFactory implements PlayerIdFactory {
  @override
  PlayerId createPlayerId() => PlayerId(createdPlayerId);
}

class _Clock implements PlayerDirectoryClock {
  @override
  DateTime nowUtc() => testNow;
}
