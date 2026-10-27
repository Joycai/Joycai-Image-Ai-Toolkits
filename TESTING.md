# Testing Strategy

Use Flutter 3.47.8, matching [CI](.github/workflows/flutter-ci.yml). Run commands
from the repository root after `flutter pub get`. If localization sources changed,
run `dart tool/merge_l10n.dart` successfully before `flutter gen-l10n`.

## Required checks

All three gates must pass after code changes and before committing:

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test -x screenshots
```

To apply formatting first, use `dart format lib test tool`. Analysis must report
`No issues found!`. CI runs formatting and analysis in one job and distributes
non-screenshot test files across three parallel jobs.

For a focused check, name a file, for example:

```bash
flutter test test/source_layout_test.dart
```

Tests mirror their subjects under `test/core/`, `test/models/`, `test/services/`,
`test/state/`, `test/widgets/`, and `test/screens/`. Whole-app tests live in
`test/app/`; source audits live in `test/architecture/`. The source-layout test
enforces layer imports, domain folders, and design-system boundaries. See
[AGENTS.md](AGENTS.md) for the full architecture rules.

## Database and widget test helpers

Tests use `flutter_test`. Database tests use real SQLite through
`sqflite_common_ffi`, with isolated databases rather than a mocked SQL API.

- Initialize FFI with `sqfliteFfiInit()`, then use `openTestDatabase()` and
  `closeTestDatabase()` from [in_memory_database.dart](test/support/in_memory_database.dart).
  Inject the returned service through `database:` (states/services) or `db:`
  (repositories). It creates the current schema but does not seed shipped presets.
- Keep database calls out of `testWidgets`' fake clock. The per-file
  [test configuration](test/flutter_test_config.dart) installs a rule that fails
  database access under that clock.
- For whole-app fixtures, initialize `AppState` in real async (`setUpAll` or
  `useRealAsyncAppState`). Use `pumpWidgetInRealAsync` / `inRealAsync` for mounting
  or actions that start database work, including the frame they request.
- Before asserting a write's outcome, use `inRealAsyncUntil` with an observable
  state condition. `databaseIdle` only waits for loads; it can return during a
  transaction. `runAsyncRethrowing` propagates failures from real async work.
  These helpers live in [real_async.dart](test/support/real_async.dart).

Set the widget test viewport for the layout being exercised. Tests do not share
a global 1920×1080 viewport; responsive coverage includes phone, tablet, and
desktop sizes.

## Visual verification

```bash
flutter test test/screenshots
flutter test test/screenshots/component_gallery_test.dart
```

The screenshot harness renders seeded real screens at 390 / 834 / 1024 / 1440px
in light and dark modes and writes PNGs to `build/ui-screenshots/`. The component
gallery covers eight accent seeds in both themes. Open the generated images and
inspect the run output for layout exceptions.

The `screenshots` tag excludes render-only harness tests from the normal gate.
These overwrite PNGs and do not assert golden-image equality; layout exceptions
are printed, not asserted. Assertion-based tests alongside them, such as
`rebuild_scope_test.dart`, remain in the normal gate. See the
[screenshot harness guide](docs/ui-screenshot-harness.md).

## Performance verification

```bash
flutter test test/screenshots/render_probe.dart
```

The render probe measures UI-tree rebuild/repaint scope. It is explicitly invoked
and is not a `*_test.dart` file. Existing regressions are covered by
`test/screenshots/rebuild_scope_test.dart` and `test/core/render_performance_test.dart`.
For GPU work, use `lib/bench/render_bench.dart` and read the platform-specific
measurement caveats in the [tooling notes](docs/README.md#tooling).

## Native and provider verification

Build on the target platform with its native toolchain, for example:

```bash
flutter build macos
```

Use `flutter build windows`, `flutter build linux`, `flutter build apk`, or
`flutter build ipa` on an appropriate host. The
[build workflow](.github/workflows/flutter-build.yml) records release dependencies
and packaging for Windows, macOS, Linux, and Android. A headless widget render
does not verify native integrations or paid provider behavior. Outstanding live
API and native checks are tracked in the [plan ledger](docs/plans/README.md).
