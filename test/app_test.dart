import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/app/app.dart';
import 'package:vpc/src/core/config/app_environment.dart';

void main() {
  testWidgets('renders the bootstrap root under ProviderScope', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: VpcApp(environment: AppEnvironment.test)),
    );

    expect(find.text('Volta Paddle Club'), findsOneWidget);
    expect(find.text('Project foundation ready.'), findsOneWidget);
    expect(find.text('Environment: test'), findsOneWidget);
    expect(
      find.text('You have pushed the button this many times:'),
      findsNothing,
    );
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('renders an unknown route safely and visibly', (tester) async {
    final app = VpcApp(environment: AppEnvironment.test);
    await tester.pumpWidget(ProviderScope(child: app));

    app.router.go('/not-a-route');
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('/not-a-route'), findsOneWidget);
  });
}
