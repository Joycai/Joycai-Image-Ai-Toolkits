import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass_menu.dart';

/// A glass menu lands where it was asked to even when the navigator is not
/// the whole window.
///
/// The app's custom window frame wraps the navigator through
/// `MaterialApp.builder`, so the overlay a menu route is laid out in starts
/// under the title bar. Callers pass global points — a pointer position, a
/// button's `localToGlobal` — and the menu was drawn one title bar lower
/// than every one of them.
void main() {
  const double bar = 36;
  final GlobalKey button = GlobalKey();

  Widget app() => MaterialApp(
        builder: (context, child) => Column(
          children: [
            const SizedBox(height: bar, width: double.infinity),
            Expanded(child: child!),
          ],
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 120, top: 80),
              child: Builder(
                builder: (context) => SizedBox(
                  key: button,
                  width: 100,
                  height: 28,
                  child: GestureDetector(
                    onTap: () {
                      final box = context.findRenderObject()! as RenderBox;
                      showAppGlassMenu(
                        context,
                        position: box.localToGlobal(Offset(0, box.size.height + 4)),
                        entries: const [
                          AppGlassMenuItem(label: 'one', checked: true, radio: true),
                          AppGlassMenuItem(label: 'two', checked: false, radio: true),
                        ],
                      );
                    },
                    child: const ColoredBox(color: Colors.red),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('a menu below a button hangs 4px under it, title bar or not', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(button));
    await tester.pumpAndSettle();

    final Rect buttonRect = tester.getRect(find.byKey(button));
    final Rect menuRect = tester.getRect(find.byType(AppGlassMenu));
    expect(menuRect.left, closeTo(buttonRect.left, 0.01));
    expect(menuRect.top, closeTo(buttonRect.bottom + 4, 0.01));
  });

  testWidgets('the same point without a frame lands in the same place', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAppGlassMenu(
                context,
                position: const Offset(200, 150),
                entries: const [AppGlassMenuItem(label: 'one')],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(AppGlassMenu)), const Offset(200, 150));
  });
}
