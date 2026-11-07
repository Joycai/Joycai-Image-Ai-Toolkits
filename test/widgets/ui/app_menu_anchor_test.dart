import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_menu_anchor.dart';

void main() {
  testWidgets('menu and tooltip keep distinct traversal parents through overlay teardown', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final menu = MenuController();
      final tooltip = GlobalKey<TooltipState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                AppMenuAnchor(
                  controller: menu,
                  menuChildren: [
                    MenuItemButton(onPressed: () {}, child: const Text('Menu action')),
                  ],
                  builder: (context, controller, child) => Tooltip(
                    key: tooltip,
                    message: 'Anchor help',
                    child: TextButton(onPressed: controller.open, child: const Text('Open menu')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      List<SemanticsData> data() {
        final result = <SemanticsData>[];
        void collect(SemanticsNode node) {
          result.add(node.getSemanticsData());
          node.visitChildren((child) {
            collect(child);
            return true;
          });
        }

        collect(tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!);
        return result;
      }

      void expectNoOrphanedOverlays() {
        final nodes = data();
        for (final node in nodes) {
          final anchor = node.traversalChildIdentifier;
          if (anchor == null) continue;
          expect(
            nodes.where((parent) => parent.traversalParentIdentifier == anchor),
            hasLength(1),
            reason: 'Every overlay must retain exactly one traversal parent.',
          );
        }
      }

      for (var i = 0; i < 4; i++) {
        menu.open();
        await tester.pumpAndSettle();
        tooltip.currentState!.ensureTooltipVisible();
        await tester.pumpAndSettle();
        expectNoOrphanedOverlays();
        final nodes = data();
        expect(
          nodes.where((node) => node.traversalChildIdentifier != null).length,
          greaterThanOrEqualTo(2),
        );
        expect(nodes.any((node) => node.label == 'Menu action'), isTrue);
        Tooltip.dismissAllToolTips();
        menu.close();
        await tester.pump(const Duration(milliseconds: 20));
        expectNoOrphanedOverlays();
        await tester.pumpAndSettle();
        expectNoOrphanedOverlays();
      }
    } finally {
      semantics.dispose();
    }
  });
}
