import 'supabase_configuration.dart';

/// Validated inputs for a production Web release.
final class ProductionWebConfiguration {
  const ProductionWebConfiguration._({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  factory ProductionWebConfiguration.fromEnvironment(
    Map<String, String> environment,
  ) {
    final configuration = SupabaseConfiguration.fromValues(
      url: environment['SUPABASE_URL'] ?? '',
      publishableKey: environment['SUPABASE_PUBLISHABLE_KEY'] ?? '',
    );
    if (!configuration.isConfigured) {
      throw const FormatException(
        'Production Web configuration is missing required values.',
      );
    }
    return ProductionWebConfiguration._(
      supabaseUrl: configuration.url!,
      supabasePublishableKey: configuration.publishableKey!,
    );
  }

  final String supabaseUrl;
  final String supabasePublishableKey;

  Map<String, Object> toDartDefineJson() => <String, Object>{
    'APP_ENV': 'production',
    'SUPABASE_URL': supabaseUrl,
    'SUPABASE_PUBLISHABLE_KEY': supabasePublishableKey,
  };
}
