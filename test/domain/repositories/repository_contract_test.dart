import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_repository.dart';
import 'package:vpc/src/domain/matches/match.dart';
import 'package:vpc/src/domain/matches/match_repository.dart';
import 'package:vpc/src/domain/players/permanent_player.dart';
import 'package:vpc/src/domain/players/player_repository.dart';

import '../fixtures.dart';

void main() {
  final player = PermanentPlayer(
    id: PlayerId(playerOneUuid),
    displayName: 'Ana Cruz',
    metadata: metadata(),
  );
  final event = Event(
    id: EventId(eventUuid),
    name: 'Community Day',
    scheduledAt: DateTime.utc(2026, 2, 1),
    type: EventType.casual,
    status: EventStatus.upcoming,
    courtLabel: 'Community Court',
    metadata: metadata(),
  );
  final match = Match(
    id: MatchId(matchOneUuid),
    divisionId: DivisionId(divisionUuid),
    status: MatchStatus.scheduled,
    metadata: metadata(),
  );

  test(
    'test-only fakes satisfy all provider-neutral repository ports',
    () async {
      final playerRepository = _FakePlayerRepository(player);
      final eventRepository = _FakeEventRepository(event);
      final matchRepository = _FakeMatchRepository(match);

      expect((await playerRepository.getById(player.id)).isSuccess, isTrue);
      expect(
        (await eventRepository.observe(EventQuery()).first).isSuccess,
        isTrue,
      );
      expect(
        (await matchRepository.observeForDivision(match.divisionId).first)
            .isSuccess,
        isTrue,
      );
    },
  );

  test('repository results represent success and typed failure', () {
    final success = RepositorySuccess<PermanentPlayer>(player);
    const failure = RepositoryFailure<PermanentPlayer>(
      NotFoundFailure(entity: 'Player', identifier: playerOneUuid),
    );

    expect(
      success.when(success: (value) => value.id, failure: (_) => null),
      player.id,
    );
    expect(failure.isSuccess, isFalse);
    expect(
      failure.when(success: (_) => null, failure: (value) => value),
      isA<NotFoundFailure>(),
    );
  });
}

final class _FakePlayerRepository implements PlayerRepository {
  _FakePlayerRepository(this.player);

  final PermanentPlayer player;

  @override
  Future<RepositoryResult<PermanentPlayer>> getById(PlayerId id) async =>
      RepositorySuccess(player);

  @override
  Stream<RepositoryResult<List<PermanentPlayer>>> observe(
    PlayerSearchQuery query,
  ) => Stream.value(RepositorySuccess([player]));

  @override
  Future<RepositoryResult<PermanentPlayer>> save(
    PermanentPlayer player, {
    int? expectedVersion,
  }) async => RepositorySuccess(player);
}

final class _FakeEventRepository implements EventRepository {
  _FakeEventRepository(this.event);

  final Event event;

  @override
  Future<RepositoryResult<Event>> getById(EventId id) async =>
      RepositorySuccess(event);

  @override
  Stream<RepositoryResult<List<Event>>> observe(EventQuery query) =>
      Stream.value(RepositorySuccess([event]));

  @override
  Future<RepositoryResult<Event>> save(
    Event event, {
    int? expectedVersion,
  }) async => RepositorySuccess(event);
}

final class _FakeMatchRepository implements MatchRepository {
  _FakeMatchRepository(this.match);

  final Match match;

  @override
  Future<RepositoryResult<Match>> getById(MatchId id) async =>
      RepositorySuccess(match);

  @override
  Stream<RepositoryResult<List<Match>>> observeForDivision(
    DivisionId divisionId,
  ) => Stream.value(RepositorySuccess([match]));

  @override
  Future<RepositoryResult<Match>> save(
    Match match, {
    int? expectedVersion,
  }) async => RepositorySuccess(match);
}
