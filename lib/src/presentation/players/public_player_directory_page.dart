import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/account_models.dart';
import '../../application/players/player_directory_models.dart';
import '../accounts/account_controller.dart';
import 'player_directory_controller.dart';

class PublicPlayerDirectoryPage extends ConsumerStatefulWidget {
  const PublicPlayerDirectoryPage({super.key});

  @override
  ConsumerState<PublicPlayerDirectoryPage> createState() =>
      _PublicPlayerDirectoryPageState();
}

class _PublicPlayerDirectoryPageState
    extends ConsumerState<PublicPlayerDirectoryPage> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerDirectoryControllerProvider);
    final organizer =
        ref.watch(accountControllerProvider).snapshot?.authorization ==
        AuthorizationState.organizer;
    return RefreshIndicator(
      onRefresh: ref.read(playerDirectoryControllerProvider.notifier).refresh,
      child: ListView(
        key: const PageStorageKey('player-directory'),
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Community players',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh players',
                onPressed: state.isRefreshing
                    ? null
                    : ref
                          .read(playerDirectoryControllerProvider.notifier)
                          .refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Permanent community records are reused across events and history.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Search players',
              hintText: 'Enter a display name',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                ref
                    .read(playerDirectoryControllerProvider.notifier)
                    .setQuery(value);
              });
            },
            onSubmitted: (value) => ref
                .read(playerDirectoryControllerProvider.notifier)
                .setQuery(value),
          ),
          if (organizer) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => context.go('/organizer/players/new'),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add permanent player'),
              ),
            ),
          ],
          if (state.isCached) ...[
            const SizedBox(height: 12),
            const _StatusBanner(
              icon: Icons.offline_bolt_outlined,
              text: 'Showing saved Android data. Refresh checks for updates.',
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 12),
            _StatusBanner(icon: Icons.info_outline, text: state.message!),
          ],
          const SizedBox(height: 16),
          switch (state.phase) {
            PlayerDirectoryPhase.loading => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            PlayerDirectoryPhase.empty => const _EmptyPlayers(
              title: 'No community players yet',
              body: 'The permanent player directory is currently empty.',
            ),
            PlayerDirectoryPhase.noResults => const _EmptyPlayers(
              title: 'No matching players',
              body: 'Try a shorter or differently spaced display name.',
            ),
            PlayerDirectoryPhase.error => _RetryState(
              title: 'Players unavailable',
              message: state.message ?? 'Please try again.',
            ),
            PlayerDirectoryPhase.unconfigured => _RetryState(
              title: 'Player data is not configured',
              message: state.message ?? 'Use a configured development build.',
            ),
            PlayerDirectoryPhase.content => _PlayerResults(
              state: state,
              showSyncState: organizer,
            ),
          },
        ],
      ),
    );
  }
}

class _PlayerResults extends ConsumerWidget {
  const _PlayerResults({required this.state, required this.showSyncState});

  final PlayerDirectoryViewState state;
  final bool showSyncState;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      for (final entry in state.entries)
        Card(
          child: ListTile(
            minVerticalPadding: 12,
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(entry.profile.displayName),
            subtitle: !showSyncState || _syncLabel(entry.syncState) == null
                ? null
                : Text(_syncLabel(entry.syncState)!),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/players/${entry.profile.id.value}'),
          ),
        ),
      if (state.hasMore || state.isLoadingMore)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton(
            onPressed: state.isLoadingMore
                ? null
                : ref.read(playerDirectoryControllerProvider.notifier).loadMore,
            child: state.isLoadingMore
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Load more'),
          ),
        ),
    ],
  );
}

String? _syncLabel(PlayerSyncPresentation state) => switch (state) {
  PlayerSyncPresentation.synchronized => null,
  PlayerSyncPresentation.pending => 'Pending cloud synchronization',
  PlayerSyncPresentation.authorizationBlocked =>
    'Waiting for confirmed organizer authorization',
  PlayerSyncPresentation.failed => 'Synchronization needs attention',
  PlayerSyncPresentation.conflicted =>
    'Synchronization conflict preserved for review',
};

class _RetryState extends ConsumerWidget {
  const _RetryState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: ref
                .read(playerDirectoryControllerProvider.notifier)
                .refresh,
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyPlayers extends StatelessWidget {
  const _EmptyPlayers({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        const Icon(Icons.people_outline, size: 48),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(leading: Icon(icon), title: Text(text)),
  );
}
