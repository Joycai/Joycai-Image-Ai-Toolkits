import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/mcp_settings_block.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/mcp_server_state.dart';
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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
}
