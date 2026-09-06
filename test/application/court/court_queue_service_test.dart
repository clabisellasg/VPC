import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/court/court_queue_service.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/court/court_queue_entry.dart';
import 'package:vpc/src/domain/matches/match.dart';

String id(int value) =>
    '16000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
final now = DateTime.utc(2026, 9, 6);
const eventName = 'VPC M16 Sample';

CourtMatchView match(
  int number,
  int one,
  int two, {
  MatchStatus status = MatchStatus.queued,
  int division = 1,
  TournamentFormat format = TournamentFormat.singleElimination,
}) => CourtMatchView(
  eventId: EventId(id(1)),
  match: Match(
    id: MatchId(id(100 + number)),
    divisionId: DivisionId(id(10 + division)),
    status: status,
    sideOneTeamId: TeamId(id(200 + one)),
    sideTwoTeamId: TeamId(id(200 + two)),
    roundNumber: 1,
    sequenceNumber: number,
    sideOneScore: status == MatchStatus.completed ? 11 : null,
    sideTwoScore: status == MatchStatus.completed ? 5 : null,
    winnerTeamId: status == MatchStatus.completed
        ? TeamId(id(200 + one))
        : null,
    metadata: RecordMetadata(createdAt: now, updatedAt: now, recordVersion: 0),
  ),
  format: format,
  divisionName: 'Open',
  sideOneLabel: 'Team $one',
  sideTwoLabel: 'Team $two',
);

QueuedCourtMatch queued(int position, CourtMatchView match) => QueuedCourtMatch(
  entry: CourtQueueEntry(
    id: CourtQueueEntryId(id(300 + position)),
    eventId: EventId(id(1)),
    divisionId: match.match.divisionId,
    matchId: match.match.id,
    queuePosition: position,
    metadata: RecordMetadata(createdAt: now, updatedAt: now, recordVersion: 0),
  ),
  match: match,
);

final class _Ids implements CourtQueueIds, CourtQueueClock {
  var next = 900;
  @override
  CourtQueueEntryId queueEntryId() => CourtQueueEntryId(id(next++));
  @override
  SyncOperationId operationId() => SyncOperationId(id(next++));
  @override
  DateTime nowUtc() => now;
}

final class _Repository implements CourtQueueRepository {
  _Repository(this.snapshot);
  CourtQueueSnapshot snapshot;
  CourtQueueCommand? started;
  CourtQueueCommand? reconciled;
  @override
  Future<RepositoryResult<CourtQueueSnapshot>> load(EventId eventId) async =>
      RepositorySuccess(snapshot);
  @override
  Future<RepositoryResult<CourtQueueSnapshot>> reconcile(
    CourtQueueCommand command,
  ) async {
    reconciled = command;
    return RepositorySuccess(snapshot);
  }

  @override
  Future<RepositoryResult<CourtQueueSnapshot>> start(
    CourtQueueCommand command,
  ) async {
    started = command;
    return RepositorySuccess(snapshot);
  }
}

