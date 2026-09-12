// Raster benchmark harness — a measuring tool, inert unless RBENCH=1.
//
// The rest of the project's render tooling (`test/screenshots/render_probe.dart`,
// `rebuild_scope_test.dart`, `render_performance_test.dart`) measures the UI
// thread: what rebuilt, how many widgets, where the boundaries sit. None of it
// can see the raster thread, and every GPU figure in the docs — "a full-width
// blur costs ~19ms a frame on an integrated GPU at 4K" — came from a one-off
// VM-service trace that nothing can re-run. This is the re-runnable version.
//
// Build profile, then drive the exe with environment variables:
//
//   flutter build windows --profile
//   RBENCH=1 RBENCH_SCENE=aurora RBENCH_SIZE=1400x950 \
//     RBENCH_OUT=out.json build/windows/x64/runner/Profile/<app>.exe
//
//   RBENCH=1                  enable (without it this file does nothing)
//   RBENCH_LABEL=baseline     name in the report
//   RBENCH_OUT=C:\out.json    write the report to a file (stdout too)
//   RBENCH_FRAMES=400         frames to sample after warm-up
//   RBENCH_WARMUP=120         frames to discard first
//   RBENCH_SIZE=1400x950      logical window size; omit to maximize
//   RBENCH_SCENE=aurora       a bisection scene instead of the real app
//
// Reading the numbers — and the trap this file exists to record:
//
//   * `build` is the UI thread, and it is honest: ~0.06ms in every scene here.
//   * **`raster` is NOT the GPU on this app.** `windows/runner/main.cpp` pins
//     Skia (Impeller cannot import video_player_win's DXGI shared-handle
//     textures), and Skia on ANGLE/D3D11 submits commands and returns while
//     the GPU works asynchronously. `rasterDuration` measures the raster
//     thread's own CPU time, so every scene below reads 0.25-1.2ms while the
//     GPU is at 15-69% of a 16.7ms frame. Maximizing from 5.3 to 7.9
//     megapixels did not move `rasterDuration` at all, which is the tell.
//   * For GPU time use the Windows engine counter, which is what
//     `tool/bench/gpu_bench.ps1` samples:
//     `\GPU Engine(pid_<pid>*engtype_3d)\Running Time`, in 100ns ticks,
//     twice N seconds apart. That is where every figure in
//     `docs/architecture/design-tokens.md` now comes from.
//   * Check the adapter before believing anything: the report carries `gpu`
//     from [GpuInfoService]. On the dev machine the 4K display hangs off the
//     motherboard port, so Windows renders this process on the integrated
//     Radeon while the RTX 4080 idles.
//
// Why continuous frames: the raster thread's steady-state cost is only visible
// while frames are actually produced. The ticker's setState returns an
// identical child widget, so `Element.updateChild` short-circuits and the app
// subtree does not rebuild — buildDuration stays near zero.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_effects.dart';
import '../core/app_theme.dart';
import '../core/constants.dart';
import '../services/gpu_info_service.dart';
import '../widgets/app_window_frame.dart';
import '../widgets/glass/app_glass.dart';
import '../widgets/baked_backdrop.dart';

bool get benchEnabled => Platform.environment['RBENCH'] == '1';

int get _frames => int.tryParse(Platform.environment['RBENCH_FRAMES'] ?? '') ?? 400;
int get _warmup => int.tryParse(Platform.environment['RBENCH_WARMUP'] ?? '') ?? 120;
String get _label => Platform.environment['RBENCH_LABEL'] ?? 'run';
String? get _out => Platform.environment['RBENCH_OUT'];
String get _scene => Platform.environment['RBENCH_SCENE'] ?? 'app';

Size? get _requestedSize {
  final raw = Platform.environment['RBENCH_SIZE'];
  if (raw == null) return null;
  final parts = raw.split('x');
  if (parts.length != 2) return null;
  final w = double.tryParse(parts[0]);
  final h = double.tryParse(parts[1]);
  return (w == null || h == null) ? null : Size(w, h);
}

/// Wrap the root widget. Returns [child] untouched unless RBENCH=1.
Widget maybeWrapWithBench(Widget child) {
  if (!benchEnabled) return child;
  final scene = benchScene();
  return _BenchDriver(child: scene ?? _maybeCover(child));
}

