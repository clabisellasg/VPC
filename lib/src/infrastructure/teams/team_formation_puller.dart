import '../../domain/common/domain_failure.dart';
import 'drift_team_formation_store.dart';
import 'team_pull_models.dart';

/// Reads the durable global team cursor again on every synchronization pass.
final class TeamFormationPuller {
  const TeamFormationPuller({required this.local, required this.remote});
  final DriftTeamFormationStore local;
  final TeamPullSource remote;

  Future<void> pull() async {
    var cursor = await local.readPullCheckpoint();
    while (true) {
      final page = await remote.pullTeams(cursor);
      if (page.isEmpty) return;
      if (page.length > 50 ||
          (cursor != null && page.first.cursor.compareTo(cursor) <= 0)) {
        throw const ValidationFailure(
          field: 'teamPull',
          message: 'Cloud team pull cursor is invalid.',
        );
      }
      if (!await local.reconcilePullPage(page)) return;
      cursor = page.last.cursor;
      if (page.length < 50) return;
    }
  }
}
