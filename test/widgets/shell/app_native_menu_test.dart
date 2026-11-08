import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/app_native_menu.dart';

void main() {
  const channel = MethodChannel('joycai/native_menu');
  final calls = <MethodCall>[];
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  Future<void> command(String id) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('command', id)),
      (_) {},
    );
  }

  testWidgets('native commands follow route state, reject stale dispatch and recover after pop', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final destinations = <int>[];
    var shortcuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppNativeMenu(
          onNavigate: destinations.add,
          onShortcuts: () => shortcuts++,
          child: const Scaffold(body: TextField()),
        ),
      ),
    );
    Map<Object?, Object?> payload() =>
        calls.lastWhere((c) => c.method == 'update').arguments as Map;
    List<Map> commands() => (payload()['commands'] as List).cast<Map>();
    expect(commands().length, 10);
    expect(commands().every((c) => c['enabled'] == true), isTrue);
    expect(commands().first['key'], ',');
    expect(commands().first['command'], true);
    await command('openSettings');
    await command('destination:1');
    await command('showShortcutPanel');
    await command('destination:99');
    expect(destinations, [7, 1]);
    expect(shortcuts, 1);

    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    expect(commands().every((c) => c['enabled'] == false), isTrue);
    await command('openSettings');
    await command('showShortcutPanel');
    expect(destinations, [7, 1]);
    expect(shortcuts, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(commands().every((c) => c['enabled'] == true), isTrue);
    await command('destination:0');
    expect(destinations, [7, 1, 0]);
    await tester.pumpWidget(const SizedBox());
    expect(calls.last.method, 'disable');
    await command('openSettings');
    expect(destinations, [7, 1, 0]);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('menu labels update in all four app languages without remounting', (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, _) => MaterialApp(
          locale: value,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppNativeMenu(onNavigate: (_) {}, onShortcuts: () {}, child: const SizedBox()),
        ),
      ),
    );
    for (final entry in {
      const Locale('en'): 'Settings…',
      const Locale('zh'): '设置…',
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'): '設定…',
      const Locale('ja'): '設定…',
    }.entries) {
      locale.value = entry.key;
      await tester.pumpAndSettle();
      final payload = calls.lastWhere((c) => c.method == 'update').arguments as Map;
      expect((payload['labels'] as Map)['BOF-NM-1cW'], entry.value);
      expect((payload['commands'] as List).first['label'], entry.value);
    }
    expect(calls.where((c) => c.method == 'disable'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('Undo and Redo follow the focused text field, including a modal', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final field = TextEditingController();
    addTearDown(field.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppNativeMenu(onNavigate: (_) {}, onShortcuts: () {}, child: const Scaffold()),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: TextField(controller: field, autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'first');
    // UndoHistory coalesces typing before publishing a new undo checkpoint.
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pump(const Duration(seconds: 1));
    await command('undo');
    await tester.pump();
    expect(field.text, 'first');
    await command('redo');
    await tester.pump();
    expect(field.text, 'second');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await command('undo');
    expect(field.text, 'second', reason: 'A blurred field must not receive an undo command.');
    await tester.pumpWidget(const SizedBox());
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('other platforms leave the native menu channel untouched', (tester) async {
    await tester.pumpWidget(
      AppNativeMenu(onNavigate: (_) {}, onShortcuts: () {}, child: const SizedBox()),
    );
    await tester.pumpWidget(const SizedBox());
    expect(calls, isEmpty);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));
}
