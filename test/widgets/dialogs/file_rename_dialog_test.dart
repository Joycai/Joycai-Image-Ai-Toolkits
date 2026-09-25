import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/dialogs/file_rename_dialog.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_button.dart';
import 'package:path/path.dart' as p;

/// The 「文件 ▸ 重命名」 dialog (`A1 · 2b`), which the gallery card's menu and
/// the file browser's both open.
void main() {
  late Directory dir;
  late String target;
  late BuildContext host;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('joycai_rename_dialog_test');
    target = p.join(dir.path, 'IMG_2041.png');
    File(target).writeAsStringSync('a');
    File(p.join(dir.path, 'hero_final.png')).writeAsStringSync('b');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Left for the OS cleaner.
    }
  });

  Future<void> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              host = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }

  Finder renameButton() => find.widgetWithText(AppButton, 'Rename');

  bool renameEnabled(WidgetTester tester) =>
      tester.widget<AppButton>(renameButton()).onPressed != null;

  Future<void> open(WidgetTester tester, {VoidCallback? onSuccess}) async {
    // Not awaited: the future resolves only when the dialog pops.
    unawaited(showFileRenameDialog(context: host, filePath: target, onSuccess: onSuccess ?? () {}));
    await tester.pumpAndSettle();
  }

  testWidgets('opens with the stem selected, the extension locked beside it, and the hint row', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester);

    expect(find.byType(FileRenameDialog), findsOneWidget);
    final EditableText field = tester.widget(find.byType(EditableText));
    expect(field.controller.text, 'IMG_2041');
    expect(field.controller.selection, const TextSelection(baseOffset: 0, extentOffset: 8));
    expect(find.text('.png'), findsOneWidget);
    expect(find.text('Enter to confirm · Esc to cancel'), findsOneWidget);
    expect(find.text('12 / $kFileRenameMaxLength'), findsOneWidget);
    // The name is unchanged, so there is nothing to do yet.
    expect(renameEnabled(tester), isFalse);
  });

  testWidgets('a name already in the folder disables Rename and says so in place of the hint', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester);

    await tester.enterText(find.byType(EditableText), 'hero_final');
    await tester.pump();

    expect(find.text('hero_final.png already exists in this folder'), findsOneWidget);
    expect(find.text('Enter to confirm · Esc to cancel'), findsNothing);
    expect(renameEnabled(tester), isFalse);

    // Enter does nothing while the name is unusable.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(FileRenameDialog), findsOneWidget);
    expect(File(target).existsSync(), isTrue);
  });

  testWidgets('illegal characters and an empty name are refused the same way', (tester) async {
    await pumpHost(tester);
    await open(tester);

    await tester.enterText(find.byType(EditableText), 'a/b');
    await tester.pump();
    expect(find.textContaining('Name cannot contain'), findsOneWidget);
    expect(renameEnabled(tester), isFalse);

    await tester.enterText(find.byType(EditableText), '   ');
    await tester.pump();
    expect(find.text('Name cannot be empty'), findsOneWidget);
    expect(renameEnabled(tester), isFalse);
  });

  testWidgets('Enter on a usable name renames the file and reports back', (tester) async {
    await pumpHost(tester);
    var succeeded = false;
    await open(tester, onSuccess: () => succeeded = true);

    await tester.enterText(find.byType(EditableText), 'cover');
    await tester.pump();
    expect(renameEnabled(tester), isTrue);

    // The rename is real dart:io, which only completes on the real clock.
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(find.byType(FileRenameDialog), findsNothing);
    expect(File(p.join(dir.path, 'cover.png')).existsSync(), isTrue);
    expect(File(target).existsSync(), isFalse);
    expect(succeeded, isTrue);
  });

  testWidgets('the lock sits at the right edge of the field', (tester) async {
    // A short name leaves the field mostly empty, which is where the lock
    // used to float off the edge: a spacer shared the room with the text.
    target = p.join(dir.path, 'a.png');
    File(target).writeAsStringSync('a');
    await pumpHost(tester);
    await open(tester);

    final Rect field = tester.getRect(
      find.ancestor(of: find.byType(EditableText), matching: find.byType(AnimatedContainer)),
    );
    final Rect lock = tester.getRect(find.byIcon(Icons.lock_outline));
    final Rect label = tester.getRect(find.text('extension'));
    expect(lock.left, greaterThan(field.center.dx));
    // Only the field's border and the toggle's own padding past the label.
    expect(field.right - label.right, lessThanOrEqualTo(12));
  });

  testWidgets('tapping the lock puts the extension in the field and renames it too', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester);

    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pump();

    final EditableText field = tester.widget(find.byType(EditableText));
    expect(field.controller.text, 'IMG_2041.png');
    // The extension is selected, the dot left out.
    expect(field.controller.selection, const TextSelection(baseOffset: 9, extentOffset: 12));
    expect(find.text('.png'), findsNothing);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    // Still the same name, so still nothing to do.
    expect(renameEnabled(tester), isFalse);

    await tester.enterText(find.byType(EditableText), 'cover.jpg');
    await tester.pump();
    expect(find.text('9 / $kFileRenameMaxLength'), findsOneWidget);
    expect(renameEnabled(tester), isTrue);

    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(File(p.join(dir.path, 'cover.jpg')).existsSync(), isTrue);
    expect(File(target).existsSync(), isFalse);
  });

  testWidgets('locking again splits the typed extension back out', (tester) async {
    await pumpHost(tester);
    await open(tester);

    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'hero_final.webp');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.lock_open));
    await tester.pump();

    final EditableText field = tester.widget(find.byType(EditableText));
    expect(field.controller.text, 'hero_final');
    expect(find.text('.webp'), findsOneWidget);
    expect(renameEnabled(tester), isTrue);
  });

  testWidgets('Cancel and Rename are the same width', (tester) async {
    for (final locale in const [Locale('en'), Locale('zh')]) {
      await pumpHost(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                host = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await open(tester);

      final buttons = find.byType(AppButton);
      expect(buttons, findsNWidgets(2));
      expect(tester.getSize(buttons.at(0)).width, tester.getSize(buttons.at(1)).width);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Cancel and Escape leave the file alone', (tester) async {
    await pumpHost(tester);
    await open(tester);

    await tester.enterText(find.byType(EditableText), 'cover');
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(FileRenameDialog), findsNothing);

    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(FileRenameDialog), findsNothing);
    expect(File(target).existsSync(), isTrue);
  });
}
