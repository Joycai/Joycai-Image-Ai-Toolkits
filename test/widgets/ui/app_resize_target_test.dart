import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_resize_target.dart';

void main() {
  for (final axis in Axis.values) {
    testWidgets('splitter adjusts and persists via keys and semantics ($axis)', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        var delta = 0.0;
        var saves = 0;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AppResizeTarget(
                axis: axis,
                onDrag: (value) => delta += value,
                onDragEnd: () => saves++,
                child: const SizedBox(width: 20, height: 100),
              ),
            ),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(
          axis == Axis.horizontal ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowDown,
        );
        expect(delta, 20);
        expect(saves, 1);
        final node = tester.getSemantics(find.bySemanticsLabel('Resize pane'));
        final actionIds = node.getSemanticsData().customSemanticsActionIds!;
        final id = actionIds.firstWhere(
          (id) =>
              CustomSemanticsAction.getAction(id)!.label ==
              (axis == Axis.horizontal ? 'Move divider left' : 'Move divider up'),
        );
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.customAction,
          id,
        );
        expect(delta, 0);
        expect(saves, 2);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(saves, 2);
      } finally {
        handle.dispose();
      }
    });
  }
}
