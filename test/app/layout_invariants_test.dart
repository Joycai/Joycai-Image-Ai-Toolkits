import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/glass_controls.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/app_destinations.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/app_top_bar.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/phone_dock.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_action_target.dart';
import 'package:material_ui/material_ui.dart';

import '../screenshots/harness/fixture_env.dart';
import '../screenshots/harness/fixture_seed.dart';
import '../screenshots/harness/shoot.dart';
import '../screenshots/harness/suite.dart';
import '../support/real_fonts.dart';

/// CI-enforced structural layout invariants across all screens, workbench tabs,
/// responsive breakpoints, themes, and locales — using real app font metrics.
///
/// Unlike the `test/screenshots/` harness (which is excluded from CI via
/// `-x screenshots` and drains exceptions to capture PNGs), these assertions
/// run in `flutter test -x screenshots` and fail the build on any overflow,
/// glass budget violation, or collapsed/off-screen chrome control.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    await ensureRealTestFontsLoaded();
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    final AppState appState = AppState();
    await appState.loadSettings();
    await waitForAppSettle(appState);
    markOneTaskRunning(appState);
  });

  tearDownAll(() => env.dispose());

  bool hasScrollableAncestor(Element element) {
    bool found = false;
    element.visitAncestorElements((Element ancestor) {
      if (ancestor.widget is Scrollable) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  Future<void> auditScreen(
    WidgetTester tester, {
    required AppScreen screen,
    required ShotSize size,
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh'),
    String? labelSuffix,
    Future<void> Function(WidgetTester tester)? before,
  }) async {
    final String tag =
        '${screen.name} @ ${size.label} ${brightness.name} ${locale.toLanguageTag()}'
        '${labelSuffix == null ? '' : ' ($labelSuffix)'}';

    final List<Object> exceptions = await mountApp(
      tester,
      env: env,
      screen: screen,
      size: size.size,
      brightness: brightness,
      locale: locale,
      label: tag,
      warmImages: false,
      before: before,
    );

    expect(exceptions, isEmpty, reason: '[$tag] threw exceptions during pump');

    // Glass layer budget (`docs/architecture/design-tokens.md` §5):
    // at most 1 full-width bar + 3 visible floating/lens glass layers = 4.
    // Hidden overlays (e.g. TaskCapsuleMonitor / GallerySelectionBar at
    // opacity == 0.0) are excluded because RenderAnimatedOpacity does not
    // paint or blur their BackdropFilter.
    bool isVisibleRender(RenderObject ro) {
      RenderObject? current = ro.parent;
      while (current != null) {
        if (current is RenderAnimatedOpacity && current.opacity.value == 0.0) return false;
        if (current is RenderOpacity && current.opacity == 0.0) return false;
        current = current.parent;
      }
      return true;
    }

    final int visibleGlassCount = find.byType(BackdropFilter).evaluate().where((Element e) {
      final RenderObject? ro = e.renderObject;
      return ro is RenderBox && ro.hasSize && !ro.size.isEmpty && isVisibleRender(ro);
    }).length;
    expect(
      visibleGlassCount,
      lessThanOrEqualTo(4),
      reason: '[$tag] exceeded 4-layer BackdropFilter budget ($visibleGlassCount)',
    );

    // Non-scrollable chrome interactive controls must keep positive size and
    // stay inside the window viewport.
    final List<Finder> controlFinders = <Finder>[
      find.byType(FilledButton).hitTestable(),
      find.byType(OutlinedButton).hitTestable(),
      find.byType(TextButton).hitTestable(),
      find.byType(IconButton).hitTestable(),
      find.byType(Switch).hitTestable(),
      find.byType(Checkbox).hitTestable(),
      find.byType(GlassIconButton).hitTestable(),
      find.byType(AppActionTarget).hitTestable(),
    ];

    const double tolerance = 1.5;
    for (final Finder finder in controlFinders) {
      for (final Element element in finder.evaluate()) {
        if (hasScrollableAncestor(element)) continue;
        final RenderObject? ro = element.renderObject;
        if (ro is! RenderBox || !ro.hasSize) continue;
        final Offset topLeft = ro.localToGlobal(Offset.zero);
        final Rect rect = topLeft & ro.size;
        expect(
          rect.width,
          greaterThan(0),
          reason: '[$tag] ${element.widget.runtimeType} collapsed horizontally',
        );
        expect(
          rect.height,
          greaterThan(0),
          reason: '[$tag] ${element.widget.runtimeType} collapsed vertically',
        );
        expect(
          rect.left,
          greaterThanOrEqualTo(-tolerance),
          reason: '[$tag] ${element.widget.runtimeType} clipped left: $rect',
        );
        expect(
          rect.top,
          greaterThanOrEqualTo(-tolerance),
          reason: '[$tag] ${element.widget.runtimeType} clipped top: $rect',
        );
        expect(
          rect.right,
          lessThanOrEqualTo(size.size.width + tolerance),
          reason: '[$tag] ${element.widget.runtimeType} overflowed right: $rect',
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(size.size.height + tolerance),
          reason: '[$tag] ${element.widget.runtimeType} overflowed bottom: $rect',
        );
      }
    }
  }

  group('all screens × all breakpoints (zh light)', () {
    for (final AppScreen screen in AppScreen.values) {
      for (final ShotSize size in kShotSizes) {
        testWidgets('${screen.name} @ ${size.label} light', (WidgetTester tester) async {
          await auditScreen(tester, screen: screen, size: size);
        });
      }
    }
  });

  group('all screens × mobile & desktop (zh dark)', () {
    for (final AppScreen screen in AppScreen.values) {
      for (final ShotSize size in <ShotSize>[kShotSizes.first, kShotSizes.last]) {
        testWidgets('${screen.name} @ ${size.label} dark', (WidgetTester tester) async {
          await auditScreen(tester, screen: screen, size: size, brightness: Brightness.dark);
        });
      }
    }
  });

  group('high-density screens (en light)', () {
    for (final AppScreen screen in const <AppScreen>[
      AppScreen.workbench,
      AppScreen.tasks,
      AppScreen.models,
      AppScreen.settings,
      AppScreen.prompts,
    ]) {
      for (final ShotSize size in <ShotSize>[kShotSizes[0], kShotSizes[2]]) {
        testWidgets('${screen.name} @ ${size.label} en', (WidgetTester tester) async {
          await auditScreen(tester, screen: screen, size: size, locale: const Locale('en'));
        });
      }
    }
  });

  group('workbench all 6 tabs (ipad & desktop)', () {
    for (int tab = 0; tab < 6; tab++) {
      for (final ShotSize size in <ShotSize>[kShotSizes[2], kShotSizes[3]]) {
        testWidgets('workbench tab $tab @ ${size.label}', (WidgetTester tester) async {
          try {
            await auditScreen(
              tester,
              screen: AppScreen.workbench,
              size: size,
              labelSuffix: 'tab=$tab',
              before: (_) async => AppState().setWorkbenchTab(tab),
            );
          } finally {
            await tester.runAsync(() async => AppState().setWorkbenchTab(0));
          }
        });
      }
    }
  });

  group('desktop platform density audit', () {
    for (final AppScreen screen in const <AppScreen>[
      AppScreen.workbench,
      AppScreen.models,
      AppScreen.settings,
      AppScreen.tasks,
    ]) {
      testWidgets('${screen.name} @ windows compact density', (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await auditScreen(tester, screen: screen, size: kShotSizes.last, labelSuffix: 'windows');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  group('mobile platform destination gating', () {
    testWidgets('mobile platform hides desktopOnly destinations at 390 and 834', (
      WidgetTester tester,
    ) async {
      AppDestination.debugIsMobilePlatformOverride = true;
      try {
        expect(AppDestination.available, isNot(contains(AppDestination.fileBrowser)));
        expect(AppDestination.available, isNot(contains(AppDestination.downloader)));

        await auditScreen(
          tester,
          screen: AppScreen.workbench,
          size: kShotSizes[0],
          labelSuffix: 'mobileOS',
        );
        expect(find.byType(PhoneDock), findsOneWidget);

        await auditScreen(
          tester,
          screen: AppScreen.workbench,
          size: kShotSizes[1],
          labelSuffix: 'tabletOS',
        );
        expect(find.byType(AppTopBar), findsOneWidget);
      } finally {
        AppDestination.debugIsMobilePlatformOverride = null;
      }
    });
  });
}
