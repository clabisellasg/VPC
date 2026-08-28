import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/players/player_directory_models.dart';
import '../../infrastructure/players/player_directory_providers.dart';
import 'player_directory_controller.dart';

enum PlayerCreationPhase { idle, submitting, duplicateWarning, created, error }

final class PlayerCreationViewState {
  const PlayerCreationViewState({
    required this.phase,
    this.requestedName = '',
    this.candidates = const [],
    this.created,
    this.message,
  });

  const PlayerCreationViewState.idle() : this(phase: PlayerCreationPhase.idle);

  final PlayerCreationPhase phase;
  final String requestedName;
  final List<PublicPlayerProfile> candidates;
  final CreatedPlayer? created;
  final String? message;
}

final playerCreationControllerProvider =
    NotifierProvider<PlayerCreationController, PlayerCreationViewState>(
      PlayerCreationController.new,
    );

final class PlayerCreationController extends Notifier<PlayerCreationViewState> {
  @override
  PlayerCreationViewState build() => const PlayerCreationViewState.idle();

  Future<void> submit(String name, {bool acknowledgeDuplicate = false}) async {
    if (state.phase == PlayerCreationPhase.submitting) return;
    state = PlayerCreationViewState(
      phase: PlayerCreationPhase.submitting,
      requestedName: name,
    );
    final result = await ref
        .read(playerCreationServiceProvider)
        .create(
          requestedDisplayName: name,
          duplicateAcknowledged: acknowledgeDuplicate,
        );
    switch (result) {
      case PlayerCreated(:final value):
        state = PlayerCreationViewState(
          phase: PlayerCreationPhase.created,
          requestedName: name,
          created: value,
        );
        ref.invalidate(playerDirectoryControllerProvider);
      case PlayerDuplicateWarning(:final candidates):
        state = PlayerCreationViewState(
          phase: PlayerCreationPhase.duplicateWarning,
          requestedName: name,
          candidates: candidates,
        );
      case PlayerCreationFailed(:final failure):
        state = PlayerCreationViewState(
          phase: PlayerCreationPhase.error,
          requestedName: name,
          message: failure.message,
        );
    }
  }

  void reset() => state = const PlayerCreationViewState.idle();
}
