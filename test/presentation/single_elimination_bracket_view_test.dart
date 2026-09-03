import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/tournament/single_elimination_generator.dart';
import 'package:vpc/src/presentation/tournament/single_elimination_bracket_view.dart';

import '../domain/tournament/tournament_fixtures.dart';

void main() {
  testWidgets('overflow has visible scrollbar and round navigation controls', (
    tester,
  ) async {
    final request = fixtureRequest(
      teams: [for (var i = 3; i < 11; i++) fixtureTeam(i)],
    );
    final plan = const SingleEliminationGenerator()
        .generate(request)
        .when(success: (p) => p, failure: (f) => throw f);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: SingleEliminationBracketView(plan: plan, labels: const {}),
            ),
          ),
        ),
      ),
    );
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar).first);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.scrollbarOrientation, ScrollbarOrientation.top);
    expect(scrollbar.controller!.offset, 0);
    await tester.tap(find.text('Later rounds'));
    await tester.pumpAndSettle();
    expect(scrollbar.controller!.offset, greaterThan(0));
    await tester.tap(find.text('Later rounds'));
    await tester.pumpAndSettle();
    expect(
      scrollbar.controller!.offset,
      scrollbar.controller!.position.maxScrollExtent,
    );
    await tester.tap(find.text('Earlier rounds'));
    await tester.pumpAndSettle();
    expect(
      scrollbar.controller!.offset,
      lessThan(scrollbar.controller!.position.maxScrollExtent),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets('real round columns, byes and large text at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final request = fixtureRequest(
        teams: [for (var i = 3; i < 8; i++) fixtureTeam(i)],
      );
      final plan = const SingleEliminationGenerator()
          .generate(request)
          .when(success: (p) => p, failure: (f) => throw f);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              textScaler: const TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SingleEliminationBracketView(
                  plan: plan,
                  labels: {
                    for (final t in request.teams) t.team.id: 'VPC Sample Pair',
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Round 1'), findsOneWidget);
      expect(find.text('Final'), findsOneWidget);
      expect(find.textContaining('BYE'), findsWidgets);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
