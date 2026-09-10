import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/supabase_configuration.dart';

/// A minimal, read-only PostgREST transport for public Web surfaces.
///
/// Some iOS WebKit configurations reject cross-origin requests carrying the
/// otherwise standard `apikey` or `x-client-info` headers. The Supabase
/// publishable key is therefore supplied as a query parameter for these
/// RLS-approved GET requests. It is public client configuration, never a
/// service-role credential, and is never included in logs or errors.
final class PublicSupabaseRestClient {
  PublicSupabaseRestClient(
    this._baseUri,
    this._publishableKey, {
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  factory PublicSupabaseRestClient.fromConfiguration(
    SupabaseConfiguration configuration, {
    http.Client? httpClient,
  }) {
    if (!configuration.isConfigured) {
      throw const FormatException('Supabase configuration is unavailable.');
    }
    return PublicSupabaseRestClient(
      Uri.parse(configuration.url!),
      configuration.publishableKey!,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final String _publishableKey;
  final http.Client _httpClient;
  final bool _ownsClient;

  Future<List<Map<String, Object?>>> select(
    String table,
    Map<String, String> query,
  ) async {
    final value = await _get('rest/v1/$table', query);
    if (value is! List) {
      throw const PublicRestProtocolException();
    }
    return value
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }

  Future<Object?> rpc(String function, Map<String, Object?> parameters) {
    return _get(
      'rest/v1/rpc/$function',
      parameters.map(
        (key, value) => MapEntry(key, value == null ? null : '$value'),
      )..removeWhere((key, value) => value == null),
    );
  }

  Future<Object?> _get(String path, Map<String, String?> query) async {
    final uri = _baseUri
        .resolve(path)
        .replace(
          queryParameters: <String, String>{
            'apikey': _publishableKey,
            for (final entry in query.entries)
              if (entry.value != null) entry.key: entry.value!,
          },
        );
    final response = await _httpClient.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PublicRestRejectedException(response.statusCode);
    }
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const PublicRestProtocolException();
    }
  }

  void close() {
    if (_ownsClient) _httpClient.close();
  }
}

final class PublicRestRejectedException implements Exception {
  const PublicRestRejectedException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'Public read rejected (HTTP $statusCode).';
}

final class PublicRestProtocolException implements Exception {
  const PublicRestProtocolException();

  @override
  String toString() => 'Public read response was invalid.';
}
