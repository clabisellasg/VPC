import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vpc/src/core/supabase/public_supabase_rest_client.dart';

void main() {
  test('public reads use GET with query key and no blocked headers', () async {
    late http.Request captured;
    final transport = MockClient((request) async {
      captured = request;
      return http.Response('[{"id":"player-1"}]', 200);
    });
    final client = PublicSupabaseRestClient(
      Uri.parse('https://project.supabase.co'),
      'public-test-key',
      httpClient: transport,
    );

    final rows = await client.select('players', const {
      'select': 'id,display_name',
      'deleted_at': 'is.null',
    });

    expect(rows.single['id'], 'player-1');
    expect(captured.method, 'GET');
    expect(captured.url.path, '/rest/v1/players');
    expect(captured.url.queryParameters['apikey'], 'public-test-key');
    expect(
      captured.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains(anyOf('apikey', 'authorization', 'x-client-info'))),
    );
  });

  test('public RPC omits null parameters and decodes JSON', () async {
    late http.Request captured;
    final client = PublicSupabaseRestClient(
      Uri.parse('https://project.supabase.co'),
      'public-test-key',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"matches":[]}', 200);
      }),
    );

    final value = await client.rpc('read_public_player_history', {
      'p_player_id': 'player-1',
      'p_cursor': null,
    });

    expect((value as Map)['matches'], isEmpty);
    expect(captured.url.path, '/rest/v1/rpc/read_public_player_history');
    expect(captured.url.queryParameters, isNot(contains('p_cursor')));
  });

  test('rejections do not expose key or response body', () async {
    final client = PublicSupabaseRestClient(
      Uri.parse('https://project.supabase.co'),
      'public-test-key',
      httpClient: MockClient(
        (_) async => http.Response('private provider detail', 401),
      ),
    );

    Object? error;
    try {
      await client.select('players', const {'select': 'id'});
    } catch (caught) {
      error = caught;
    }

    expect(error, isA<PublicRestRejectedException>());
    expect('$error', isNot(contains('public-test-key')));
    expect('$error', isNot(contains('private provider detail')));
  });
}
