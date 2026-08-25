/// Compile-time Supabase client configuration.
final class SupabaseConfiguration {
  const SupabaseConfiguration._({
    required this.url,
    required this.publishableKey,
  });

  factory SupabaseConfiguration.fromValues({
    String url = '',
    String publishableKey = '',
  }) {
    final normalizedUrl = url.trim();
    final normalizedKey = publishableKey.trim();
    final hasUrl = normalizedUrl.isNotEmpty;
    final hasKey = normalizedKey.isNotEmpty;

    if (hasUrl != hasKey) {
      throw const FormatException(
        'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be provided together.',
      );
    }

    if (!hasUrl) {
      return const SupabaseConfiguration._(url: null, publishableKey: null);
    }

    final parsedUrl = Uri.tryParse(normalizedUrl);
    if (parsedUrl == null ||
        !parsedUrl.hasScheme ||
        !parsedUrl.hasAuthority ||
        (parsedUrl.scheme != 'https' && parsedUrl.scheme != 'http')) {
      throw const FormatException('SUPABASE_URL must be a valid HTTP(S) URL.');
    }

    return SupabaseConfiguration._(
      url: normalizedUrl,
      publishableKey: normalizedKey,
    );
  }

  factory SupabaseConfiguration.fromEnvironment() =>
      SupabaseConfiguration.fromValues(
        url: const String.fromEnvironment('SUPABASE_URL'),
        publishableKey: const String.fromEnvironment(
          'SUPABASE_PUBLISHABLE_KEY',
        ),
      );

  final String? url;
  final String? publishableKey;

  bool get isConfigured => url != null && publishableKey != null;
}
