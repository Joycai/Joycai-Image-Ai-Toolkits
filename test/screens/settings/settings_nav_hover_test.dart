import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/settings_screen.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

void main() {
  usePrivateDataDir('settings_nav_hover_test');
  useRealAsyncAppState();
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Joycai Image AI Toolkits',
      packageName: 'com.joycai.imageAiToolkits',
      version: '4.31.9',
      buildNumber: '1',
      buildSignature: '',
    );
    await AppState().loadSettings();
  });

  testWidgets(
    'settings nav rows paint ink inside AnimatedContainer without black-transparent lerp',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final theme = buildAppTheme(
        accent: ThemeAccent.fromSeed(Colors.blue),
        brightness: Brightness.light,
      );
      final scheme = theme.colorScheme;

      expect(scheme.navBackground(selected: false).a, 0);
      expect(scheme.navBackground(selected: false).r, closeTo(scheme.accentTint.r, 0.01));
      expect(scheme.navBackground(selected: false).g, closeTo(scheme.accentTint.g, 0.01));
      expect(scheme.navBackground(selected: false).b, closeTo(scheme.accentTint.b, 0.01));

      await pumpWidgetInRealAsync(
        tester,
        ChangeNotifierProvider.value(
          value: AppState(),
          child: MaterialApp(
            theme: theme,
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Locate the unselected Connectivity nav row and its AnimatedContainer / InkWell.
      final connectivityText = find.text('Connectivity').first;
      final rowContainer = find
          .ancestor(of: connectivityText, matching: find.byType(AnimatedContainer))
          .first;
      final rowInkWell = find.ancestor(of: connectivityText, matching: find.byType(InkWell)).first;
      final rowMaterial = find
          .ancestor(of: connectivityText, matching: find.byType(Material))
          .first;

      // InkWell paints inside a transparent Material inside AnimatedContainer so ink
      // layers render above the selection background.
      expect(tester.widget<Material>(rowMaterial).type, MaterialType.transparency);
      expect(
        find.descendant(of: rowContainer, matching: find.byWidget(tester.widget(rowInkWell))),
        findsOneWidget,
      );

      final inkWell = tester.widget<InkWell>(rowInkWell);
      expect(inkWell.hoverDuration, AppMotion.hover);
      expect(inkWell.hoverColor, scheme.onSurface.withValues(alpha: 0.04));

      final container = tester.widget<AnimatedContainer>(rowContainer);
      final decoration = container.decoration! as BoxDecoration;
      final bgColor = decoration.color!;
      final borderColor = (decoration.border! as Border).top.color;

      // Zero-alpha endpoints preserve target RGB (never Colors.transparent 0x00000000).
      expect(bgColor.a, 0);
      expect(bgColor.r, closeTo(scheme.accentTint.r, 0.01));
      expect(bgColor.g, closeTo(scheme.accentTint.g, 0.01));
      expect(bgColor.b, closeTo(scheme.accentTint.b, 0.01));
      expect(borderColor.a, 0);
      expect(borderColor.r, closeTo(scheme.primary.r, 0.01));

      // Mid-transition lerp between unselected and selected holds constant RGB channels.
      final midpoint = Color.lerp(bgColor, scheme.accentTint, 0.5)!;
      expect(midpoint.r, closeTo(scheme.accentTint.r, 0.01));
      expect(midpoint.g, closeTo(scheme.accentTint.g, 0.01));
      expect(midpoint.b, closeTo(scheme.accentTint.b, 0.01));

      // Hovering triggers no exception and paints cleanly via InkWell.hoverDuration.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(connectivityText));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
