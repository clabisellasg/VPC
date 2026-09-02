import 'dart:async';

import '../../application/accounts/account_models.dart';
import '../accounts/account_controller.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/events/event_setup_contracts.dart';
import '../../application/events/event_setup_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../infrastructure/events/event_setup_providers.dart';
import '../public_events/public_events_controller.dart';

enum OrganizerEventPhase { loading, content, unavailable, working }

final class OrganizerEventState {
  const OrganizerEventState({
    required this.phase,
    this.setups = const [],
    this.syncStatuses = const {},
    this.message,
  });
  final OrganizerEventPhase phase;
  final List<EventSetup> setups;
  final Map<EventId, EventSetupSyncStatus> syncStatuses;
  final String? message;
}

final organizerEventControllerProvider =
    NotifierProvider<OrganizerEventController, OrganizerEventState>(
      OrganizerEventController.new,
    );

final class OrganizerEventController extends Notifier<OrganizerEventState> {
  bool _disposed = false;
  bool _synchronizing = false;

  @override
  OrganizerEventState build() {
    ref.onDispose(() => _disposed = true);
    Future<void>.microtask(refresh);
    return const OrganizerEventState(phase: OrganizerEventPhase.loading);
  }

  Future<void> refresh() async {
    final store = ref.read(eventSetupStoreProvider);
    if (store == null) {
      state = const OrganizerEventState(
        phase: OrganizerEventPhase.unavailable,
        message: 'Event setup is not configured.',
      );
      return;
    }
    await _load(store);
    _synchronizeInBackground(store);
  }

  Future<void> _load(EventSetupStore store) async {
    final result = await store.listSetups();
    if (_disposed) return;
    await result.when(
      success: (setups) async {
        final statuses = <EventId, EventSetupSyncStatus>{};
        for (final setup in setups) {
          final status = await store.syncStatus(setup.event.id);
          if (status case RepositorySuccess(:final value)) {
            statuses[setup.event.id] = value;
          }
        }
        if (_disposed) return;
        state = OrganizerEventState(
          phase: OrganizerEventPhase.content,
          setups: setups,
          syncStatuses: Map.unmodifiable(statuses),
        );
      },
      failure: (failure) async {
        state = OrganizerEventState(
          phase: OrganizerEventPhase.unavailable,
          message: failure.message,
        );
      },
    );
  }

  void _synchronizeInBackground(EventSetupStore store) {
    final synchronizer = ref.read(eventSetupSynchronizerProvider);
    if (synchronizer == null || _synchronizing) return;
    _synchronizing = true;
    unawaited(() async {
      try {
        await synchronizer.synchronize();
        if (!_disposed) await _load(store);
      } catch (_) {
        if (!_disposed) {
          state = OrganizerEventState(
            phase: OrganizerEventPhase.content,
            setups: state.setups,
            syncStatuses: state.syncStatuses,
            message: 'Synchronization is temporarily unavailable.',
          );
        }
      } finally {
        _synchronizing = false;
      }
    }());
  }

  Future<EventSetupMutationResult> create({
    required EventType type,
    required String name,
    required DateTime scheduledAt,
    required String venue,
    required List<String> divisions,
  }) async {
    state = OrganizerEventState(
      phase: OrganizerEventPhase.working,
      setups: state.setups,
      syncStatuses: state.syncStatuses,
    );
    final service = ref.read(eventSetupServiceProvider);
    final result = type == EventType.casual
        ? await service.createQuickCasual(
            name: name,
            scheduledAt: scheduledAt,
            venue: venue,
          )
        : await service.createFormal(
            name: name,
            scheduledAt: scheduledAt,
            venue: venue,
            divisionNames: divisions,
          );
    await refresh();
    await _refreshPublicEventsAfterSuccess(result);
    return result;
  }

  Future<EventSetupMutationResult> update({
    required EventSetup current,
    required String name,
    required DateTime scheduledAt,
    required String venue,
    required Iterable<String> divisionNames,
  }) async {
    final result = await ref
        .read(eventSetupServiceProvider)
        .updateUpcoming(
          current: current,
          name: name,
          scheduledAt: scheduledAt,
          venue: venue,
          divisionNames: divisionNames,
        );
    await refresh();
    await _refreshPublicEventsAfterSuccess(result);
    return result;
  }

  Future<EventSetupMutationResult> advance(EventSetup setup) async {
    final result = await ref.read(eventSetupServiceProvider).advance(setup);
    await refresh();
    await _refreshPublicEventsAfterSuccess(result);
    return result;
  }

  Future<EventSetupMutationResult> selectFormat(
    EventSetup setup,
    DivisionId divisionId,
    TournamentFormat format,
  ) async {
    final result = await ref
        .read(eventSetupServiceProvider)
        .selectFormat(
          current: setup,
          divisionId: divisionId,
          format: format,
          authorization:
              ref.read(accountControllerProvider).snapshot?.authorization ??
              AuthorizationState.guest,
        );
    await refresh();
    await _refreshPublicEventsAfterSuccess(result);
    return result;
  }

  Future<void> _refreshPublicEventsAfterSuccess(
    EventSetupMutationResult result,
  ) async {
    if (result is EventSetupSaved) {
      final refresh = ref
          .read(publicEventsControllerProvider.notifier)
          .refresh();
      if (ref.read(eventSetupSynchronizerProvider) == null) {
        await refresh;
      } else {
        unawaited(refresh);
      }
    }
  }
}
