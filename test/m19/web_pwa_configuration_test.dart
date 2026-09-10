import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest has installable Volta metadata and valid icons', () {
    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['name'], 'Volta Paddle Club');
    expect(manifest['short_name'], 'VPC');
    expect(manifest['id'], '/');
    expect(manifest['start_url'], '/');
    expect(manifest['scope'], '/');
    expect(manifest['display'], 'standalone');

    final icons = manifest['icons']! as List<dynamic>;
    expect(icons, hasLength(4));
    for (final icon in icons.cast<Map<String, dynamic>>()) {
      final file = File('web/${icon['src']}');
      expect(file.existsSync(), isTrue, reason: file.path);
      expect(file.readAsBytesSync().length, greaterThan(24));
    }
    expect(File('web/icons/apple-touch-icon-180.png').existsSync(), isTrue);
  });

  test('static hosting keeps SPA fallback and safe response headers', () {
    expect(File('web/404.html').existsSync(), isFalse);
    final headers = File('web/_headers').readAsStringSync();
    expect(headers, contains('X-Content-Type-Options: nosniff'));
    expect(
      headers,
      contains('Referrer-Policy: strict-origin-when-cross-origin'),
    );
    expect(headers, contains('X-Frame-Options: DENY'));
    expect(headers, contains('Cache-Control: no-cache, no-store'));
    expect(headers, contains('/main.dart.js'));
    expect(headers, contains('/assets/AssetManifest.bin.json'));
  });

  test('deployment is main-only, static, and secret-backed', () {
    final workflow = File('.github/workflows/deploy-pages.yml')
        .readAsStringSync();
    expect(workflow, contains("github.ref == 'refs/heads/main'"));
    expect(workflow, contains('pages deploy build/web'));
    expect(workflow, contains('CLOUDFLARE_API_TOKEN'));
    expect(workflow, contains('CLOUDFLARE_ACCOUNT_ID'));
    expect(workflow, contains('SUPABASE_PUBLISHABLE_KEY'));
    expect(workflow, isNot(contains('service-role')));
    expect(workflow, isNot(contains('pull_request:')));
  });

  test('Web build disables the generated service worker', () {
    final script = File('tool/build_web_release.dart').readAsStringSync();
    expect(script, contains("'--pwa-strategy=none'"));
    expect(script, contains('--dart-define-from-file='));
    expect(script, contains("'build/web/flutter_service_worker.js'"));
    expect(script, contains("'--no-wasm-dry-run'"));
    expect(script, isNot(contains('--wasm')));

    final index = File('web/index.html').readAsStringSync();
    expect(index, contains('flutter_bootstrap.js'));
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(bootstrap, contains('navigator.serviceWorker.getRegistrations()'));
    expect(bootstrap, contains("path.endsWith('/flutter_service_worker.js')"));
    expect(bootstrap, contains('registration.unregister()'));
    expect(bootstrap, contains('canvasKitForceCpuOnly: iosWebKit'));
    expect(bootstrap, contains('iPad|iPhone|iPod'));
  });
}
