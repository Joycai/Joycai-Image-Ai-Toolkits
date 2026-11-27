import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/mcp_settings_block.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/mcp_server_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';
import '../../support/real_async.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late DatabaseService db;
  late TaskQueueService queue;
  late McpServerState state;
  String? clipboard;
  setUp(() async {
    db = await openTestDatabase();
    queue = TaskQueueService(database: db);
    await queue.ready;
    state = McpServerState(queue: queue, database: db);
    await state.load();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    await state.shutdown();
    state.dispose();
    queue.dispose();
    await closeTestDatabase(db);
  });

  testWidgets('invalid port is explained and copy uses applied configuration with its token', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          accent: ThemeAccent.fromSeed(Colors.blue),
          brightness: Brightness.light,
        ),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(child: McpSettingsBlock(server: state)),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('mcp-port')), 'abc');
    await tester.tap(find.text('Apply settings'));
    await tester.pump();
    expect(find.text('Use a port from 1024 to 65535.'), findsOneWidget);
    await tester.tap(find.text('Copy connection configuration'));
    await tester.pumpAndSettle();
    final config = jsonDecode(clipboard!) as Map;
    final connection = config['mcpServers']['joycai-images'] as Map;
    expect(connection['url'], 'http://127.0.0.1:39287/mcp');
    expect((connection['headers'] as Map)['Authorization'], startsWith('Bearer '));
    expect(find.text('Copied'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.enterText(find.byKey(const Key('mcp-port')), '39288');
    await inRealAsyncUntil(
      tester,
      () => tester.tap(find.text('Apply settings')),
      until: () => !state.busy,
    );
    expect(state.port, 39288);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'token reveal/copy, endpoint preview/copy, dual-view folder sync, and rotate confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(960, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            accent: ThemeAccent.fromSeed(Colors.blue),
            brightness: Brightness.light,
          ),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: McpSettingsBlock(
                server: state,
                onPickFolder: () async => '/Users/demo/PickedRefs',
              ),
            ),
          ),
        ),
      );

      // Masked token shown by default; toggle shows raw token; copy sets clipboard.
      expect(find.text(state.maskedToken), findsOneWidget);
      expect(find.text(state.token), findsNothing);
      await tester.tap(find.byKey(const Key('mcp-token-visibility')));
      await tester.pump();
      expect(find.text(state.token), findsOneWidget);
      await tester.tap(find.byKey(const Key('mcp-token-copy')));
      await tester.pumpAndSettle();
      expect(clipboard, state.token);

      // Draft port updates endpoint preview immediately and shows unsaved badge.
      await tester.enterText(find.byKey(const Key('mcp-port')), '40100');
      await tester.pump();
      expect(find.text('http://127.0.0.1:40100/mcp'), findsOneWidget);
      expect(find.text(l10n.mcpUnsavedChanges), findsOneWidget);
      await tester.tap(find.byKey(const Key('mcp-copy-endpoint')));
      await tester.pumpAndSettle();
      expect(clipboard, 'http://127.0.0.1:40100/mcp');

      // List view empty state -> inline add via browse + confirm -> syncs to plain text view.
      expect(find.text(l10n.mcpFoldersEmpty), findsOneWidget);
      await tester.tap(find.byKey(const Key('mcp-add-folder-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mcp-browse-folder-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mcp-confirm-add-folder')));
      await tester.pumpAndSettle();

      expect(find.text('/Users/demo/PickedRefs/**'), findsOneWidget);
      expect(find.text(l10n.mcpFolderRecursive), findsOneWidget);

      await tester.tap(find.text(l10n.mcpFoldersViewText));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.descendant(of: find.byKey(const Key('mcp-folders')), matching: find.byType(TextField)),
      );
      expect(field.controller?.text, '/Users/demo/PickedRefs/**');

      // Editing plain text updates list badges when switching back to list view.
      await tester.enterText(
        find.byKey(const Key('mcp-folders')),
        '/Users/demo/PickedRefs/**\n/Users/demo/DirectOnly/*',
      );
      await tester.tap(find.text(l10n.mcpFoldersViewList));
      await tester.pumpAndSettle();
      expect(find.text('/Users/demo/DirectOnly/*'), findsOneWidget);
      expect(find.text(l10n.mcpFolderDirectOnly), findsOneWidget);

      // Remove second row.
      await tester.tap(find.byKey(const Key('mcp-remove-folder-1')));
      await tester.pumpAndSettle();
      expect(find.text('/Users/demo/DirectOnly/*'), findsNothing);

      // Rotate token requires confirmation: cancel preserves token, confirm rotates it.
      final originalToken = state.token;
      await inRealAsync(tester, () => tester.tap(find.byKey(const Key('mcp-rotate-token'))));
      await tester.pumpAndSettle();
      expect(find.text(l10n.mcpRotateTokenConfirmTitle), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(state.token, originalToken);

      await inRealAsync(tester, () => tester.tap(find.byKey(const Key('mcp-rotate-token'))));
      await tester.pumpAndSettle();
      await inRealAsyncUntil(
        tester,
        () => tester.tap(find.byKey(const Key('mcp-confirm-rotate-token'))),
        until: () => !state.busy && state.token != originalToken,
      );
      expect(state.token, isNot(originalToken));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
