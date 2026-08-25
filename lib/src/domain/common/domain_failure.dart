/// An expected, platform-independent failure at a domain or repository boundary.
sealed class DomainFailure implements Exception {
  const DomainFailure({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => '$runtimeType($code): $message';
}

final class ValidationFailure extends DomainFailure {
  const ValidationFailure({required this.field, required super.message})
    : super(code: 'validation');

  final String field;
}

final class InvalidStateTransitionFailure extends DomainFailure {
  const InvalidStateTransitionFailure({
    required this.entity,
    required this.from,
    required this.to,
  }) : super(
         code: 'invalid_state_transition',
         message: 'Cannot transition $entity from $from to $to.',
       );

  final String entity;
  final String from;
  final String to;
}

final class NotFoundFailure extends DomainFailure {
  const NotFoundFailure({required this.entity, required this.identifier})
    : super(code: 'not_found', message: '$entity $identifier was not found.');

  final String entity;
  final String identifier;
}

final class ConflictFailure extends DomainFailure {
  const ConflictFailure({
    required super.message,
    this.expectedVersion,
    this.actualVersion,
  }) : super(code: 'conflict');

  final int? expectedVersion;
  final int? actualVersion;
}

final class PersistenceUnavailableFailure extends DomainFailure {
  const PersistenceUnavailableFailure({required super.message})
    : super(code: 'persistence_unavailable');
}

final class UnauthorizedFailure extends DomainFailure {
  const UnauthorizedFailure({required super.message})
    : super(code: 'unauthorized');
}

final class UnknownRepositoryFailure extends DomainFailure {
  const UnknownRepositoryFailure({required super.message})
    : super(code: 'unknown_repository_failure');
}
