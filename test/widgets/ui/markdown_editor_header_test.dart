import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_switch.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/markdown_editor.dart';

/// The editor's header keeps the view toggle and the expand button against the
/// right edge, whatever width it is given.
///
/// The screenshot harness cannot see this: its config panel is 300 wide, where
/// the header's children fill the line and every alignment looks the same. The
/// bug only showed in a wider panel, so the widths are chosen here.
void main() {
  Future<void> pump(WidgetTester tester, double width, {bool bordered = true}) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: MarkdownEditor(
                controller: TextEditingController(text: 'prompt'),
                label: 'Prompt',
                isMarkdown: true,
                onMarkdownChanged: (_) {},
                bordered: bordered,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The header's inset in the unframed form; see `_buildBodyColumn`.
  const double unframedInset = 10;

  for (final double width in [200, 300, 420, 800]) {
    for (final bool bordered in [true, false]) {
      testWidgets('controls sit at the right edge @ $width, bordered: $bordered', (tester) async {
        await pump(tester, width, bordered: bordered);
        expect(tester.takeException(), isNull);

        final editor = tester.getRect(find.byType(MarkdownEditor));
        final expand = tester.getRect(find.byIcon(Icons.open_in_full));
        final checkbox = tester.getRect(find.byType(AppSwitch));
        final toggle = tester.getRect(find.text('Preview'));

        expect(editor.width, width);
        // The icon sits inside the button's own padding, so allow for it.
        final rightEdge = editor.right - (bordered ? 0 : unframedInset);
        expect(rightEdge - expand.right, inInclusiveRange(0, 16));
        expect(checkbox.left - editor.left, lessThan(16 + unframedInset));
        // One line: the toggle is beside the Markdown switch, not under it.
        expect(toggle.center.dy, closeTo(checkbox.center.dy, 1));
        expect(toggle.right, lessThan(expand.left));
      });
    }
  }
}
