import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/permanent_player.dart';
import '../../domain/players/player_skill.dart';

abstract interface class PlayerSkillEditor {
  Future<RepositoryResult<PermanentPlayer>> update(
    PlayerId id,
    PlayerSkill? skill,
  );
}
