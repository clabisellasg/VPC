import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/core/config/app_environment.dart';

void main() {
  test('development is the default environment', () {
    expect(AppEnvironment.resolve(), AppEnvironment.development);
  });

  test('supported values map to their environments', () {
    expect(AppEnvironment.parse('development'), AppEnvironment.development);
    expect(AppEnvironment.parse('test'), AppEnvironment.test);
    expect(AppEnvironment.parse('production'), AppEnvironment.production);
  });

  test('unsupported values are rejected', () {
    expect(
      () => AppEnvironment.parse('staging'),
      throwsA(isA<FormatException>()),
    );
  });
}
