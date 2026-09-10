import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/common/domain_failure.dart';
import '../../core/supabase/public_supabase_rest_client.dart';

const _requestTimeout = Duration(seconds: 8);
const _retryDelays = <Duration>[
  Duration(milliseconds: 500),
  Duration(seconds: 2),
];

/// Retries browser transport failures without retrying an authoritative API
/// rejection. The bounded delays keep an iOS foreground recovery under 20s.
Future<T> runPublicSupabaseRequest<T>(Future<T> Function() request) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await request().timeout(_requestTimeout);
    } on PostgrestException {
      rethrow;
    } on AuthException {
      rethrow;
    } on PublicRestRejectedException {
      rethrow;
    } on PublicRestProtocolException {
      rethrow;
    } on Exception {
      if (attempt >= _retryDelays.length) rethrow;
      await Future<void>.delayed(_retryDelays[attempt]);
    }
  }
}

RemoteReadFailure safePublicReadFailure(Object error, String resource) {
  if (error is TimeoutException) {
    return RemoteReadFailure(
      code: 'remote_timeout',
      message: '$resource timed out. Diagnostic: NET-TIMEOUT.',
    );
  }
  if (error is AuthException) {
    return RemoteReadFailure(
      code: 'remote_authorization',
      message: '$resource was rejected. Diagnostic: API-AUTH.',
    );
  }
  if (error is PostgrestException) {
    return RemoteReadFailure(
      code: 'remote_rejected',
      message: '$resource was rejected. Diagnostic: API-REJECTED.',
    );
  }
  if (error is PublicRestRejectedException ||
      error is PublicRestProtocolException) {
    return RemoteReadFailure(
      code: 'remote_rejected',
      message: '$resource was rejected. Diagnostic: API-REJECTED.',
    );
  }
  return RemoteReadFailure(
    code: 'remote_transport',
    message: '$resource could not reach the cloud. Diagnostic: NET-TRANSPORT.',
  );
}
