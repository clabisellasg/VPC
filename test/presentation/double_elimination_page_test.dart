import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/tournament/double_elimination_service.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_division.dart';
import 'package:vpc/src/infrastructure/tournament/double_elimination_providers.dart';
import 'package:vpc/src/presentation/accounts/account_controller.dart';
import 'package:vpc/src/presentation/tournament/double_elimination_page.dart';

import '../domain/tournament/tournament_fixtures.dart';

final class _Reader implements DoubleEliminationRepository {
  int writes = 0;

  @override
  Future<RepositoryResult<DoubleEliminationContext>> load(
    EventId eventId,
    DivisionId divisionId,
  ) async => RepositorySuccess(
    DoubleEliminationContext(
      event: Event(
        id: eventId,
        name: 'VPC M15 Sample',
        scheduledAt: DateTime.utc(2026, 9, 5),
        type: EventType.formal,
        status: EventStatus.registration,
        courtLabel: 'Sample Court',
        metadata: fixtureMetadata(),
      ),
      division: EventDivision(
        id: divisionId,
        eventId: eventId,
        name: 'Open',
        format: TournamentFormat.doubleElimination,
        metadata: fixtureMetadata(),
      ),
      teams: [fixtureTeam(3), fixtureTeam(4), fixtureTeam(5)],
      teamLabels: {
        TeamId(fixtureId(3)): 'VPC Pair A',
        TeamId(fixtureId(4)): 'VPC Pair B',
        TeamId(fixtureId(5)): 'VPC Pair C',
      },
    ),
  );

  @override
  Future<RepositoryResult<DoubleEliminationContext>> apply(
    DoubleEliminationCommand command,
  ) {
    writes++;
    throw StateError('Preview must not persist.');
  }
}

void main() {
  testWidgets(
    'organizer preview renders responsive winners losers and finals',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reader = _Reader();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            doubleEliminationRepositoryProvider.overrideWithValue(reader),
            localDoubleEliminationRepositoryProvider.overrideWithValue(null),
            remoteDoubleEliminationRepositoryProvider.overrideWithValue(null),
            doubleEliminationRefreshHintsProvider.overrideWith(
              (ref) => const Stream<void>.empty(),
            ),
            accountControllerProvider.overrideWithBuild(
              (ref, self) => AccountViewState(
                phase: AccountPhase.content,
                snapshot: AccountSnapshot(
                  profile: AccountProfile(
                    accountId: AccountId(fixtureId(90)),
                    displayName: 'VPC Organizer',
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
              body: DoubleEliminationPage(
                eventId: fixtureEvent.value,
                divisionId: fixtureDivision.value,
                organizerRoute: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Preview double-elimination bracket'),
      );
      await tester.tap(find.text('Preview double-elimination bracket'));
      await tester.pumpAndSettle();
      expect(find.text('Winners bracket'), findsOneWidget);
      expect(find.text('Losers bracket'), findsOneWidget);
      expect(find.text('Grand finals'), findsOneWidget);
      expect(find.text('Grand Final 2 — if necessary'), findsOneWidget);
      expect(
        find.text('Preview only — no records have been saved.'),
        findsOneWidget,
      );
      expect(reader.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('guest can read but has no generation controls', (tester) async {
    final reader = _Reader();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          doubleEliminationRepositoryProvider.overrideWithValue(reader),
          localDoubleEliminationRepositoryProvider.overrideWithValue(null),
          remoteDoubleEliminationRepositoryProvider.overrideWithValue(null),
          doubleEliminationRefreshHintsProvider.overrideWith(
            (ref) => const Stream<void>.empty(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DoubleEliminationPage(
              eventId: fixtureEvent.value,
              divisionId: fixtureDivision.value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Double Elimination'), findsWidgets);
    expect(find.text('Preview double-elimination bracket'), findsNothing);
    expect(reader.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
