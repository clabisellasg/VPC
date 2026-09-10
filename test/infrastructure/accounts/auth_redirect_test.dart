import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/infrastructure/accounts/account_providers.dart';

void main() {
  test('Web callback uses the browser origin and production path', () {
    expect(
      buildAuthRedirect(
        isWeb: true,
        browserUri: Uri.parse('https://volta-paddle-club.pages.dev/players/1'),
      ),
      'https://volta-paddle-club.pages.dev/account/confirm',
    );
  });

  test('Android callback remains the native application scheme', () {
    expect(
      buildAuthRedirect(
        isWeb: false,
        browserUri: Uri.parse('https://ignored.example.invalid'),
      ),
      'com.voltapaddleclub.vpc://auth-callback/account/confirm',
    );
  });
}
