# M20 — Release Hardening

## Evidence-based hardening checklist

Baseline: `main` at `9a70f7ad1cc55d2a8e858acb14b4e9c6d9e7f10e`.
This checklist records the release-candidate audit before corrective work. A
checked item requires repository, automated, hosted, deployed, or physical
device evidence as appropriate.

### Release blockers

- [x] Confirm no authorization, privacy, data-loss, migration, synchronization,
  production-crash, or essential-workflow blocker exists.
- [x] Correct any blocker found and rerun its focused regression before the
  complete validation suite.

### Important hardening

- [x] Security: scan source, generated artifacts, CI, documentation, Flutter
  bundles, Supabase grants/RLS/functions, and production responses for secrets,
  private data, unsafe redirects, debug surfaces, or excessive authority.
- [x] Migrations: verify fresh Drift creation and every committed snapshot path,
  rollback behavior, generated freshness, hosted history agreement, dry run,
  lint, and append-only recovery guidance.
- [x] Accessibility: verify semantics, keyboard alternatives and focus,
  validation recovery, non-color status labels, touch targets, 200% text,
  safe-area/keyboard behavior, and accessible bracket/table alternatives.
- [x] Performance: measure release artifacts and representative launch, list,
  tournament, queue, synchronization, and hosted history-query behavior; fix
  only reproducible weaknesses.
- [x] Recovery: exercise atomic interruption, claim/apply acknowledgement,
  pull checkpoints, connectivity/auth loss, replay, scoped conflicts,
  Cloudflare rollback, and non-destructive migration failure.
- [x] Regression: add only missing high-value tests and run the full Android/Web,
  hosted, deployed, documentation, privacy, and generated-source checks once.

### Known nonblocking limitations to verify and document

- [x] Web/iPhone remains online-first; Android remains the only offline-first
  platform.
- [x] The tested iPhone may briefly retain a prior CanvasKit frame during native
  Safari history traversal while still reaching the correct route and data.
- [x] Local pgTAP/reset is unavailable when Docker's Linux engine is unavailable.
- [x] A signed release APK is not produced unless the repository already has a
  secure signing process; M20 must not create signing material.
- [x] M21 community rehearsal, pilot, and Version 1 release remain out of scope.

## Findings and corrections

### Release blockers corrected

- The production configuration accepted an HTTP Supabase origin and did not
  explicitly reject the modern `sb_secret_` prefix or a service-role JWT. The
  validator now requires HTTPS for production and rejects both privileged-key
  forms without echoing their values.
- Unknown routes displayed the complete URI, including query and fragment data.
  The safe not-found page now displays only the path.
- The round-robin organizer header lost essential controls at 200% text size.
  It now scrolls within a bounded header, and the seed editor provides labelled
  keyboard/touch move controls as an alternative to drag.
- Team-preview failures could display an unexpected provider exception. Domain
  failures retain their safe message; unexpected failures now use a fixed,
  retryable explanation.

### Important hardening completed

- Added configuration-redaction, safe-route, all-snapshot migration, migration
  rollback, 200%-text queue, round-robin layout, and keyboard seed-order
  regressions. Existing atomicity, replay, recovery, privacy, four-format,
  history, queue, and Web-no-SQLite coverage remains authoritative.
- Every committed Drift v1–v10 snapshot migrates to v11. A deliberately failed
  migration leaves the old user version and representative player row intact.
- All 19 exposed PostgreSQL tables have RLS enabled. All 42 committed
  `SECURITY DEFINER` definitions declare an explicit safe search path. The 47
  local and hosted migrations agree through `20260907180000`; no M20 database
  migration was necessary.
- The production Web artifact was built with validated public configuration and
  deployed to the existing Cloudflare Pages project solely for release-candidate
  validation. It contains no generated service worker or source map; Pages may
  return the SPA document for unknown asset paths.

### Nonblocking limitations

- The standalone Drift schema-dump command stalls in Dart build-hook startup on
  this Windows host. Deterministic `build_runner` output, the committed v11 JSON
  snapshot, regenerated migration helpers, and migration tests are clean; CI
  uses this same bounded verification strategy.
- Linked lint reports only inherited PL/pgSQL quality warnings in the large M13
  and M14 functions, not errors. Replacing those accepted functions solely to
  silence shadow/unused-variable warnings would be a higher-risk change.
- Docker's Linux engine is unavailable, so local reset/pgTAP was skipped. Hosted
  history, dry-run, lint, HTTP/RLS smoke checks, and committed SQL assertions
  provide the available database evidence.
- No secure Android release-signing material exists in the repository. M20 built
  the approved debug APK and did not create or request a signing key.
- The previously observed iPhone WebKit/CanvasKit prior-frame flash remains a
  presentation limitation; it did not change routing, current data, or access
  control during M19 acceptance.

## Validation evidence

- Flutter 3.47.1 / Dart 3.13.1: strict formatting and analysis pass; all 387
  Flutter tests pass. Ordinary tests use no live network.
- Production JavaScript Web build: 98.1 seconds and 43,801,679 bytes total.
  Android debug APK: 45.8 seconds and 193,624,425 bytes. These are reproducible
  host measurements, not release budgets.
- Five production-root requests had a 287 ms median on the validation network;
  the one cold/outlier request made the observed range 126–4,178 ms. Public
  player/event lists remain bounded, history is paginated, and inspected hosted
  indexes cover the active operational access paths. No speculative performance
  rewrite was justified.
- Production root, events, players, account, auth confirmation, and deep routes
  return the Flutter application over HTTPS. Manifest and JavaScript MIME types,
  no-store shell caching, `nosniff`, strict-origin referrer policy, and frame
  denial are present. The deployed `main.dart.js` exactly matches the locally
  validated artifact. Browser inspection found meaningful content, usable
  keyboard focus, a safe path-only not-found view, and no console warnings or
  errors.
- Hosted anonymous public reads succeed; anonymous writes and reads of private
  profiles/payments fail. Committed protocol assertions and the complete Flutter
  suite cover organizer/non-organizer authority, idempotency, stale conflicts,
  scoped recovery, and private synchronization data without creating hosted
  test records during M20. The Supabase Security Advisor was not available
  through the installed CLI, so no advisor result is claimed.
- The user completed and accepted the physical Android, physical iPhone PWA,
  and desktop-Web release-candidate matrices on 2026-09-11. These covered
  guest/auth/session behavior, representative organizer and offline Android
  recovery, synchronization/conflicts, TalkBack/VoiceOver, 200% text,
  rotation/safe areas, iPhone online-only recovery, direct-route and browser
  history behavior, keyboard-only Web operation, privacy, USB-free Android
  reopening, and standalone iPhone reopening.

## Release-candidate manual matrix

Use only existing synthetic records. Android must cover guest/auth/session,
representative offline organizer work, restart, reconnect, conflict handling,
200% text, TalkBack, rotation, and USB-free reopen. iPhone PWA must cover HTTPS
and standalone relaunch, guest/auth/organizer paths, VoiceOver, 200% text,
rotation/safe areas, connectivity honesty/recovery, callback handling, and the
absence of Web offline mutation claims. Desktop Web must cover guest/organizer
paths, direct routes/history navigation, keyboard-only operation, narrow/wide
layouts, current deployment, no console errors, no SQLite, and no private data.
All three matrices passed on 2026-09-11 using synthetic/test records.

## Remaining M21 actions

M21 alone owns the real community rehearsal, pilot tournament, release-blocking
pilot fixes, and Version 1 release decision.
