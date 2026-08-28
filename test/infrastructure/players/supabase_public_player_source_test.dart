import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/players/player_directory_models.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/infrastructure/players/supabase_public_player_source.dart';

void main() {
  test(
    'maps only validated public player fields with stable pagination',
    () async {
      final gateway = _Gateway([row(hasMore: true)]);
      final result = await SupabasePublicPlayerSource(gateway)
          .fetchPage(PlayerDirectoryQuery());
      result.when(
        success: (page) {
          expect(page.entries.single.profile.displayName, 'VPC Sample Player');
          expect(page.hasMore, isTrue);
        },
        failure: (failure) => fail(failure.message),
      );
      expect(
        SupabasePublicPlayerRowsGateway.selectedColumns,
        isNot(contains('email')),
      );
      expect(
        SupabasePublicPlayerRowsGateway.selectedColumns,
        isNot(contains('account')),
      );
    },
  );

  test('invalid UUID fails explicitly', () async {
    final result = await SupabasePublicPlayerSource(_Gateway([row(id: 'bad')]))
        .fetchPage(PlayerDirectoryQuery());
    result.when(
      success: (_) => fail('Expected failure'),
      failure: (failure) => expect(failure, isA<ValidationFailure>()),
    );
  });

  test('invalid timestamp fails explicitly', () async {
    final result = await SupabasePublicPlayerSource(
      _Gateway([row(createdAt: '2026-08-29 00:00:00')]),
    ).fetchPage(PlayerDirectoryQuery());
    result.when(
      success: (_) => fail('Expected failure'),
      failure: (failure) => expect(failure, isA<ValidationFailure>()),
    );
  });

  test('invalid normalized ordering data fails explicitly', () async {
    final bad = row()..['normalized_name'] = 'different';
    final result = await SupabasePublicPlayerSource(_Gateway([bad]))
        .fetchPage(PlayerDirectoryQuery());
    result.when(
      success: (_) => fail('Expected failure'),
      failure: (failure) => expect(failure, isA<ValidationFailure>()),
    );
  });

  test('infrastructure details are redacted', () async {
    final result = await SupabasePublicPlayerSource(_ThrowingGateway())
        .fetchPage(PlayerDirectoryQuery());
    result.when(
      success: (_) => fail('Expected failure'),
      failure: (failure) {
        expect(failure, isA<UnknownRepositoryFailure>());
        expect(failure.message, isNot(contains('secret-value')));
      },
    );
  });

  test('missing public profile returns typed not found', () async {
    final result = await SupabasePublicPlayerSource(_Gateway(const []))
        .fetchById(PlayerId(playerId));
    result.when(
      success: (_) => fail('Expected failure'),
      failure: (failure) => expect(failure, isA<NotFoundFailure>()),
    );
  });
}

const playerId = '82000000-0000-4000-8000-000000000001';

Map<String, Object?> row({
  String id = playerId,
  String createdAt = '2026-08-29T00:00:00Z',
  bool hasMore = false,
}) => {
  'id': id,
  'display_name': 'VPC Sample Player',
  'created_at': createdAt,
  'updated_at': '2026-08-29T00:00:00Z',
  'version': 0,
  'deleted_at': null,
  'normalized_name': 'vpc sample player',
  'has_more': hasMore,
};

class _Gateway implements PublicPlayerRowsGateway {
  _Gateway(this.rows);
  final List<Map<String, Object?>> rows;

  @override
  Future<Map<String, Object?>?> getById(PlayerId id) async =>
      rows.isEmpty ? null : rows.first;

  @override
  Future<List<Map<String, Object?>>> search(PlayerDirectoryQuery query) async =>
      rows;
}

class _ThrowingGateway implements PublicPlayerRowsGateway {
  @override
  Future<Map<String, Object?>?> getById(PlayerId id) =>
      throw Exception('secret-value');

  @override
  Future<List<Map<String, Object?>>> search(PlayerDirectoryQuery query) =>
      throw Exception('secret-value');
}
