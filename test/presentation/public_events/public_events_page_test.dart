import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/app/app.dart';
import 'package:vpc/src/application/public_events/public_event_models.dart';
import 'package:vpc/src/application/public_events/public_event_reader.dart';
import 'package:vpc/src/core/config/app_environment.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';
import 'package:vpc/src/infrastructure/public_events/public_event_providers.dart';
import 'package:vpc/src/presentation/public_events/public_events_controller.dart';

import '../../application/public_events/public_event_fixtures.dart';

void main() {
  testWidgets('guest navigates through grouped events and public details', (
    tester,
  ) async {
    final reader = _FakeReader.success(publicCatalog());
    await _pumpApp(tester, reader);

    expect(find.textContaining('No account is required'), findsOneWidget);
    await tester.tap(find.text('Browse events'));
    await tester.pumpAndSettle();

    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('VPC Demo Current'), findsOneWidget);
    expect(find.text('VPC Demo Upcoming'), findsOneWidget);
    expect(find.text('VPC Demo Completed'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Open VPC Demo Current' &&
            widget.properties.button == true,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('VPC Demo Current'));
    await tester.pumpAndSettle();
    expect(find.text('Sample Open'), findsOneWidget);
    expect(find.text('Single round robin'), findsOneWidget);
    expect(find.text('Aug 28, 2026 • 2:00 AM UTC'), findsOneWidget);

    await tester.tap(find.text('Back to events'));
    await tester.pumpAndSettle();
    expect(find.text('Public events'), findsOneWidget);
  });

  testWidgets('shows loading then empty public state', (tester) async {
    final completer = Completer<RepositoryResult<PublicEventCatalog>>();
    final reader = _FakeReader(refreshes: [completer.future]);
    await _pumpEvents(tester, reader);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(
      RepositorySuccess(
        PublicEventCatalog(
          events: const [],
          origin: PublicCatalogOrigin.remote,
          refreshedAt: fixtureRefreshAt,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No public events yet'), findsOneWidget);
  });

  testWidgets('shows recoverable error and retries successfully', (
    tester,
  ) async {
    final reader = _FakeReader(
      refreshes: [
        Future.value(
          const RepositoryFailure(
            UnknownRepositoryFailure(message: 'hidden endpoint detail'),
          ),
        ),
        Future.value(RepositorySuccess(publicCatalog())),
      ],
    );
    await _pumpEvents(tester, reader);
    await tester.pumpAndSettle();

    expect(find.text('Events are temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('hidden endpoint'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('VPC Demo Current'), findsOneWidget);
  });

  testWidgets('shows explicit unconfigured state', (tester) async {
    await _pumpEvents(tester, _FakeReader.unconfigured());
    await tester.pumpAndSettle();

    expect(find.text('Public events are not configured'), findsOneWidget);
    expect(find.textContaining('SUPABASE_'), findsNothing);
  });

  testWidgets('retains Android cached content after failed refresh', (
    tester,
  ) async {
    final reader = _FakeReader(
      cached: publicCatalog(origin: PublicCatalogOrigin.androidCache),
      refreshes: [
        Future.value(
          const RepositoryFailure(UnknownRepositoryFailure(message: 'offline')),
        ),
      ],
    );
    await _pumpEvents(tester, reader);
    await tester.pumpAndSettle();

    expect(find.text('VPC Demo Current'), findsOneWidget);
    expect(
      find.textContaining('Showing saved event information'),
      findsOneWidget,
    );
    expect(find.textContaining('could not be refreshed'), findsOneWidget);
  });

  testWidgets('unknown event identity fails visibly and safely', (
    tester,
  ) async {
    final reader = _FakeReader.success(publicCatalog());
    final app = await _pumpApp(tester, reader);
    app.router.go('/events/71000000-0000-4000-8000-000000000099');
    await tester.pumpAndSettle();

    expect(find.text('Event not found'), findsOneWidget);
    expect(find.text('View public events'), findsOneWidget);
  });

  testWidgets('uses phone navigation at narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(tester, _FakeReader.success(publicCatalog()));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('uses Web navigation rail at wide width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(tester, _FakeReader.success(publicCatalog()));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  test('coalesces duplicate refresh requests', () async {
    final completer = Completer<RepositoryResult<PublicEventCatalog>>();
    final reader = _FakeReader(refreshes: [completer.future]);
    final container = ProviderContainer(
      overrides: [publicEventReaderProvider.overrideWithValue(reader)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      publicEventsControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(publicEventsControllerProvider.notifier);
    final first = controller.refresh();
    final second = controller.refresh();
    expect(reader.refreshCalls, 1);
    completer.complete(RepositorySuccess(publicCatalog()));
    await Future.wait([first, second]);
    expect(reader.refreshCalls, 1);
  });

  test(
    'disposed stale request cannot update a replacement controller',
    () async {
      final first = Completer<RepositoryResult<PublicEventCatalog>>();
      final second = Completer<RepositoryResult<PublicEventCatalog>>();
      final reader = _FakeReader(refreshes: [first.future, second.future]);
      final firstContainer = ProviderContainer(
        overrides: [publicEventReaderProvider.overrideWithValue(reader)],
      );
      final firstSubscription = firstContainer.listen(
        publicEventsControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await _flushMicrotasks();
      firstSubscription.close();
      firstContainer.dispose();

      final replacement = ProviderContainer(
        overrides: [publicEventReaderProvider.overrideWithValue(reader)],
      );
      addTearDown(replacement.dispose);
      final replacementSubscription = replacement.listen(
        publicEventsControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(replacementSubscription.close);
      await _flushMicrotasks();
      expect(reader.refreshCalls, 2);

      second.complete(RepositorySuccess(publicCatalog()));
      await _flushMicrotasks();
      first.complete(
        const RepositoryFailure(
          UnknownRepositoryFailure(message: 'stale failure'),
        ),
      );
      await _flushMicrotasks();

      expect(
        replacement.read(publicEventsControllerProvider).phase,
        PublicEventsPhase.content,
      );
    },
  );
}

Future<void> _flushMicrotasks() async {
  for (var index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<VpcApp> _pumpApp(WidgetTester tester, PublicEventReader reader) async {
  final app = VpcApp(environment: AppEnvironment.test);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.web,
        ),
        publicEventReaderProvider.overrideWithValue(reader),
      ],
      child: app,
    ),
  );
  await tester.pump();
  return app;
}

Future<void> _pumpEvents(WidgetTester tester, PublicEventReader reader) async {
  final app = await _pumpApp(tester, reader);
  app.router.go('/events');
  await tester.pump();
  await tester.pump();
}

final class _FakeReader implements PublicEventReader {
  _FakeReader({this.cached, required this.refreshes});

  factory _FakeReader.success(PublicEventCatalog catalog) =>
      _FakeReader(refreshes: [Future.value(RepositorySuccess(catalog))]);

  factory _FakeReader.unconfigured() => _FakeReader(
    refreshes: [
      Future.value(
        const RepositoryFailure(
          PersistenceUnavailableFailure(message: 'not configured'),
        ),
      ),
    ],
  );

  final PublicEventCatalog? cached;
  final List<Future<RepositoryResult<PublicEventCatalog>>> refreshes;
  var refreshCalls = 0;

  @override
  Future<RepositoryResult<PublicEventCatalog?>> readCachedCatalog() async =>
      RepositorySuccess(cached);

  @override
  Future<RepositoryResult<PublicEventCatalog>> refreshCatalog() {
    final index = refreshCalls++;
    return refreshes[index.clamp(0, refreshes.length - 1)];
  }

  @override
  Future<RepositoryResult<PublicEventItem>> getEvent(EventId id) async {
    final item = cached?.eventById(id.value);
    return item == null
        ? RepositoryFailure(
            NotFoundFailure(entity: 'Event', identifier: id.value),
          )
        : RepositorySuccess(item);
  }
}
