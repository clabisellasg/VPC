enum AppEnvironment {
  development,
  test,
  production;

  static const String defineName = 'APP_ENV';
  static const String defaultValue = 'development';

  static AppEnvironment resolve([
    String value = const String.fromEnvironment(
      defineName,
      defaultValue: defaultValue,
    ),
  ]) {
    return parse(value);
  }

  static AppEnvironment parse(String value) {
    return switch (value) {
      'development' => AppEnvironment.development,
      'test' => AppEnvironment.test,
      'production' => AppEnvironment.production,
      _ => throw FormatException(
        'Unsupported APP_ENV "$value". Expected development, test, or '
        'production.',
      ),
    };
  }
}
