import '../common/domain_failure.dart';
import '../common/entity_id.dart';

/// V1: one game to 11, win by two, stopping at the first winning score.
final class ValidatedScore {
  factory ValidatedScore(int sideOne, int sideTwo) {
    final high = sideOne > sideTwo ? sideOne : sideTwo;
    final low = sideOne < sideTwo ? sideOne : sideTwo;
    if (low < 0 ||
        !((high == 11 && low <= 9) || (low >= 10 && high - low == 2))) {
      throw const ValidationFailure(
        field: 'score',
        message: 'Use one game to 11, win by two, with no score cap or draws.',
      );
    }
    return ValidatedScore._(sideOne, sideTwo);
  }
  const ValidatedScore._(this.sideOne, this.sideTwo);
  final int sideOne;
  final int sideTwo;
  bool get sideOneWins => sideOne > sideTwo;
  @override
  bool operator ==(Object other) =>
      other is ValidatedScore &&
      sideOne == other.sideOne &&
      sideTwo == other.sideTwo;
  @override
  int get hashCode => Object.hash(sideOne, sideTwo);
}

final class MatchResult {
  MatchResult({
    required this.sideOne,
    required this.sideTwo,
    required this.score,
  }) {
    if (sideOne == sideTwo) {
      throw const ValidationFailure(
        field: 'teams',
        message: 'A team cannot play itself.',
      );
    }
  }
  final TeamId sideOne;
  final TeamId sideTwo;
  final ValidatedScore score;
  TeamId get winner => score.sideOneWins ? sideOne : sideTwo;
}