void main() {
  const policy = CourtSchedulingPolicy();
  test('discovers READY matches and excludes blocked, completed and deleted states', () {
    final ready = queued(0, match(1, 1, 2));
    final completed = queued(1, match(2, 3, 4, status: MatchStatus.completed));
    final scheduled = queued(2, match(3, 5, 6, status: MatchStatus.scheduled));
    final snapshot = CourtQueueSnapshot(
      eventId: EventId(id(1)),
      eventName: eventName,
      queue: [completed, ready, scheduled],
      completedHistory: const [],
    );
    expect(policy.order(snapshot), [ready]);
  });

  test('avoids immediate team repeat when an alternative exists without starving skipped match', () {
    final repeat = queued(0, match(1, 1, 2));
    final alternative = queued(1, match(2, 3, 4));
    final previous = match(9, 1, 8, status: MatchStatus.completed);
    final snapshot = CourtQueueSnapshot(
      eventId: EventId(id(1)),
      eventName: eventName,
      queue: [repeat, alternative],
      completedHistory: [previous],
    );
    expect(policy.order(snapshot), [alternative, repeat]);
    final afterAlternative = CourtQueueSnapshot(
      eventId: EventId(id(1)),
      eventName: eventName,
      queue: [repeat],
      completedHistory: [
        previous,
        match(2, 3, 4, status: MatchStatus.completed),
      ],
    );
    expect(policy.order(afterAlternative).single, repeat);
  });

  test('all-repeat fallback preserves durable waiting order', () {
    final first = queued(2, match(1, 1, 2));
    final second = queued(3, match(2, 1, 3));
    final snapshot = CourtQueueSnapshot(
      eventId: EventId(id(1)),
      eventName: eventName,
      queue: [second, first],
      completedHistory: [match(9, 1, 8, status: MatchStatus.completed)],
    );
    expect(policy.order(snapshot), [first, second]);
  });

  test(
    'rest distance resolves equal waiting positions before stable identity',
    () {
      final lessRested = queued(0, match(1, 1, 2));
      final moreRested = queued(0, match(2, 3, 4));
      final history = [
        match(8, 3, 9, status: MatchStatus.completed),
        match(9, 1, 8, status: MatchStatus.completed),
      ];
      final snapshot = CourtQueueSnapshot(
        eventId: EventId(id(1)),
        eventName: eventName,
        queue: [lessRested, moreRested],
        completedHistory: history,
      );
      expect(policy.order(snapshot).first, moreRested);
    },
  );

  test('stable division, sequence and UUID tie-break is deterministic across formats', () {
    final a = queued(
      0,
      match(2, 1, 2, division: 2, format: TournamentFormat.doubleElimination),
    );
    final b = queued(
      0,
      match(1, 3, 4, format: TournamentFormat.singleRoundRobin),
    );
    final c = queued(
      0,
      match(3, 5, 6, division: 3, format: TournamentFormat.doubleRoundRobin),
    );
    final snapshot = CourtQueueSnapshot(
      eventId: EventId(id(1)),
      eventName: eventName,
      queue: [c, a, b],
      completedHistory: const [],
    );
    expect(policy.order(snapshot), [b, a, c]);
    expect(policy.order(snapshot), [b, a, c]);
  });

  test(
    'organizer explicitly starts recommended match and member is rejected',
    () async {
      final snapshot = CourtQueueSnapshot(
        eventId: EventId(id(1)),
        eventName: eventName,
        queue: [queued(0, match(1, 1, 2))],
        completedHistory: const [],
      );
      final repository = _Repository(snapshot), ids = _Ids();
      final service = CourtQueueService(
        repository: repository,
        ids: ids,
        clock: ids,
      );
      expect(
        (await service.startNext(
          snapshot,
          AuthorizationState.member,
        )).isSuccess,
        isFalse,
      );
      expect(
        (await service.startNext(
          snapshot,
          AuthorizationState.organizer,
        )).isSuccess,
        isTrue,
      );
      expect(repository.started?.matchId, match(1, 1, 2).match.id);
    },
  );

  test('start is rejected while another match is Now Playing', () async {
    final snapshot = CourtQueueSnapshot(
      eventId: EventId(id(1)),
      eventName: eventName,
      current: match(9, 7, 8, status: MatchStatus.inProgress),
      queue: [queued(0, match(1, 1, 2))],
      completedHistory: const [],
    );
    final repository = _Repository(snapshot), ids = _Ids();
    final result = await CourtQueueService(
      repository: repository,
      ids: ids,
      clock: ids,
    ).startNext(snapshot, AuthorizationState.organizer);
    expect(result.isSuccess, isFalse);
    expect(repository.started, isNull);
  });

  test(
    'unchanged refresh does not create a redundant queue operation',
    () async {
      final snapshot = CourtQueueSnapshot(
        eventId: EventId(id(1)),
        eventName: eventName,
        queue: [queued(0, match(1, 1, 2))],
        completedHistory: const [],
      );
      final repository = _Repository(snapshot), ids = _Ids();
      final result = await CourtQueueService(
        repository: repository,
        ids: ids,
        clock: ids,
      ).refresh(snapshot.eventId);
      expect(result.isSuccess, isTrue);
      expect(repository.reconciled, isNull);
    },
  );

  test('refresh reconciles newly READY and ineligible entries', () async {
    for (final snapshot in [
      CourtQueueSnapshot(
        eventId: EventId(id(1)),
        eventName: eventName,
        queue: const [],
        unqueuedReady: [match(1, 1, 2)],
        completedHistory: const [],
      ),
      CourtQueueSnapshot(
        eventId: EventId(id(1)),
        eventName: eventName,
        queue: const [],
        completedHistory: const [],
        hasIneligibleEntries: true,
      ),
    ]) {
      final repository = _Repository(snapshot), ids = _Ids();
      await CourtQueueService(
        repository: repository,
        ids: ids,
        clock: ids,
      ).refresh(snapshot.eventId);
      expect(repository.reconciled, isNotNull);
    }
  });
}
