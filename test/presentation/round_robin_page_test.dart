import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/tournament/round_robin_service.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_division.dart';
import 'package:vpc/src/domain/matches/match.dart';
import 'package:vpc/src/domain/tournament/round_robin_generator.dart';
import 'package:vpc/src/domain/tournament/round_robin_tournament.dart';
import 'package:vpc/src/domain/tournament/tournament_contracts.dart';
import 'package:vpc/src/infrastructure/tournament/round_robin_providers.dart';
import 'package:vpc/src/presentation/accounts/account_controller.dart';
import 'package:vpc/src/presentation/tournament/round_robin_page.dart';

import '../domain/tournament/tournament_fixtures.dart';

final class _RoundRobinReader implements RoundRobinRepository {
  _RoundRobinReader({
    this.tournament,
    this.eventStatus = EventStatus.registration,
  });
  final RoundRobinTournament? tournament;
  final EventStatus eventStatus;
  int reads = 0, writes = 0;
  @override
  Future<RepositoryResult<RoundRobinContext>> load(
    EventId eventId,
    DivisionId divisionId,
  ) async {
    reads++;
    return RepositorySuccess(
      RoundRobinContext(
        event: Event(
          id: eventId,
          name: 'VPC Round Robin Preview',
          scheduledAt: DateTime.utc(2026, 9, 4),
          type: EventType.formal,
          status: eventStatus,
          courtLabel: 'Sample Court',
          metadata: fixtureMetadata(),
        ),
        division: EventDivision(
          id: divisionId,
          eventId: eventId,
          name: 'Open',
          format: TournamentFormat.singleRoundRobin,
          metadata: fixtureMetadata(),
        ),
        teams: [fixtureTeam(3), fixtureTeam(4), fixtureTeam(5)],
        teamLabels: {
          TeamId(fixtureId(3)): 'VPC Pair A',
          TeamId(fixtureId(4)): 'VPC Pair B',
          TeamId(fixtureId(5)): 'VPC Pair C',
        },
        tournament: tournament,
      ),
    );
  }

  @override
  Future<RepositoryResult<RoundRobinContext>> apply(RoundRobinCommand command) {
    writes++;
    throw StateError('Preview must not persist');
  }
}

RoundRobinTournament _completedTournament() {
  final teams = [fixtureTeam(3), fixtureTeam(4)];
  final result = const RoundRobinGenerator().generate(
    TournamentGenerationRequest(
      eventId: fixtureEvent,
      division: EventDivision(
        id: fixtureDivision,
        eventId: fixtureEvent,
        name: 'Open',
        format: TournamentFormat.singleRoundRobin,
        metadata: fixtureMetadata(),
      ),
      teams: teams,
    ),
  );
  final plan = result.when(
    success: (value) => value,
    failure: (failure) => throw failure,
  );
  final planned = plan.matches.single;
  final sideOne = (planned.sideOne as DirectTeamSource).teamId;
  final sideTwo = (planned.sideTwo as DirectTeamSource).teamId;
  return RoundRobinTournament(
    plan: plan,
    metadata: fixtureMetadata(),
    matches: {
      planned.key: Match(
        id: MatchId(fixtureId(80)),
        divisionId: fixtureDivision,
        status: MatchStatus.completed,
        metadata: RecordMetadata(
          createdAt: DateTime.utc(2026, 9, 4),
          updatedAt: DateTime.utc(2026, 9, 4),
          recordVersion: 1,
        ),
        sideOneTeamId: sideOne,
        sideTwoTeamId: sideTwo,
        sideOneScore: 11,
        sideTwoScore: 5,
        winnerTeamId: sideOne,
        roundNumber: planned.round,
        sequenceNumber: 1,
      ),
    },
  );
}

void main() {
  testWidgets('responsive schedule preview is accessible and read-only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reader = _RoundRobinReader();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roundRobinRepositoryProvider.overrideWithValue(reader),
          localRoundRobinRepositoryProvider.overrideWithValue(null),
          remoteRoundRobinRepositoryProvider.overrideWithValue(null),
          roundRobinRefreshHintsProvider.overrideWith(
            (ref) => const Stream<void>.empty(),
          ),
          accountControllerProvider.overrideWithBuild(
            (ref, self) => AccountViewState(
              phase: AccountPhase.content,
              snapshot: AccountSnapshot(
                profile: AccountProfile(
                  accountId: AccountId(fixtureId(90)),
                  displayName: 'VPC Sample',
                  metadata: fixtureMetadata(),
                ),
                authorization: AuthorizationState.organizer,
                claim: null,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RoundRobinPage(
              eventId: fixtureEvent.value,
              divisionId: fixtureDivision.value,
              organizerRoute: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review seed order'), findsOneWidget);
    await tester.tap(find.text('Review seed order'));
    await tester.pumpAndSettle();
    expect(find.text('Seed order'), findsOneWidget);
    expect(find.byTooltip('Drag to reorder seed'), findsNWidgets(3));
    await tester.drag(
      find.byTooltip('Drag to reorder seed').first,
      const Offset(0, 100),
    );
    await tester.pumpAndSettle();
    expect(find.text('Order changed'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Preview schedule'));
    await tester.tap(find.text('Preview schedule'));
    await tester.pumpAndSettle();
    expect(
      find.text('Preview only — no records have been saved.'),
      findsOneWidget,
    );
    expect(find.textContaining('Resting:'), findsNWidgets(3));
    expect(reader.writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completed schedule labels champion and runner-up in progress', (
    tester,
  ) async {
    final reader = _RoundRobinReader(
      tournament: _completedTournament(),
      eventStatus: EventStatus.inProgress,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roundRobinRepositoryProvider.overrideWithValue(reader),
          localRoundRobinRepositoryProvider.overrideWithValue(null),
          remoteRoundRobinRepositoryProvider.overrideWithValue(null),
          roundRobinRefreshHintsProvider.overrideWith(
            (ref) => const Stream<void>.empty(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RoundRobinPage(
              eventId: fixtureEvent.value,
              divisionId: fixtureDivision.value,
              organizerRoute: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standings'));
    await tester.pumpAndSettle();
    expect(find.text('Final placements'), findsOneWidget);
    expect(find.text('Champion: VPC Pair A'), findsOneWidget);
    expect(find.text('Runner-up: VPC Pair B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
