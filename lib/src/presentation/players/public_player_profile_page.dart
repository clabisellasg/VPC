import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/accounts/account_models.dart';
import '../../application/players/player_directory_models.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../infrastructure/players/player_directory_providers.dart';
import '../accounts/account_controller.dart';

final publicPlayerProfileProvider = FutureProvider.autoDispose
    .family<RepositoryResult<PlayerDirectoryEntry>, PlayerId>(
      (ref, id) => ref.watch(playerDirectoryReaderProvider).getById(id),
    );

class PublicPlayerProfilePage extends ConsumerWidget {
  const PublicPlayerProfilePage({required this.playerId, super.key});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    PlayerId id;
    try {
      id = PlayerId(playerId);
    } on Exception {
      return const _MissingPlayer();
    }
    final result = ref.watch(publicPlayerProfileProvider(id));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        result.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const _MissingPlayer(),
          data: (repositoryResult) => repositoryResult.when(
            success: (entry) => _Profile(entry: entry),
            failure: (_) => const _MissingPlayer(),
          ),
        ),
      ],
    );
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({required this.entry});

  final PlayerDirectoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organizer =
        ref.watch(accountControllerProvider).snapshot?.authorization ==
        AuthorizationState.organizer;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.account_circle_outlined, size: 56),
            const SizedBox(height: 12),
            Text(
              entry.profile.displayName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Permanent community player record',
              semanticsLabel: 'Permanent community player profile',
            ),
            if (organizer &&
                entry.syncState != PlayerSyncPresentation.synchronized) ...[
              const Divider(height: 32),
              Text(_organizerSyncMessage(entry.syncState)),
            ],
          ],
        ),
      ),
    );
  }
}

String _organizerSyncMessage(PlayerSyncPresentation state) => switch (state) {
  PlayerSyncPresentation.synchronized => 'Synchronized',
  PlayerSyncPresentation.pending => 'Pending cloud synchronization.',
  PlayerSyncPresentation.authorizationBlocked =>
    'Waiting for confirmed organizer authorization.',
  PlayerSyncPresentation.failed => 'Synchronization needs attention.',
  PlayerSyncPresentation.conflicted =>
    'A synchronization conflict is preserved and has not been resolved.',
};

class _MissingPlayer extends StatelessWidget {
  const _MissingPlayer();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.person_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            'Player not available',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'This permanent player record is missing or no longer public.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
