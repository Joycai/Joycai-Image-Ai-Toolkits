import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_disclosure_chevron.dart';

/// Both trees' chevrons turn rather than swap glyphs (`plans/README.md`).
void main() {
  Future<void> pump(WidgetTester tester, bool open, {bool reduce = false}) =>
      tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Center(child: AppDisclosureChevron(open: open, size: 14)),
        ),
      ));

  double turns(WidgetTester tester) => tester
      .widget<RotationTransition>(find.descendant(
        of: find.byType(AnimatedRotation),
        matching: find.byType(RotationTransition),
      ))
      .turns
      .value;

  testWidgets('one glyph, turned a quarter when open, tweened on the way', (tester) async {
    await pump(tester, false);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(turns(tester), 0);

    await pump(tester, true);
    await tester.pump(const Duration(milliseconds: 60));
    expect(turns(tester), inExclusiveRange(0, 0.25));
    await tester.pumpAndSettle();
    expect(turns(tester), 0.25);
    expect(find.byIcon(Icons.expand_more), findsNothing, reason: 'no glyph swap');
  });

  testWidgets('under reduce-motion it turns at once', (tester) async {
    await pump(tester, false, reduce: true);
    await pump(tester, true, reduce: true);
    await tester.pump();
    expect(turns(tester), 0.25);
  });
}
