import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/players/player_directory_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../infrastructure/players/player_directory_providers.dart';

enum PlayerDirectoryPhase {
  loading,
  content,
  empty,
  noResults,
  error,
  unconfigured,
}

final class PlayerDirectoryViewState {
  const PlayerDirectoryViewState({
    required this.phase,
    this.entries = const [],
    this.query = '',
    this.origin,
    this.hasMore = false,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.message,
  });

  const PlayerDirectoryViewState.loading()
    : this(phase: PlayerDirectoryPhase.loading);

  final PlayerDirectoryPhase phase;
  final List<PlayerDirectoryEntry> entries;
  final String query;
  final PlayerDirectoryOrigin? origin;
  final bool hasMore;
  final bool isRefreshing;
  final bool isLoadingMore;
  final String? message;

  bool get isCached => origin == PlayerDirectoryOrigin.androidLocal;

  PlayerDirectoryViewState copyWith({
    PlayerDirectoryPhase? phase,
    List<PlayerDirectoryEntry>? entries,
    String? query,
    PlayerDirectoryOrigin? origin,
    bool? hasMore,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? message,
    bool clearMessage = false,
  }) => PlayerDirectoryViewState(
    phase: phase ?? this.phase,
    entries: entries ?? this.entries,
    query: query ?? this.query,
    origin: origin ?? this.origin,
    hasMore: hasMore ?? this.hasMore,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    message: clearMessage ? null : message ?? this.message,
  );
}

final playerDirectoryControllerProvider =
    NotifierProvider<PlayerDirectoryController, PlayerDirectoryViewState>(
      PlayerDirectoryController.new,
    );

final class PlayerDirectoryController
    extends Notifier<PlayerDirectoryViewState> {
  Future<void>? _activeRefresh;
  var _request = 0;
  var _disposed = false;

  @override
  PlayerDirectoryViewState build() {
    ref.watch(playerDirectoryReaderProvider);
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(_load));
    return const PlayerDirectoryViewState.loading();
  }

  Future<void> _load() async {
    final request = ++_request;
    final result = await ref
        .read(playerDirectoryReaderProvider)
        .readPage(PlayerDirectoryQuery(searchText: state.query));
    if (_disposed || request != _request) return;
    result.when(success: _acceptPage, failure: (_) {});
    await refresh();
  }

  Future<void> setQuery(String value) async {
    final normalized = normalizePlayerName(value);
    if (normalized == state.query) return;
    _request++;
    _activeRefresh = null;
    state = PlayerDirectoryViewState(
      phase: PlayerDirectoryPhase.loading,
      query: normalized,
    );
    await _load();
  }

  Future<void> refresh() {
    final active = _activeRefresh;
    if (active != null) return active;
    final operation = _refresh();
    _activeRefresh = operation;
    return operation.whenComplete(() {
      if (identical(_activeRefresh, operation)) _activeRefresh = null;
    });
  }

  Future<void> _refresh() async {
    final request = ++_request;
    state = state.entries.isEmpty
        ? PlayerDirectoryViewState(
            phase: PlayerDirectoryPhase.loading,
            query: state.query,
          )
        : state.copyWith(isRefreshing: true, clearMessage: true);
    final result = await ref
        .read(playerDirectoryReaderProvider)
        .refreshPage(PlayerDirectoryQuery(searchText: state.query));
    if (_disposed || request != _request) return;
    result.when(
      success: _acceptPage,
      failure: (failure) {
        if (state.entries.isNotEmpty) {
          state = state.copyWith(
            isRefreshing: false,
            message: 'Latest player data is unavailable. Showing saved data.',
          );
          return;
        }
        state = PlayerDirectoryViewState(
          phase: failure is PersistenceUnavailableFailure
              ? PlayerDirectoryPhase.unconfigured
              : PlayerDirectoryPhase.error,
          query: state.query,
          message: failure is PersistenceUnavailableFailure
              ? 'Public player data is not configured for this build.'
              : 'Players could not be loaded. Please try again.',
        );
      },
    );
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.entries.isEmpty) return;
    final request = ++_request;
    state = state.copyWith(isLoadingMore: true, clearMessage: true);
    final last = state.entries.last.profile;
    final result = await ref
        .read(playerDirectoryReaderProvider)
        .readPage(
          PlayerDirectoryQuery(
            searchText: state.query,
            after: PlayerDirectoryCursor(
              normalizedName: last.displayName,
              id: last.id,
            ),
          ),
        );
    if (_disposed || request != _request) return;
    result.when(
      success: (page) {
        state = state.copyWith(
          entries: [...state.entries, ...page.entries],
          hasMore: page.hasMore,
          origin: page.origin,
          isLoadingMore: false,
        );
      },
      failure: (_) {
        state = state.copyWith(
          isLoadingMore: false,
          message: 'More players could not be loaded. Please try again.',
        );
      },
    );
  }

  void _acceptPage(PlayerDirectoryPage page) {
    state = PlayerDirectoryViewState(
      phase: page.entries.isEmpty
          ? (state.query.isEmpty
                ? PlayerDirectoryPhase.empty
                : PlayerDirectoryPhase.noResults)
          : PlayerDirectoryPhase.content,
      entries: page.entries,
      query: state.query,
      origin: page.origin,
      hasMore: page.hasMore,
    );
  }
}