/// `app-covered` / `app-covered-gated`: the real app under a full-window
/// opaque black surface — what the media-preview lightbox does, since it is
/// pushed with `opaque: false` over a `Scaffold(backgroundColor: black)` and
/// an [Overlay] only stops painting downwards at an *opaque* entry.
///
/// `-gated` is the fix: the shell stops painting once something fully covers
/// it. Both render the identical final image, so the difference between them
/// is the whole cost of the invisible work.
Widget _maybeCover(Widget child) {
  final covered = _scene == 'app-covered';
  final gated = _scene == 'app-covered-gated';
  if (!covered && !gated) return child;
  return Stack(
    fit: StackFit.expand,
    children: [
      Visibility(
        visible: !gated,
        maintainState: true,
        maintainSize: true,
        maintainAnimation: true,
        child: child,
      ),
      const ColoredBox(color: Color(0xFF000000)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Bisection scenes. Every one renders at the same window size as the real app,
// so the numbers are comparable. `blank` is the floor: if it is not ~0.2-0.5ms
// the measurement is wrong, not the app.
// ---------------------------------------------------------------------------
Widget? benchScene() {
  switch (_scene) {
    case 'blank':
      return _scaffold(const SizedBox.expand());

    // P2 — the window ground as it ships: ColoredBox + two RadialGradients +
    // one LinearGradient, each SizedBox.expand, the last three alpha-blended
    // over the one below.
    case 'aurora':
      return _scaffold(const AuroraBackdrop());

    // P2 after — the same recipe baked once into a quarter-resolution image
    // and drawn as one textured quad.
    case 'aurora-baked':
      return _scaffold(const BakedAuroraBackdrop(child: SizedBox.expand()));

    // The same bake sampled bilinearly instead of trilinearly.
    case 'aurora-baked-low':
      return _scaffold(const BakedAuroraBackdrop(
        filterQuality: FilterQuality.low,
        child: SizedBox.expand(),
      ));

    // Control for "three full-window translucent draws". If this is cheap and
    // `aurora` is not, the gradient shader is the cost, not the alpha blend.
    case 'aurora-solid':
      return _scaffold(const ColoredBox(
        color: Color(0xFFEBEAE6),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0x0F635BFF)),
          child: DecoratedBox(
            decoration: BoxDecoration(color: Color(0x0A635BFF)),
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0x8CFFFFFF)),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ));

    // The aurora with no glass, so the glass ladder below has a floor that
    // already includes the ground it samples.
    case 'glass0':
      return _glassLadder(0);
    case 'glass1':
      return _glassLadder(1);
    case 'glass2':
      return _glassLadder(2);
    case 'glass3':
      return _glassLadder(3);
    // Four live backdrop filters — the count the workbench carries while a
    // task runs and something is selected.
    case 'glass4':
      return _glassLadder(4);

    default:
      return null;
  }
}

Widget _scaffold(Widget body) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        accent: AppConstants.presetThemes[AppConstants.defaultThemeAccentKey]!,
        brightness: Brightness.light,
      ),
      home: AppEffects(
        reduceVisualEffects: false,
        child: Scaffold(body: body),
      ),
    );

/// [n] full-width G1 bars of real [AppGlass] over the real [AuroraBackdrop].
///
/// Bars rather than the app's actual mix of one bar and three floats: a float
/// only samples the fraction of the target it covers, and the point of the
/// ladder is the per-filter pass cost. Using the same grade for all four keeps
/// the only variable the number of filters.
///
/// What it measured, maximized at 4K on the integrated Radeon (GPU ms/frame,
/// from the engine counter): 0 filters 9.90 · 1 10.16 · 2 10.51 · 3 10.78 ·
/// 4 11.19. So a full-width G1 blur costs about **0.32 ms**, not the ~19 ms
/// this project's design note used to claim, and four of them are 1.3 ms of an
/// 11 ms frame. `BackdropGroup` + `BackdropFilter.grouped` across all four
/// measured 11.20 against 11.19 — no saving, which is why `AppGlass` carries
/// no `grouped` flag. Do not re-open that without re-running this ladder.
Widget _glassLadder(int n) {
  final Widget stack = Stack(
    fit: StackFit.expand,
    children: [
      const AuroraBackdrop(),
      for (int i = 0; i < n; i++)
        Positioned(
          left: 0,
          right: 0,
          top: 40.0 + i * 120,
          height: 56,
          child: const AppGlass(
            grade: GlassGrade.bar,
            edges: GlassEdges.bottom,
            shadow: false,
            child: SizedBox.expand(),
          ),
        ),
    ],
  );
  return _scaffold(stack);
}

// ---------------------------------------------------------------------------

class _BenchDriver extends StatefulWidget {
  const _BenchDriver({required this.child});

  final Widget child;

  @override
  State<_BenchDriver> createState() => _BenchDriverState();
}

