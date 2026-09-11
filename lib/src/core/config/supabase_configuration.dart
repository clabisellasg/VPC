import 'dart:convert';

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

    if (_isPrivilegedKey(normalizedKey)) {
      throw const FormatException(
        'SUPABASE_PUBLISHABLE_KEY must be a public client key.',
      );
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

bool _isPrivilegedKey(String value) {
  if (value.toLowerCase().startsWith('sb_secret_')) return true;
  final segments = value.split('.');
  if (segments.length != 3) return false;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
    );
    return payload is Map<String, dynamic> &&
        payload['role']?.toString().toLowerCase() == 'service_role';
  } on FormatException {
    return false;
  }
}
