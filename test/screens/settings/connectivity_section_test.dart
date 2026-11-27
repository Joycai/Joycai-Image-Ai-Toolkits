import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/connectivity_section.dart';
import 'package:joycai_image_ai_toolkits/services/system/proxy_probe_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

void main() {
  usePrivateDataDir('connectivity_section_test');
  useRealAsyncAppState();
  setUpAll(() => AppState().loadSettings());

  Widget buildHarness({required ProxyProbeService probeService, bool isMobile = false}) {
    return ChangeNotifierProvider.value(
      value: AppState(),
      child: MaterialApp(
        theme: buildAppTheme(
          accent: ThemeAccent.fromSeed(Colors.blue),
          brightness: Brightness.light,
        ),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConnectivitySection(isMobile: isMobile, probeService: probeService),
          ),
        ),
      ),
    );
  }

  testWidgets('proxy accordion expands/collapses and probe result updates on edit', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final state = AppState();

    var shouldFail = false;
    final probe = ProxyProbeService(
      connector: (host, port, timeout) async {
        if (shouldFail) {
          throw const SocketException(
            'Connection refused',
            osError: OSError('Connection refused', 61),
          );
        }
      },
    );

    await runAsyncRethrowing(tester, () async {
      await state.saveSetting('proxy_enabled', 'false');
      await state.saveSetting('proxy_url', '127.0.0.1:7890');
      await tester.pumpWidget(buildHarness(probeService: probe));
      await databaseIdle();
    });
    await tester.pumpAndSettle();

    expect(find.text(l10n.proxyStatusDisabled), findsOneWidget);
    expect(find.byKey(const Key('proxy-url')), findsNothing);

    await inRealAsync(tester, () => tester.tap(find.byKey(const Key('proxy-enabled-switch'))));
    await tester.pumpAndSettle();

    expect(find.text(l10n.proxyStatusEnabled), findsOneWidget);
    expect(find.byKey(const Key('proxy-url')), findsOneWidget);
    final savedEnabled = await runAsyncRethrowing(tester, () => state.getSetting('proxy_enabled'));
    expect(savedEnabled, 'true');

    await tester.tap(find.byKey(const Key('proxy-test-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('proxy-probe-result')), findsOneWidget);
    expect(find.textContaining('Proxy reachable'), findsOneWidget);

    await inRealAsync(
      tester,
      () => tester.enterText(find.byKey(const Key('proxy-url')), '127.0.0.1:7891'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('proxy-probe-result')), findsNothing);

    shouldFail = true;
    await tester.tap(find.byKey(const Key('proxy-test-button')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.proxyTestRefused), findsOneWidget);

    await inRealAsync(tester, () => tester.tap(find.byKey(const Key('proxy-enabled-switch'))));
    await tester.pumpAndSettle();
    expect(find.text(l10n.proxyStatusDisabled), findsOneWidget);
    expect(find.byKey(const Key('proxy-url')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
