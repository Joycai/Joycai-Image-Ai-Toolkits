import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_distribution.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/application_section.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  usePrivateDataDir('application_section_distribution_test');
  useRealAsyncAppState();
  setUpAll(() async {
    await AppState().loadSettings();
    await AppState().galleryState.settingsLoaded;
  });

  const channel = MethodChannel('joycai/directory_access');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('Full Disk Access is direct-only and authorized folders dialog revokes grants', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final grants = [
      {'path': '/Users/demo/Output', 'readOnly': false},
      {'path': '/Users/demo/Reference', 'readOnly': true},
    ];
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'list':
          return List<Map<String, dynamic>>.from(grants);
        case 'revoke':
          final target = call.arguments['path'] as String?;
          final before = grants.length;
          grants.removeWhere((g) => g['path'] == target);
          return grants.length != before;
        case 'revokeAll':
          final count = grants.length;
          grants.clear();
          return count;
        default:
          return null;
      }
    });

    final l10n = lookupAppLocalizations(const Locale('en'));
    await pumpWidgetInRealAsync(
      tester,
      ChangeNotifierProvider.value(
        value: AppState(),
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: ApplicationSection())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.macFullDiskAccess),
      AppDistribution.direct ? findsOneWidget : findsNothing,
    );
    expect(find.text(l10n.macAuthorizedFolders), findsOneWidget);

    await tester.ensureVisible(find.text(l10n.macManageAuthorizedFolders));
    await tester.tap(find.text(l10n.macManageAuthorizedFolders));
    await tester.pumpAndSettle();

    expect(find.text('/Users/demo/Output'), findsOneWidget);
    expect(find.text('/Users/demo/Reference'), findsOneWidget);
    expect(find.text(l10n.macAuthorizedFolderReadOnly), findsOneWidget);

    await tester.tap(find.text(l10n.macRevokeFolderAccess).last);
    await tester.pumpAndSettle();

    expect(find.text('/Users/demo/Output'), findsOneWidget);
    expect(find.text('/Users/demo/Reference'), findsNothing);

    await tester.tap(find.text(l10n.macRevokeAllFolderAccess));
    await tester.pumpAndSettle();

    expect(find.text(l10n.macNoAuthorizedFolders), findsOneWidget);
    expect(find.text(l10n.macRevokeAllFolderAccess), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isMacOS);
}
