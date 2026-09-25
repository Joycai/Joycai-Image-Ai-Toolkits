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

```bash
flutter test test/screenshots/component_gallery_test.dart
```

Output: `build/ui-screenshots/<screen>_<size>_<brightness>[_<suffix>].png`
— 8 screens × 4 widths in light, a dark shot of each at desktop, then a long
tail of state variants (staging, conflicts, folder ops, AI rename, every
workbench tab, the model editor's four states). 123 files from the
`app_screens_*_test.dart` files plus the 16 `gallery_*.png` theme sheets from
`component_gallery_test.dart`, about a minute for the lot.

The shots are split into one file per area because `flutter test` runs files
in parallel but a file's own tests in sequence. As a single file they took
~150s on their own; split, the runner spreads them across cores. Each file
seeds its own fixture environment, so a new shot goes into the file for its
area, after that area's matrix.

**This is not a regression gate.** The comparator installed by
`flutter_test_config.dart` always overwrites and always passes, so a UI change
can never fail `flutter test`. Every file carries the `screenshots` tag, so the
gate (`flutter test -x screenshots`, which CI runs) skips them; naming the
directory still renders them. Layout exceptions are drained and printed rather
than asserted — an overflow is the thing you want a picture of, and
`expect(takeException(), isNull)` would abort before the PNG got written. Watch
the run output for lines like:

```
[prompts_tablet_light] exception during pump: A RenderFlex overflowed by 113 pixels on the right.
```

## Why this and not a Flutter web build

Web was the obvious idea and it does not pay off here. 70 files under `lib/`
import `dart:io`, and the coupling is structural rather than incidental:
`AppState` is a hard singleton behind `DatabaseService` → `sqflite_common_ffi`,
and the models themselves are file-backed (an `AppImage` is a path, shown through a
`FileImage`). Every top-level screen fails to compile transitively. Even after
a port there is no SQLite and no local filesystem on web, so every screen would
photograph as an empty state — and each new `dart:io` call site would break the
web build again. This harness renders the same widget tree the desktop app does,
against a real database with seeded data.

## File map

| File | Responsibility |
|---|---|
| `test/screenshots/flutter_test_config.dart` | Loads real fonts; installs the always-overwrite golden comparator; disables the debug banner |
| `test/screenshots/fonts/` | NotoSansSC (all UI text, aliased to the OS family names) and Cascadia Mono (every name in the mono stack, OFL text beside it) — why each is needed is in `_loadFonts` |
| `test/screenshots/app_screens_*_test.dart` | The screen × size matrix and each area's state variants, one file per area |
| `test/screenshots/harness/suite.dart` | Per-file fixture setup, `shootMatrix()` and `settle()` |
| `test/screenshots/harness/fixture_env.dart` | Temp directory tree, sqflite ffi, path_provider and plugin channel mocks |
| `test/screenshots/harness/fixture_seed.dart` | Database rows and generated PNG fixtures |
| `test/screenshots/harness/shoot.dart` | `shoot()`, the `AppScreen` enum and `kShotSizes` |
| `test/screenshots/component_gallery_test.dart` | Every shared component on one page, rendered under all 8 preset accents × light/dark |

## Extending it

**A new size** — add to `kShotSizes` in `harness/shoot.dart`.

**A different accent** — `shoot(..., accent: AppConstants.presetThemes['Rose'])`.
The accent name goes into the filename, so two accents never overwrite each
other's PNG. For anything touching accent or status colour, reach for
`component_gallery_test.dart` first: one page of every component under all 8
seeds in both brightnesses is the only way to see whether a colour rule
survives a seed change.

**A variant** (a tab, an open dialog, a different view mode) — add a
`testWidgets` with `suffix:` plus one of the hooks. `before` runs after the
singleton is configured but before the first pump, for state a screen reads on
mount; `after` runs on the settled tree, for taps. `before` runs in real async
(so it may write a file or a persisted setting, and must not call `runAsync`
itself); `after` runs under the fake clock.

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

Pick the hook by what the screen does on mount, not by what is convenient.
Seeding a gallery selection in `before` looks like it works — the count is
right — and then photographs as empty, because the workbench rescans on mount
and the scan rebuilds the `AppImage` list the selection was made against. That
kind of state belongs in `after`. The `_workbenchTabs` table in
`app_screens_workbench_tabs_test.dart` carries a `seedOnSettled` flag for exactly this.

**The workbench is six tools behind one nav entry**, and the main matrix only
reaches tab 0. The rest live in the `_workbenchTabs` table at the bottom of
`app_screens_workbench_tabs_test.dart` — all six tabs are covered now, several of them more
than once where the arrangements are separate rendering paths rather than
settings of one (the comparator has side-by-side, stacked, slider and empty;
the assistant has idle, running, system-prompt and knowledge-edit). Add a new
one there before redesigning it, not after.

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
several of them assert on layout and overflow. (`test/` has one of its own, which
only installs the database rule below; this one shadows it, so it installs it too.)

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
after load instead, then calls `refreshQueue()` — which re-issues the list and
notifies, and does not execute anything. To change *which* tasks are in the queue
use `setQueueForTest`: the list `queue` hands out is unmodifiable.

**Async work needs `runAsync`.** The `compute()` isolates behind the gallery and
browser scans make no progress inside the fake-async zone. The first scan
happens in `setUpAll` (real async); inside a test everything async goes through
`tester.runAsync` — by way of the helpers in the next paragraph, not bare.
`FileImage` decoding is asynchronous too, which is why `shoot` precaches every
fixture image before the final pump — skip that and every thumbnail captures
blank.

**No database call under the fake clock — enforced.** Both
`flutter_test_config.dart` files install
`test/support/fake_async_database_rule.dart`, which fails any test in which
`DatabaseService.database` was read under `testWidgets`' fake clock, with the
stack of the call. Such a call is a race with the runner's disk (it read as
Linux-only CI flakes for a while), and one still in flight when the test ends
holds sqflite's lock for every test after it. In an `after` hook or a test
body, put the action that reaches the database *and the frame it asks for* —
the pump is what mounts a panel that loads on mount — inside real async:
`actInRealAsync` here, `inRealAsync` / `inRealAsyncUntil` /
`pumpWidgetInRealAsync` / `useRealAsyncAppState` in
`test/support/real_async.dart`. Wait on a state, or on `databaseIdle`, never on a
number of pumps. A bare `tester.runAsync` swallows what its body throws — a
finder that matched nothing becomes a line of log and a wrong picture — so use
those helpers, or `runAsyncRethrowing`; `mountApp` runs `before` through it.

**An image load must not outlive its test.** The image cache is process-wide,
and a load started by a pump outside `runAsync` belongs to that test's
fake-async zone. When the test ends nothing flushes that zone again, so the
load stays pending for good — and the next `precacheImage` of the same path is
handed the same completer and never returns. That hung `render_probe.dart` from
its second test on. `mountApp` calls `dropUnfinishedImageLoads()` on the way in
and registers it as a teardown; a harness file that precaches without going
through `mountApp` relies on the teardown of the test before it. The warm-up
also bounds each image at 10 real seconds and throws `WarmUpStalled` with the
path, because an unbounded wait does not fail a test, it hangs the process until
CI's job timeout. `test/app/mount_app_unfinished_image_load_test.dart` pins all of it.

**Mobile size is not mobile platform.** `main.dart:248` reads
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
