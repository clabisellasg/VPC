import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vpc/src/app/app.dart';
import 'package:vpc/src/core/config/app_environment.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';

void main() {
  testWidgets('renders the public guest root under ProviderScope', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localPersistencePlatformProvider.overrideWithValue(
            LocalPersistencePlatform.web,
          ),
        ],
        child: VpcApp(environment: AppEnvironment.test),
      ),
    );

    expect(find.text('Volta Paddle Club'), findsOneWidget);
    expect(
      find.text('Community pickleball, one court at a time.'),
      findsOneWidget,
    );
    expect(find.text('Browse events'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsNothing);
    expect(find.textContaining('Register'), findsNothing);
    expect(
      find.text('You have pushed the button this many times:'),
      findsNothing,
    );
    expect(find.byIcon(Icons.add), findsNothing);
    expect(GoRouter.optionURLReflectsImperativeAPIs, isTrue);
  });

  testWidgets('renders an unknown route safely and visibly', (tester) async {
    final app = VpcApp(environment: AppEnvironment.test);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localPersistencePlatformProvider.overrideWithValue(
            LocalPersistencePlatform.web,
          ),
        ],
        child: app,
      ),
    );

    app.router.go('/not-a-route');
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('/not-a-route'), findsOneWidget);
  });
}
