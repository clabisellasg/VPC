import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/court/court_queue_entry.dart';
import '../../domain/matches/match.dart';
import '../accounts/account_models.dart';

enum CourtQueueDisposition {
  synchronized,
  pending,
  blocked,
  failed,
  conflicted,
}

final class CourtMatchView {
  const CourtMatchView({
    required this.eventId,
    required this.match,
    required this.format,
    required this.divisionName,
    required this.sideOneLabel,
    required this.sideTwoLabel,
    this.bracketSection,
  });

  final EventId eventId;
  final Match match;
  final TournamentFormat format;
  final String divisionName;
  final String sideOneLabel;
  final String sideTwoLabel;
  final String? bracketSection;

  Set<TeamId> get teamIds => {?match.sideOneTeamId, ?match.sideTwoTeamId};

  bool get isReady =>
      match.status == MatchStatus.queued &&
      match.sideOneTeamId != null &&
      match.sideTwoTeamId != null &&
      !match.metadata.isDeleted;
}

final class QueuedCourtMatch {
  const QueuedCourtMatch({required this.entry, required this.match});
  final CourtQueueEntry entry;
  final CourtMatchView match;
}

final class CourtQueueSnapshot {
  CourtQueueSnapshot({
    required this.eventId,
    required this.eventName,
    required Iterable<QueuedCourtMatch> queue,
    required Iterable<CourtMatchView> completedHistory,
    this.unqueuedReady = const [],
    this.current,
    this.currentEntry,
    this.hasIneligibleEntries = false,
    this.disposition = CourtQueueDisposition.synchronized,
  }) : queue = List.unmodifiable(queue),
       completedHistory = List.unmodifiable(completedHistory);

  final EventId eventId;
  final String eventName;
  final CourtMatchView? current;
  final CourtQueueEntry? currentEntry;
  final bool hasIneligibleEntries;
  final List<QueuedCourtMatch> queue;
  final List<CourtMatchView> completedHistory;
  final List<CourtMatchView> unqueuedReady;
  final CourtQueueDisposition disposition;
}

final class CourtQueueCommand {
  const CourtQueueCommand({
    required this.operationId,
    required this.eventId,
    required this.action,
    required this.createdAt,
    required this.expectedMatchVersion,
    this.matchId,
    this.entryIds = const {},
  });

  final SyncOperationId operationId;
  final EventId eventId;
  final String action;
  final DateTime createdAt;
  final MatchId? matchId;
  final int expectedMatchVersion;
  final Map<MatchId, CourtQueueEntryId> entryIds;
}

abstract interface class CourtQueueRepository {
  Future<RepositoryResult<CourtQueueSnapshot>> load(EventId eventId);
  Future<RepositoryResult<CourtQueueSnapshot>> reconcile(
    CourtQueueCommand command,
  );
  Future<RepositoryResult<CourtQueueSnapshot>> start(CourtQueueCommand command);
}

abstract interface class CourtQueueIds {
  SyncOperationId operationId();
  CourtQueueEntryId queueEntryId();
}

abstract interface class CourtQueueClock {
  DateTime nowUtc();
}

/// Deterministic one-court policy. Durable queue age always uses the entry
/// position; rest distance and stable identities resolve remaining ties.
final class CourtSchedulingPolicy {
  const CourtSchedulingPolicy();

