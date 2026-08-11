# UI Screenshot Harness

Renders the real app, headlessly, at several window sizes and writes PNGs you
can look at. It exists so an agent (or anyone without the app in front of them)
can debug layout instead of guessing from source.

```bash
flutter test test/screenshots
```

```bash
flutter test test/screenshots --plain-name workbench
```

Output: `build/ui-screenshots/<screen>_<size>_<brightness>[_<suffix>].png`
— 8 screens × 3 widths in light, plus a dark shot of each, 32 files, ~30s.

**This is not a regression gate.** The comparator installed by
`flutter_test_config.dart` always overwrites and always passes, so a UI change
can never fail `flutter test`. Layout exceptions are drained and printed rather
than asserted — an overflow is the thing you want a picture of, and
`expect(takeException(), isNull)` would abort before the PNG got written. Watch
the run output for lines like:

```
[prompts_tablet_light] exception during pump: A RenderFlex overflowed by 113 pixels on the right.
```

## Why this and not a Flutter web build

Web was the obvious idea and it does not pay off here. 56 files under `lib/`
import `dart:io`, and the coupling is structural rather than incidental:
`AppState` is a hard singleton behind `DatabaseService` → `sqflite_common_ffi`,
and the models themselves are file-backed (`AppImage.imageProvider` returns
`FileImage`). Every top-level screen fails to compile transitively. Even after
a port there is no SQLite and no local filesystem on web, so every screen would
photograph as an empty state — and each new `dart:io` call site would break the
web build again. This harness renders the same widget tree the desktop app does,
against a real database with seeded data.

## File map

| File | Responsibility |
|---|---|
| `test/screenshots/flutter_test_config.dart` | Loads real fonts; installs the always-overwrite golden comparator; disables the debug banner |
| `test/screenshots/app_screens_test.dart` | The screen × size matrix |
| `test/screenshots/harness/fixture_env.dart` | Temp directory tree, sqflite ffi, path_provider and plugin channel mocks |
| `test/screenshots/harness/fixture_seed.dart` | Database rows and generated PNG fixtures |
| `test/screenshots/harness/shoot.dart` | `shoot()`, the `AppScreen` enum and `kShotSizes` |

## Extending it

**A new size** — add to `kShotSizes` in `harness/shoot.dart`.

**A variant** (a tab, an open dialog, a different view mode) — add a
`testWidgets` with `suffix:` plus one of the hooks. `before` runs after the
singleton is configured but before the first pump, for state a screen reads on
mount; `after` runs on the settled tree, for taps.

```dart
testWidgets('workbench @ desktop, comparator tab', (WidgetTester tester) async {
  await shoot(
    tester,
    env: env,
    screen: AppScreen.workbench,
    size: kShotSizes.last,
    suffix: 'comparator',
    before: (_) async => AppState().setWorkbenchTab(2),
  );
});
```

**A different locale** — `shoot(..., locale: const Locale('ja'))`. The parameter
already exists; the matrix just fixes it at `zh` because CJK is the widest text
and therefore the case most likely to overflow.

**More seed data** — the seeders in `fixture_seed.dart` are split per area
(`_seedSettings`, `_seedCatalog`, `_seedPrompts`, `_seedTasks`, `_seedUsage`,
`_writeImages`). They all talk to `DatabaseService()` directly and must never
touch `AppState()`.

## Constraints worth knowing before you change it

**`flutter_test_config.dart` must stay in `test/screenshots/`.** flutter_tools
walks up from the test file's own directory and takes the first hit. At `test/`
it would apply to all the other test files, changing their text metrics — and
several of them assert on layout and overflow.

**Setup order is load-bearing.** `installFixtureEnv` must run before the first
`AppState()` call: `AppState` is a singleton whose `GalleryState` /
`FileBrowserState` / `TaskQueueService` fields each fire an async database read
from their constructors, so the DB path is chosen before you can await anything.
Seeding must precede `loadSettings()`.

**Seed `setup_completed`.** Without that row `AppState.loadSettings` sets
`setupCompleted = false` and `_checkFirstRun` pushes `SetupWizard` over
everything — every shot becomes the wizard.

**Never seed `concurrency_limit`.** `loadSettings` only calls
`taskQueue.updateConcurrency` when the row exists, and that path reaches
`_attemptNextExecution()`, which would fire real LLM requests for the seeded
pending tasks.

**A `processing` task cannot be seeded through the database.**
`TaskQueueService`'s constructor calls `cleanupStuckTasks()`, which rewrites
every `processing` row to `failed`. `markOneTaskRunning()` mutates one in memory
after load instead, then calls `refreshQueue()` — which is `notifyListeners()`
only and does not execute anything.

**Async work needs `runAsync`.** The `compute()` isolates behind the gallery and
browser scans make no progress inside the fake-async zone. The first scan
happens in `setUpAll` (real async); inside a test everything async goes through
`tester.runAsync`. `FileImage` decoding is asynchronous too, which is why
`shoot` precaches every fixture image before the final pump — skip that and
every thumbnail captures blank.

**Mobile size is not mobile platform.** `main.dart:256` reads
`Platform.isAndroid || Platform.isIOS` to decide which nav destinations exist,
and that is a `dart:io` check the harness cannot override on a macOS host. So
the 390px shots show File Browser and Downloader in the nav even though a real
phone hides them. The layout itself — `NavigationBar`, the drawer, the
breakpoint behaviour — is faithful; only the destination set is not.

**Timestamps are anchored to the real clock.** `kSeedNow` is `DateTime.now()`,
deliberately: the task list and usage screens render relative times, so a pinned
date drifts out of the present and renders as nonsense. Only the usage row
distribution is deterministic (a seeded LCG).

## Escape hatch: higher resolution

Captures are 1× — a 1440×900 window produces a 1440×900 PNG, which is about the
largest an agent can read without downsampling. If you ever need 2×,
`captureImage` is exported from `package:flutter_test` and can replace
`matchesGoldenFile` with a hand-rolled `toImage(pixelRatio: 2.0)` + write. It
was left out on purpose: `matchesGoldenFile` already handles the repaint-boundary
walk, the `runAsync` wrapping and the PNG encode correctly.