class _BenchDriverState extends State<_BenchDriver> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<FrameTiming> _timings = [];
  int _seen = 0;
  bool _done = false;
  bool _sized = false;
  Stopwatch? _wall;
  String? _gpu;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => setState(() {}))..start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prepare()));
  }

  /// The window size has to settle before sampling starts: fill cost is
  /// area-driven, so percentiles taken across a resize are meaningless.
  Future<void> _prepare() async {
    _gpu = await GpuInfoService().activeGpuName();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _applyWindowSize(_requestedSize);
    // Let the resize-triggered reallocation of render targets settle.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _sized = true;
  }

  Future<void> _applyWindowSize(Size? size) async {
    await windowManager.ensureInitialized();
    for (var attempt = 0; attempt < 10; attempt++) {
      if (size == null) {
        if (await windowManager.isMaximized()) break;
        await windowManager.maximize();
      } else {
        if (await windowManager.isMaximized()) await windowManager.unmaximize();
        await windowManager.setSize(size);
        final actual = await windowManager.getSize();
        if ((actual.width - size.width).abs() < 2 &&
            (actual.height - size.height).abs() < 2) {
          break;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await windowManager.show();
    await windowManager.focus();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_done || !_sized) return;
    for (final t in timings) {
      _seen++;
      if (_seen <= _warmup) continue;
      if (_seen == _warmup + 1) _wall = Stopwatch()..start();
      _timings.add(t);
      if (_timings.length >= _frames) {
        _done = true;
        _report();
        return;
      }
    }
  }

  double _pct(List<double> sorted, double p) =>
      sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];

  Map<String, double> _stats(Iterable<double> values) {
    final sorted = values.toList()..sort();
    return {
      'p50': _pct(sorted, 0.50),
      'p90': _pct(sorted, 0.90),
      'p99': _pct(sorted, 0.99),
      'max': sorted.isEmpty ? 0 : sorted.last,
    };
  }

  void _report() {
    _ticker.stop();
    final wallMs = (_wall?.elapsedMicroseconds ?? 0) / 1000.0;
    double ms(Duration d) => d.inMicroseconds / 1000.0;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final report = <String, Object?>{
      'label': _label,
      'scene': _scene,
      'frames': _timings.length,
      'fps': wallMs > 0 ? _timings.length / (wallMs / 1000.0) : 0,
      'build': _stats(_timings.map((t) => ms(t.buildDuration))),
      'raster': _stats(_timings.map((t) => ms(t.rasterDuration))),
      'totalSpan': _stats(_timings.map((t) => ms(t.totalSpan))),
      'devicePixelRatio': view.devicePixelRatio,
      'renderTarget': '${view.physicalSize.width.toStringAsFixed(0)}x'
          '${view.physicalSize.height.toStringAsFixed(0)}',
      'megapixels': (view.physicalSize.width * view.physicalSize.height) / 1e6,
      'gpu': _gpu,
      'layers': countLayers(),
    };
    final json = const JsonEncoder.withIndent('  ').convert(report);
    stdout.writeln('RBENCH_RESULT $json');
    final out = _out;
    if (out != null) {
      try {
        File(out).writeAsStringSync(json);
      } catch (_) {
        // A report that cannot be written must not take down the benchmark.
      }
    }
    Future<void>.delayed(const Duration(milliseconds: 250), () => exit(0));
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Tally the composited layer tree by type.
///
/// The ones that force a full-size offscreen pass — and so predict the frame
/// time — are `BackdropFilterLayer`, `ImageFilterLayer`, `ColorFilterLayer`,
/// `OpacityLayer` and antialiasing clip layers. `PictureLayer`, `OffsetLayer`
/// and `TransformLayer` are free.
///
/// This is the count that matters, and it is not the one
/// `rebuild_scope_test.dart` pins: that test counts `BackdropFilter` *widgets*,
/// which includes the selection bar and the task capsule while they sit at
/// opacity 0 and paint nothing.
///
/// Reads `RenderView.layer` rather than `debugLayer`, which is assert-guarded
/// and therefore null in profile builds — where the numbers mean anything.
Map<String, int> countLayers() {
  final counts = <String, int>{};
  void walk(Layer? layer) {
    while (layer != null) {
      final name = layer.runtimeType.toString();
      counts[name] = (counts[name] ?? 0) + 1;
      if (layer is ContainerLayer) walk(layer.firstChild);
      layer = layer.nextSibling;
    }
  }

  for (final view in RendererBinding.instance.renderViews) {
    // `layer` is @protected, but it is the only accessor that returns the real
    // layer in a profile build (`debugLayer` is assert-guarded, so null
    // there) — and profile is the only mode where these numbers mean anything.
    // ignore: invalid_use_of_protected_member
    walk(view.layer);
  }
  return Map.fromEntries(
    counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
}
