// What the workbench does when it deletes a file.
//
//   flutter test test/screenshots/workbench_delete_scope_test.dart
//
// Beside the screenshot harness because it needs the real app tree: the thing
// under test is which dialog a menu row opens, and that only exists once the
// whole screen is standing. Asserts, so it stays in the gate and is not
// tagged `screenshots`.
//
// The workbench used to delete with its own implementation — a one-line
// confirmation and, on macOS and Linux, `File.delete()`. The browser sent the
// same file to the trash. Unifying the shortcut meant unifying that first,
// and this test is what keeps the second implementation from growing back.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/gallery/image_card.dart';
import 'package:joycai_image_ai_toolkits/services/files/trash_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/files/transfer_dialog_parts.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass_menu.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dialog.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    TrashService.overrideSupport(true);
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    await AppState().loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() {
    TrashService.overrideSupport(null);
    env.dispose();
  });

  testWidgets('the gallery deletes through the shared confirmation', (
    WidgetTester tester,
  ) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 900),
      label: 'workbench-delete-scope',
    );

    expect(find.byType(ImageCard), findsWidgets,
        reason: 'the gallery needs something to delete');

    await tester.tap(find.byType(ImageCard).first, buttons: kSecondaryButton);
    await settle(tester);

    final Finder deleteRow = find.descendant(
      of: find.byType(AppGlassMenu),
      matching: find.text('删除'),
    );
    expect(deleteRow, findsOneWidget,
        reason: 'the row no longer says 「移到回收站」 on Windows and 「删除」 '
            'elsewhere — the dialog is what names the outcome now');

    // The shared run asks the filesystem whether a trash exists before it can
    // word the confirmation, and that answer only arrives out here.
    await tester.tap(deleteRow);
    await settle(tester);
    // The shared run asks whether a trash exists before it can word the
    // confirmation, and that answer only arrives out here.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await settle(tester, 12);

    expect(find.byType(AppDialog), findsOneWidget);
    // The shared dialog's heading — the old one-line workbench confirmation
    // had no such thing, so this is the proof the two paths are one.
    expect(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.byType(TransferDialogHeading),
      ),
      findsOneWidget,
      reason: 'the workbench must be showing the browser\'s delete dialog',
    );
    expect(find.text('删除文件？'), findsNothing,
        reason: 'that was the old one-line confirmation, whose macOS branch '
            'deleted permanently');
    // The point of the unification, in one assertion: where the platform has
    // a trash, the workbench offers the trash. The old implementation said
    // 「删除文件？」 here and then called `File.delete()` on everything but
    // Windows. (`TrashService` is forced on because a `flutter test` process
    // has no native side, so macOS would otherwise report no trash.)
    expect(find.text('移到回收站？'), findsOneWidget);
  });
}
