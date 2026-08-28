import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/public_events/public_event_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../infrastructure/public_events/public_event_providers.dart';

enum PublicEventsPhase { loading, content, empty, error, unconfigured }

final class PublicEventsViewState {
  const PublicEventsViewState({
    required this.phase,
    this.catalog,
    this.isRefreshing = false,
    this.message,
  });

  const PublicEventsViewState.loading()
    : this(phase: PublicEventsPhase.loading);

  final PublicEventsPhase phase;
  final PublicEventCatalog? catalog;
  final bool isRefreshing;
  final String? message;

  bool get isCached => catalog?.origin == PublicCatalogOrigin.androidCache;

  PublicEventsViewState copyWith({
    PublicEventsPhase? phase,
    PublicEventCatalog? catalog,
    bool? isRefreshing,
    String? message,
    bool clearMessage = false,
  }) => PublicEventsViewState(
    phase: phase ?? this.phase,
    catalog: catalog ?? this.catalog,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    message: clearMessage ? null : message ?? this.message,
  );
}

final publicEventsControllerProvider =
    NotifierProvider<PublicEventsController, PublicEventsViewState>(
      PublicEventsController.new,
    );

final class PublicEventsController extends Notifier<PublicEventsViewState> {
  Future<void>? _activeRefresh;
  var _requestSequence = 0;
  var _disposed = false;

  @override
  PublicEventsViewState build() {
    ref.watch(publicEventReaderProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>(_load));
    return const PublicEventsViewState.loading();
  }

  Future<void> _load() async {
    final reader = ref.read(publicEventReaderProvider);
    final cached = await reader.readCachedCatalog();
    if (_disposed) {
      return;
    }
    cached.when(
      success: (catalog) {
        if (catalog != null && catalog.events.isNotEmpty) {
          state = PublicEventsViewState(
            phase: PublicEventsPhase.content,
            catalog: catalog,
          );
        }
      },
      failure: (_) {},
    );
    await refresh();
  }

  Future<void> refresh() {
    final existing = _activeRefresh;
    if (existing != null) {
      return existing;
    }
    final operation = _performRefresh();
    _activeRefresh = operation;
    return operation.whenComplete(() {
      if (identical(_activeRefresh, operation)) {
        _activeRefresh = null;
      }
    });
  }

  Future<void> _performRefresh() async {
    final request = ++_requestSequence;
    final hasContent = state.catalog != null;
    state = hasContent
        ? state.copyWith(isRefreshing: true, clearMessage: true)
        : const PublicEventsViewState.loading();
    final result = await ref.read(publicEventReaderProvider).refreshCatalog();
    if (_disposed || request != _requestSequence) {
      return;
    }
    result.when(
      success: (catalog) {
        state = PublicEventsViewState(
          phase: catalog.events.isEmpty
              ? PublicEventsPhase.empty
              : PublicEventsPhase.content,
          catalog: catalog,
        );
      },
      failure: (failure) {
        final existingCatalog = state.catalog;
        if (existingCatalog != null && existingCatalog.events.isNotEmpty) {
          state = state.copyWith(
            isRefreshing: false,
            message: _messageFor(failure),
          );
          return;
        }
        state = PublicEventsViewState(
          phase: failure is PersistenceUnavailableFailure
              ? PublicEventsPhase.unconfigured
              : PublicEventsPhase.error,
          message: _messageFor(failure),
        );
      },
    );
  }

  String _messageFor(DomainFailure failure) =>
      failure is PersistenceUnavailableFailure
      ? 'Public event data is not configured for this build.'
      : 'Public events could not be refreshed. Please try again.';
}
