import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/app/app.dart';
import 'package:vpc/src/core/config/app_environment.dart';
import 'package:vpc/src/core/platform/browser_online_status.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';

void main() {
  testWidgets('Web offline state is honest and recoverable', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localPersistencePlatformProvider.overrideWithValue(
            LocalPersistencePlatform.web,
          ),
          browserOnlineProvider.overrideWith(
            (ref) => Stream<bool>.value(false),
          ),
        ],
        child: VpcApp(environment: AppEnvironment.test),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Web changes require a connection'), findsOne);
    expect(find.textContaining('Reconnect, then retry'), findsOne);
    expect(find.byType(MaterialApp), findsOne);
  });
}
