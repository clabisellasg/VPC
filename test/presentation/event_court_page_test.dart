import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/court/court_queue_service.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/court/court_queue_entry.dart';
import 'package:vpc/src/domain/matches/match.dart';
import 'package:vpc/src/infrastructure/court/court_queue_providers.dart';
import 'package:vpc/src/presentation/court/event_court_page.dart';

String id(int value) =>
    '16300000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
final stamp = DateTime.utc(2026, 9, 6);

CourtMatchView courtMatch(int number) => CourtMatchView(
  eventId: EventId(id(1)),
  match: Match(
    id: MatchId(id(10 + number)),
    divisionId: DivisionId(id(2)),
    status: MatchStatus.queued,
    sideOneTeamId: TeamId(id(20 + number)),
    sideTwoTeamId: TeamId(id(30 + number)),
    roundNumber: 1,
    sequenceNumber: number,
    metadata: RecordMetadata(
      createdAt: stamp,
      updatedAt: stamp,
      recordVersion: 0,
    ),
  ),
  format: TournamentFormat.doubleRoundRobin,
  divisionName: 'Open',
  sideOneLabel: 'VPC Sample A',
  sideTwoLabel: 'VPC Sample B',
);

final class _Repository implements CourtQueueRepository {
  int loadCount = 0;
  final snapshot = CourtQueueSnapshot(
    eventId: EventId(id(1)),
    eventName: 'VPC M16 Sample',
    queue: [
      QueuedCourtMatch(
        entry: CourtQueueEntry(
          id: CourtQueueEntryId(id(3)),
          eventId: EventId(id(1)),
          divisionId: DivisionId(id(2)),
          matchId: MatchId(id(11)),
          queuePosition: 0,
          metadata: RecordMetadata(
            createdAt: stamp,
            updatedAt: stamp,
            recordVersion: 0,
          ),
        ),
        match: courtMatch(1),
      ),
    ],
    completedHistory: const [],
  );

  @override
  Future<RepositoryResult<CourtQueueSnapshot>> load(EventId eventId) async {
    loadCount++;
    return RepositorySuccess(snapshot);
  }

  @override
  Future<RepositoryResult<CourtQueueSnapshot>> reconcile(
    CourtQueueCommand command,
  ) async => RepositorySuccess(snapshot);
  @override
  Future<RepositoryResult<CourtQueueSnapshot>> start(
    CourtQueueCommand command,
  ) async => RepositorySuccess(snapshot);
}

void main() {
  testWidgets('guest sees responsive queue but no organizer start control', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courtQueueRepositoryProvider.overrideWithValue(repository),
          courtQueueRefreshHintsProvider.overrideWith(
            (ref) => const Stream<void>.empty(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: EventCourtPage(eventId: id(1))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('VPC M16 Sample'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Up Next'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Up Next'), findsOneWidget);
    expect(find.textContaining('Double Round Robin'), findsOneWidget);
    expect(find.text('Start next match'), findsNothing);
    expect(
      find.bySemanticsLabel(
        RegExp(r'Queued match VPC Sample A versus VPC Sample B'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(repository.loadCount, 1);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('organizer route blocks a guest without reading mutations', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courtQueueRepositoryProvider.overrideWithValue(_Repository()),
          courtQueueRefreshHintsProvider.overrideWith(
            (ref) => const Stream<void>.empty(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: EventCourtPage(eventId: id(1), organizerRoute: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'A confirmed organizer account is required to operate the court.',
      ),
      findsOneWidget,
    );
    expect(find.text('Start next match'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
