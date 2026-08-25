import '../common/domain_validation.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';

/// A reusable community player identity independent of event participation.
final class PermanentPlayer {
  factory PermanentPlayer({
    required PlayerId id,
    required String displayName,
    required RecordMetadata metadata,
    AccountId? accountId,
  }) => PermanentPlayer._(
    id: id,
    displayName: requireNonBlank(displayName, field: 'displayName'),
    metadata: metadata,
    accountId: accountId,
  );

  const PermanentPlayer._({
    required this.id,
    required this.displayName,
    required this.metadata,
    required this.accountId,
  });

  final PlayerId id;
  final String displayName;
  final AccountId? accountId;
  final RecordMetadata metadata;
}
