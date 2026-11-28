# Testing Strategy

Use Flutter 3.50.1, matching [CI](.github/workflows/flutter-ci.yml). Run commands
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

## Visual and layout verification

The project uses a four-layer UI verification model:

1. **Static source guards** (`test/architecture/`): `design_token_scan_test.dart` ratchets raw `Color(0x...)`, `Colors.<named>`, `fontSize`, and `BorderRadius.circular(...)` literals in `lib/screens/` and `lib/widgets/`, while `test_hygiene_scan_test.dart` forbids `expect()` calls inside `@Tags(['screenshots'])` files so assertions are never silently skipped by CI.
2. **Component theme & overlay contracts**: `test/widgets/ui/design_system_theme_contract_test.dart` and `test/widgets/glass/glass_theme_contract_test.dart` assert neutral invariance, accent bindings across all 8 presets × light/dark, reduced-effects fallbacks, real `Tooltip`/`AppSnackBar`/`AppGlassMenu` overlays, and rendered WCAG AA contrast.
3. **CI layout invariants** (`test/app/layout_invariants_test.dart`): mounts all 8 screens across 390 / 834 / 1024 / 1440 widths, light/dark, `zh`/`en`, all 6 workbench tabs, Windows compact density, and mobile-OS destination gating using real test fonts (`test/support/real_fonts.dart`), asserting zero exceptions, `<= 4` visible `BackdropFilter` layers, and non-clipped chrome controls.
4. **Component goldens & interactive/screenshot review**:
   - **Component goldens** (`test/golden/design_system_golden_test.dart`, tagged `golden`): deterministic pixel regression sheets with a tolerant comparator (`test/support/tolerant_golden_comparator.dart`). Run `flutter test -t golden test/golden` (or `--update-goldens` when intentionally updating component visuals); CI runs this in a dedicated Ubuntu job.
   - **Live previews & Desktop Catalog**: `@Preview` definitions in `lib/widgets/ui/ui_previews.dart` and `lib/widgets/glass/glass_previews.dart`, plus the standalone interactive catalog launched via `CATALOG=1` (`lib/bench/design_catalog.dart`).
   - **Full-screen screenshot harness** (`test/screenshots/`):

```bash
flutter test test/screenshots
flutter test --dart-define=STRICT_SCREENSHOTS=true test/screenshots/component_gallery_test.dart
dart run tool/screenshot_diff.dart snapshot
dart run tool/screenshot_diff.dart compare
```

The screenshot harness renders seeded real screens at 390 / 834 / 1024 / 1440px
in light and dark modes and writes PNGs to `build/ui-screenshots/`. The component
gallery covers eight accent seeds in both themes. Passing `--dart-define=STRICT_SCREENSHOTS=true`
still writes PNGs first and then fails the test if any pump exceptions occurred. Use
`tool/screenshot_diff.dart` to snapshot before edits and generate a side-by-side HTML
diff report (`build/ui-screenshots-diff/index.html`) afterward.

The `screenshots` tag excludes render-only harness tests from the normal gate.
These overwrite PNGs and do not assert golden-image equality; layout exceptions
are printed unless `STRICT_SCREENSHOTS=true` is set. Assertion-based tests alongside
them, such as `rebuild_scope_test.dart`, remain in the normal gate. See the
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
