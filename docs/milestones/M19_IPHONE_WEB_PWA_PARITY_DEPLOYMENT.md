# M19 — iPhone Web/PWA Parity and Deployment

## Scope and decision

M19 verifies guest, player, and online organizer behavior on iPhone Safari and
deploys the Flutter Web/PWA as a purely static Cloudflare Pages application.
OPEN-010 is resolved by V1-082: the project is `volta-paddle-club`, the Version
1 origin is `https://volta-paddle-club.pages.dev`, and no paid Cloudflare
product, Function, Worker, KV, D1, R2, or custom domain is used.

## Production build and hosting

`tool/build_web_release.dart` requires environment variables `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY`. It validates the pair without echoing values, writes
a temporary Dart-define JSON file, invokes `flutter build web --release` with
the standard JavaScript target and `--pwa-strategy=none`, then deletes the
temporary file. The publishable key is intentionally browser-visible; a secret
or service-role key is prohibited.

Cloudflare Pages serves `build/web`. There is no top-level `404.html`, allowing
automatic SPA fallback for direct path reloads. `_headers` disables stale
caching for the application shell/bootstrap/version metadata and adds
`nosniff`, strict-origin referrer, framing, and unused-device-permission
protections. A restrictive CSP is deferred until compatibility with Flutter,
Supabase, CanvasKit, authentication, and optional Wasm paths is demonstrated.

The GitHub workflow builds and deploys only on `main`, uses the protected
`production` environment, serializes deployments, reads configuration from
GitHub variables/secrets, and deploys only static Web output. Pull requests and
forks cannot deploy or access production deployment credentials.

## PWA and iPhone behavior

The manifest uses stable ID, start URL, and scope `/`, standalone display,
Volta Paddle Club names/colors, and 192/512 regular and maskable icons. The
document adds iPhone standalone/touch-icon metadata, `viewport-fit=cover`, and
safe-area insets. Orientation remains unrestricted for portrait and landscape.
Path URL strategy preserves production deep links and the exact callback route.

The Web application remains online-first. A visible browser-offline banner
explains that Web changes require connectivity and retry. No SQLite, Drift,
IndexedDB repository, private-response cache, offline outbox, or offline
organizer authority is added. Home Screen installation does not provide
Android-style offline operation.

Public events, players, and history use a minimal RLS-protected GET adapter on
Web. The publishable key is supplied as a query parameter because the tested
iPhone WebKit environment blocked cross-origin requests containing the
standard `apikey` and `x-client-info` headers. The adapter sends no private
credential, redacts failures, and is not used for authenticated mutations.
Account and organizer commands remain on the official Supabase client. The
iPhone bootstrap keeps CanvasKit while selecting its supported CPU surface to
reduce stale WebGL-frame compositing during history traversal.

## Authentication

Production uses
`https://volta-paddle-club.pages.dev/account/confirm`. Supabase must allow that
exact redirect and retain approved localhost callbacks plus
`com.voltapaddleclub.vpc://auth-callback/account/confirm`. Preview origins do
not receive production authentication authority. Email confirmation remains
enabled.

## Validation and manual acceptance

The configured release was deployed to the production Pages origin. All 383
Flutter tests, strict formatting, analysis, build-runner freshness, Web release
and Android debug builds, linked migration agreement, and linked database lint
passed. Production HTTPS, SPA deep routes, manifest/icons and MIME types,
cache/security headers, public event reads, and browser-console checks passed.
No source map or generated service-worker asset was deployed. The standalone
Drift schema-dump command stalled repeatedly during Windows build-hook startup;
M19 changes no Drift input, tracked generated files remained unchanged, and all
migration/database tests passed.

Hosted publishable-key checks returned `200` for public events, players, and
player history; private profile, role, claim, and payment relations were not
exposed, and anonymous player mutation returned `401`. The user confirmed the
physical Android regression categories A–E on 2026-09-08 after installing the
current configured debug APK. Fresh-install launch, synchronized history,
offline cached reading, reconnect, authentication, large text, and relaunch
without USB passed.

The user confirmed physical iPhone 15/iOS 18.7.8 Safari and Home Screen
walkthrough categories A–F on 2026-09-10. Public data, direct routes,
authentication, organizer gating, tournament views, online-only failure and
retry, portrait/landscape, text scaling, installation, session restoration,
and standalone relaunch passed. A targeted header diagnostic identified the
iPhone WebKit public-read failure, and the deployed header-minimal transport
restored stable public data in both Safari and Home Screen mode.

## Known limitations and M20 boundary

Cloudflare and Supabase free-tier limits may change and must be monitored. The
PWA has no native iOS distribution, offline tournament operation, push
notifications, or custom domain. M20 owns release-wide hardening; M19 does not
start it.

The tested iPhone can still show a brief image of the previous route while
Safari performs native back/forward traversal. The correct route and content
arrive, and the behavior persisted after disabling the iPhone WebGL surface;
it is documented as a device/WebKit rendering limitation rather than incorrect
application history. No native iOS workaround or custom navigation stack was
introduced.
