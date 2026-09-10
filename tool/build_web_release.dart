import 'dart:convert';
import 'dart:io';

import 'package:vpc/src/core/config/production_web_configuration.dart';

Future<void> main() async {
  late final ProductionWebConfiguration configuration;
  try {
    configuration = ProductionWebConfiguration.fromEnvironment(
      Platform.environment,
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'vpc-web-release-',
  );
  final defineFile = File('${temporaryDirectory.path}/defines.json');
  try {
    await defineFile.writeAsString(
      jsonEncode(configuration.toDartDefineJson()),
    );
    final flutterExecutable = Platform.isWindows ? 'flutter.bat' : 'flutter';
    final process = await Process.start(flutterExecutable, <String>[
      'build',
      'web',
      '--release',
      '--no-wasm-dry-run',
      '--pwa-strategy=none',
      '--dart-define-from-file=${defineFile.path}',
    ], mode: ProcessStartMode.inheritStdio);
    exitCode = await process.exitCode;
    if (exitCode == 0) {
      final generatedServiceWorker = File(
        'build/web/flutter_service_worker.js',
      );
      if (await generatedServiceWorker.exists()) {
        await generatedServiceWorker.delete();
      }
    }
  } finally {
    await temporaryDirectory.delete(recursive: true);
  }
}
