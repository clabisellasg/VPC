# M01 — Flutter Project Bootstrap

## Goal and result

Milestone 1 creates a minimal, maintainable Flutter foundation for Android and
Web using the permanent Volta Paddle Club identity. It establishes only the
application composition root, declarative routing, compile-time environment
selection, a restrained bootstrap presentation, focused tests, and automated
quality/build checks.

No application feature from Milestone 2 or later is implemented.

## Toolchain baseline

- Flutter: `3.47.1`, stable channel, framework revision
  `6655482ec06e547f90abf8ae7590466f4415978d`.
- Dart: `3.13.1` stable.
- Android SDK Platform: `36.0.0`.
- Android Build Tools: `36.0.0`.
- Android NDK: `28.2.13676358` (`r28c`), required by Flutter `3.47.1`.
- Java: Android Studio JBR OpenJDK 17.
- Web browsers detected locally: Chrome and Edge.

The exact project-generation command was:

```powershell
flutter create --empty --platforms=android,web --org com.voltapaddleclub --project-name vpc --android-language kotlin .
```

The existing README and all Milestone 0 documents were hash-checked across
generation and were not overwritten by Flutter.

## Dependencies

The only direct non-SDK runtime dependencies are:

- `flutter_riverpod 3.4.2` for the state-management and
  dependency-injection composition foundation.
- `go_router 17.5.0` for declarative Android/Web routing and visible unknown
  route handling.

The development baseline uses `flutter_lints 6.0.0`. Versions were selected by
`flutter pub add flutter_riverpod go_router` against the installed stable SDK,
and the complete resolved graph is committed in `pubspec.lock`.

Riverpod was selected so application state and dependencies can be composed
without coupling presentation to later infrastructure. Its experimental
persistence or mutation APIs are not used, and Riverpod does not replace the
planned SQLite/repository/outbox synchronization architecture.

GoRouter was selected as the approved declarative routing mechanism shared by
Android and Web. Milestone 1 defines only `/`; it does not imply future feature
navigation.

## Important files

- `lib/main.dart`: resolves `APP_ENV`, creates `ProviderScope`, and calls
  `runApp`.
- `lib/src/app/app.dart`: creates `MaterialApp.router`, enables Material 3, and
  sets the application title.
- `lib/src/app/app_router.dart`: defines the single `/` route and visible safe
  handling for an unknown location.
- `lib/src/core/config/app_environment.dart`: parses the supported compile-time
  environment values.
- `lib/src/presentation/bootstrap_page.dart`: renders the responsive,
  non-interactive bootstrap status.
- `test/app_test.dart`: verifies composition, root/unknown routing, bootstrap
  content, and absence of counter-demo content.
- `test/core/config/app_environment_test.dart`: verifies default, supported,
  and unsupported environment behavior.
- `.github/workflows/ci.yml`: performs dependency, format, analysis, test, Web,
  and debug APK checks without deployment or secrets.

## Application startup and environments

At startup, `main.dart` resolves the compile-time `APP_ENV` value, then runs
`VpcApp` inside `ProviderScope`. `VpcApp` builds `MaterialApp.router` with the
approved GoRouter configuration.

`APP_ENV` supports exactly:

- `development` (default).
- `test`.
- `production`.

Select a value with `--dart-define=APP_ENV=<value>`. Unsupported values throw a
`FormatException` during startup rather than silently selecting an environment.
Configuration contains no URLs, API keys, secrets, Supabase values, or database
settings.

## Local commands

Resolve dependencies:

```powershell
flutter pub get
```

Run Android after selecting a connected device or emulator:

```powershell
flutter devices
flutter run -d <device-id> --dart-define=APP_ENV=development
```

Run Web in Chrome:

```powershell
flutter run -d chrome --dart-define=APP_ENV=development
```

Verify formatting, analysis, and tests:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Produce local build artifacts:

```powershell
flutter build apk --debug
flutter build web
```

The debug APK is produced at
`build/app/outputs/flutter-apk/app-debug.apk`; the Web build is produced at
`build/web`.

## CI behavior

GitHub Actions runs for pull requests targeting `main` and pushes to `main` or
`milestone/**`. A single Ubuntu job uses Java 17 and Flutter `3.47.1` stable,
then resolves dependencies, verifies formatting, analyzes, tests, builds Web,
and builds a debug APK. It uses no secrets, deploys nothing, uploads nothing to
Google Play, and creates no release.

The workflow is committed but has not run remotely because Milestone 1 does not
push the branch.

## Validation notes and limitations

- Local formatting, analysis, five tests, Web production build, and Android
  debug APK build passed.
- Flutter Doctor reports Android license status as unknown with the new Android
  CLI. The CLI reports that its legacy `--licenses` option is no longer needed,
  and the decisive APK build completed without a license error.
- The initial generated 8 GiB Gradle heap ceiling exceeded this machine's
  available memory. Project-local limits now use a 2 GiB heap, 1 GiB metaspace,
  and two workers; the successful APK build used those limits.
- The new Android CLI's `sdkmanager` compatibility shim could not forward the
  required NDK package correctly. The official CLI installed the exact NDK
  directly; no Android tools were downgraded and the Flutter requirement was
  not changed.
- Flutter's Web build emitted a non-fatal optional Cupertino-icons font
  diagnostic. No unapproved icon dependency was added.
- Android emitted a non-fatal SDK XML-version compatibility warning between
  installed Android tools.
- Generated placeholder launcher/PWA icons and manifest colors remain. Final
  branding, deployment, and PWA behavior are deferred.
- The app contains only a bootstrap page and safe not-found page.

Supabase, SQLite, authentication, domain entities, repositories, player/event
features, tournament algorithms, statistics, persistence, synchronization,
and deployment remain unimplemented. Milestone 2 remains `NOT STARTED`.