  List<QueuedCourtMatch> order(CourtQueueSnapshot snapshot) {
    final candidates = snapshot.queue
        .where((row) => row.match.isReady)
        .toList();
    if (candidates.length < 2) return candidates;
    final previous = snapshot.completedHistory.isEmpty
        ? null
        : snapshot.completedHistory.last;
    final hasNonRepeat =
        previous != null &&
        candidates.any(
          (candidate) =>
              candidate.match.teamIds.intersection(previous.teamIds).isEmpty,
        );
    candidates.sort((a, b) {
      if (hasNonRepeat) {
        final ar = a.match.teamIds.intersection(previous.teamIds).isNotEmpty;
        final br = b.match.teamIds.intersection(previous.teamIds).isNotEmpty;
        if (ar != br) return ar ? 1 : -1;
      }
      var comparison = a.entry.queuePosition.compareTo(b.entry.queuePosition);
      if (comparison != 0) return comparison;
      comparison = _leastRestedDistance(
        b.match,
        snapshot.completedHistory,
      ).compareTo(_leastRestedDistance(a.match, snapshot.completedHistory));
      if (comparison != 0) return comparison;
      comparison = a.match.eventId.value.compareTo(b.match.eventId.value);
      if (comparison != 0) return comparison;
      comparison = a.match.match.divisionId.value.compareTo(
        b.match.match.divisionId.value,
      );
      if (comparison != 0) return comparison;
      final ar = a.match.match.roundNumber ?? 0;
      final br = b.match.match.roundNumber ?? 0;
      comparison = ar.compareTo(br);
      if (comparison != 0) return comparison;
      final asq = a.match.match.sequenceNumber ?? 0;
      final bsq = b.match.match.sequenceNumber ?? 0;
      comparison = asq.compareTo(bsq);
      return comparison != 0
          ? comparison
          : a.match.match.id.value.compareTo(b.match.match.id.value);
    });
    return candidates;
  }

  int _leastRestedDistance(
    CourtMatchView candidate,
    List<CourtMatchView> history,
  ) {
    int distance(TeamId team) {
      for (var index = history.length - 1; index >= 0; index--) {
        if (history[index].teamIds.contains(team)) {
          return history.length - index;
        }
      }
      return history.length + 1;
    }

    return candidate.teamIds.map(distance).reduce((a, b) => a < b ? a : b);
  }
}

final class CourtQueueService {
  const CourtQueueService({
    required this.repository,
    required this.ids,
    required this.clock,
    this.policy = const CourtSchedulingPolicy(),
  });

  final CourtQueueRepository repository;
  final CourtQueueIds ids;
  final CourtQueueClock clock;
  final CourtSchedulingPolicy policy;

  Future<RepositoryResult<CourtQueueSnapshot>> refresh(EventId eventId) async {
    final loaded = await repository.load(eventId);
    return loaded.when(
      success: (snapshot) {
        if (snapshot.unqueuedReady.isEmpty && !snapshot.hasIneligibleEntries) {
          return Future.value(RepositorySuccess(snapshot));
        }
        final missing = snapshot.unqueuedReady.map((entry) => entry.match.id);
        return repository.reconcile(
          CourtQueueCommand(
            operationId: ids.operationId(),
            eventId: eventId,
            action: 'reconcile',
            createdAt: clock.nowUtc(),
            expectedMatchVersion: -1,
            entryIds: {for (final id in missing) id: ids.queueEntryId()},
          ),
        );
      },
      failure: (failure) async => RepositoryFailure(failure),
    );
  }

  Future<RepositoryResult<CourtQueueSnapshot>> startNext(
    CourtQueueSnapshot snapshot,
    AuthorizationState authorization,
  ) {
    if (authorization != AuthorizationState.organizer) {
      return Future.value(
        const RepositoryFailure(
          UnauthorizedFailure(message: 'Organizer permission is required.'),
        ),
      );
    }
    if (snapshot.current != null) {
      return Future.value(
        const RepositoryFailure(
          ConflictFailure(message: 'Another match is already Now Playing.'),
        ),
      );
    }
    final ordered = policy.order(snapshot);
    if (ordered.isEmpty) {
      return Future.value(
        const RepositoryFailure(
          ValidationFailure(
            field: 'queue',
            message: 'No READY match is available to start.',
          ),
        ),
      );
    }
    final selected = ordered.first.match.match;
    return repository.start(
      CourtQueueCommand(
        operationId: ids.operationId(),
        eventId: snapshot.eventId,
        action: 'start',
        createdAt: clock.nowUtc(),
        matchId: selected.id,
        expectedMatchVersion: selected.metadata.recordVersion,
      ),
    );
  }
}
