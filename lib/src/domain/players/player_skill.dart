import '../common/domain_failure.dart';

/// Organizer-maintained community skill used only as a formation aid.
final class PlayerSkill {
  const PlayerSkill._(this.value);

  factory PlayerSkill(int value) {
    if (value < 1 || value > 5) {
      throw const ValidationFailure(
        field: 'skillLevel',
        message: 'Player skill must be between 1 and 5.',
      );
    }
    return PlayerSkill._(value);
  }

  final int value;

  String get label => switch (value) {
    1 => 'Beginner',
    2 => 'Developing',
    3 => 'Intermediate',
    4 => 'Advanced',
    5 => 'Competitive',
    _ => throw StateError('Invalid validated player skill.'),
  };

  @override
  bool operator ==(Object other) =>
      other is PlayerSkill && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

String playerSkillLabel(PlayerSkill? skill) => skill?.label ?? 'Unrated';
