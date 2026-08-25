import 'domain_failure.dart';

/// A provider-neutral repository outcome.
sealed class RepositoryResult<T> {
  const RepositoryResult();

  bool get isSuccess;

  R when<R>({
    required R Function(T value) success,
    required R Function(DomainFailure failure) failure,
  });
}

final class RepositorySuccess<T> extends RepositoryResult<T> {
  const RepositorySuccess(this.value);

  final T value;

  @override
  bool get isSuccess => true;

  @override
  R when<R>({
    required R Function(T value) success,
    required R Function(DomainFailure failure) failure,
  }) => success(value);
}

final class RepositoryFailure<T> extends RepositoryResult<T> {
  const RepositoryFailure(this.failure);

  final DomainFailure failure;

  @override
  bool get isSuccess => false;

  @override
  R when<R>({
    required R Function(T value) success,
    required R Function(DomainFailure failure) failure,
  }) => failure(this.failure);
}
