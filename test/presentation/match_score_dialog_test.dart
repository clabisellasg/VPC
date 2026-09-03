import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/presentation/tournament/match_score_dialog.dart';

void main() {
  testWidgets('immediate rejection does not dispose fields during route exit', (
    tester,
  ) async {
    MatchScoreInput? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                Text(submitted == null ? 'Bracket' : 'Correction blocked'),
                TextButton(
                  onPressed: () async {
                    final result = await showDialog<MatchScoreInput>(
                      context: context,
                      builder: (_) => const MatchScoreDialog(
                        correcting: true,
                        sideOneLabel: 'First pair',
                        sideTwoLabel: 'Second pair',
                      ),
                    );
                    // Expected domain failures return immediately, before route exit.
                    if (result != null) setState(() => submitted = result);
                  },
                  child: const Text('Correct'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Correct'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '11');
    await tester.enterText(find.byType(TextField).at(1), '5');
    await tester.enterText(
      find.byType(TextField).at(2),
      'Downstream lock test',
    );
    await tester.tap(find.text('Confirm score'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(submitted, (
      sideOne: '11',
      sideTwo: '5',
      reason: 'Downstream lock test',
    ));
    expect(find.text('Correction blocked'), findsOneWidget);
    // Reopening and cancelling must also release route-owned controllers safely.
    await tester.tap(find.text('Correct'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '11'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MatchScoreDialog), findsNothing);
  });
}
