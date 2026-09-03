import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/tournament/single_elimination_service.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_division.dart';
import 'package:vpc/src/infrastructure/tournament/bracket_providers.dart';
import 'package:vpc/src/presentation/accounts/account_controller.dart';
import 'package:vpc/src/presentation/tournament/single_elimination_page.dart';

import '../domain/tournament/tournament_fixtures.dart';

class _Reader implements BracketRepository {
  int reads = 0, writes = 0;
  @override
  Future<RepositoryResult<BracketContext>> load(EventId e, DivisionId d) async {
    reads++;
    return RepositorySuccess(
      BracketContext(
        event: Event(
          id: e,
          name: 'VPC Preview Test',
          scheduledAt: DateTime.utc(2026, 9, 4),
          type: EventType.formal,
          status: EventStatus.registration,
          courtLabel: 'Sample Court',
          metadata: fixtureMetadata(),
        ),
        division: EventDivision(
          id: d,
          eventId: e,
          name: 'Open',
          format: TournamentFormat.singleElimination,
          metadata: fixtureMetadata(),
        ),
        teams: [fixtureTeam(3), fixtureTeam(4)],
        teamLabels: {
          TeamId(fixtureId(3)): 'VPC Pair A',
          TeamId(fixtureId(4)): 'VPC Pair B',
        },
      ),
    );
  }

  @override
  Future<RepositoryResult<BracketContext>> apply(BracketCommand c) {
    writes++;
    throw StateError('Preview must not write');
  }
}

void main() {
  testWidgets(
    'preview notice survives manual and periodic refresh without writes',
    (tester) async {
      final reader = _Reader();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bracketRepositoryProvider.overrideWithValue(reader),
            localBracketRepositoryProvider.overrideWithValue(null),
            remoteBracketRepositoryProvider.overrideWithValue(null),
            bracketRefreshHintsProvider.overrideWith(
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
              body: SingleEliminationPage(
                eventId: fixtureEvent.value,
                divisionId: fixtureDivision.value,
                organizerRoute: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Preview bracket'));
      await tester.tap(find.text('Preview bracket'));
      await tester.pumpAndSettle();
      final notice = find.text('Preview only — no records have been saved.');
      expect(notice, findsOneWidget);
      await tester.ensureVisible(find.text('Refresh bracket'));
      await tester.tap(find.text('Refresh bracket'));
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);
      expect(reader.reads, greaterThanOrEqualTo(3));
      expect(reader.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
