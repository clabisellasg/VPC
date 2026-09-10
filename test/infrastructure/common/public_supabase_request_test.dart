import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vpc/src/infrastructure/common/public_supabase_request.dart';

void main() {
  test('classifies public request failures without provider details', () {
    expect(
      safePublicReadFailure(
        TimeoutException('private detail'),
        'Events',
      ).message,
      'Events timed out. Diagnostic: NET-TIMEOUT.',
    );
    expect(
      safePublicReadFailure(Exception('private detail'), 'Players').message,
      'Players could not reach the cloud. Diagnostic: NET-TRANSPORT.',
    );
    expect(
      safePublicReadFailure(
        const PostgrestException(message: 'private detail'),
        'History',
      ).message,
      'History was rejected. Diagnostic: API-REJECTED.',
    );
  });
}
