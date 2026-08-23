import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_button.dart';
import 'package:joycai_image_ai_toolkits/widgets/dialogs/image_size_picker_dialog.dart';

/// Covers the gpt-image-2 size picker's ratio calculator: "16:9 at 3840"
/// has to come back as a size that passes all four of OpenAI's rules, with
/// the long edge corrected onto the 16-px grid rather than the user doing
/// that arithmetic themselves.
void main() {
  group('parseAspectRatio', () {
    test('reads a:b, and keeps the orientation the terms imply', () {
      expect(parseAspectRatio('16:9')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('16:9')!.portrait, isFalse);
      expect(parseAspectRatio('9:16')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('9:16')!.portrait, isTrue);
    });

    test('accepts x, × and / as separators, and a bare decimal', () {
      expect(parseAspectRatio('16x9')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('16×9')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('16/9')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('1.85')!.portrait, isFalse);
      expect(parseAspectRatio('0.5625')!.portrait, isTrue);
      expect(parseAspectRatio('0.5625')!.longOverShort, closeTo(1.778, 0.001));
    });

    test('rejects what it cannot read', () {
      for (final bad in ['', '  ', '16:', ':9', '0:9', '16:0', 'abc', '-2']) {
        expect(parseAspectRatio(bad), isNull, reason: bad);
      }
    });
  });

  group('formatAspectRatio', () {
    test('reduces to readable terms', () {
      expect(formatAspectRatio(3840, 2160), '16:9');
      expect(formatAspectRatio(2160, 3840), '9:16');
      expect(formatAspectRatio(1024, 1024), '1:1');
      expect(formatAspectRatio(1536, 1024), '3:2');
    });

    test('falls back to a decimal when the terms get unreadable', () {
      expect(formatAspectRatio(1000, 1234), '0.81');
    });
  });

  group('sizeForAspectRatio', () {
    (int, int) compute(String ratio, int longEdge) =>
        sizeForAspectRatio(parseAspectRatio(ratio)!, longEdge);

    test('hits the exact size when the ratio divides cleanly', () {
      expect(compute('16:9', 3840), (3840, 2160));
      expect(compute('9:16', 3840), (2160, 3840));
      expect(compute('1:1', 1024), (1024, 1024));
    });

    test('corrects the long edge onto the 16-px grid', () {
      expect(compute('16:9', 3838), (3840, 2160));
      // 3824 is the *nearer* multiple of 16 to 3830 (6px away, not 10).
      expect(compute('16:9', 3830), (3824, 2144));
    });

    test('walks the long edge down until the pixel cap is cleared', () {
      // 3840×3840 is 14.7 MP — nearly double the 8.29 MP ceiling. 2880² is
      // the largest square that fits under it.
      expect(compute('1:1', 3840), (2880, 2880));
    });

    test('walks the long edge up until the pixel floor is cleared', () {
      // 16:9 at 1024 is 0.6 MP, just under the 0.66 MP floor.
      expect(compute('16:9', 1024), (1088, 608));
    });

    test('every result that can be legal is legal', () {
      for (final ratio in ['1:1', '4:3', '3:2', '16:9', '21:9', '3:1', '9:16', '2:3']) {
        for (final long in [200, 1024, 1500, 2048, 3000, 3830, 3840]) {
          final (w, h) = compute(ratio, long);
          expect(isValidOpenAIImage2Size('${w}x$h'), isTrue,
              reason: '$ratio @ $long → ${w}x$h');
        }
      }
    });

    test('a ratio no size can satisfy still returns the shape asked for', () {
      // Past 3:1 nothing is legal at any size, so the dialog shows the failing
      // rule rather than the button appearing to do nothing.
      final (w, h) = compute('4:1', 2048);
      expect(w / h, closeTo(4, 0.05));
      expect(isValidOpenAIImage2Size('${w}x$h'), isFalse);
    });
  });

  group('the picker dialog', () {
    final ParamSpec spec = ModelCapabilities.forModel('gpt-image-2')
        .imageParams
        .firstWhere((p) => p.key == 'imageSize');

    Future<void> open(WidgetTester tester, String current) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAppTheme(seedColor: Colors.indigo, brightness: Brightness.light),
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showImageSizePickerDialog(
                  context: context, spec: spec, currentValue: current),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    /// Ratio, long edge, width, height — the four fields, in layout order.
    String fieldText(WidgetTester tester, int index) =>
        tester.widgetList<TextField>(find.byType(TextField)).elementAt(index).controller!.text;

    testWidgets('seeds the calculator from the size it opened on', (tester) async {
      await open(tester, '2160x3840');

      expect(fieldText(tester, 0), '9:16');
      expect(fieldText(tester, 1), '3840');
    });

    testWidgets('fills width and height from the ratio', (tester) async {
      await open(tester, '1024x1024');

      await tester.enterText(find.byType(TextField).at(0), '16:9');
      await tester.enterText(find.byType(TextField).at(1), '3000');
      await tester.tap(find.text('Calculate'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, 2), '3008');
      expect(fieldText(tester, 3), '1696');
    });

    testWidgets('writes the corrected long edge back into its own field',
        (tester) async {
      await open(tester, '1024x1024');

      await tester.enterText(find.byType(TextField).at(0), '1:1');
      await tester.enterText(find.byType(TextField).at(1), '3840');
      await tester.tap(find.text('Calculate'));
      await tester.pumpAndSettle();

      // 3840² blows the pixel cap, so the long edge really used was smaller —
      // the field has to say so rather than keep claiming 3840.
      expect(fieldText(tester, 1), isNot('3840'));
      expect(fieldText(tester, 1), fieldText(tester, 2));
    });

    testWidgets('an unreadable ratio disables the button', (tester) async {
      await open(tester, '1024x1024');

      await tester.enterText(find.byType(TextField).at(0), '16:');
      await tester.pumpAndSettle();

      final button = tester.widget<AppButton>(
        find.ancestor(of: find.text('Calculate'), matching: find.byType(AppButton)),
      );
      expect(button.onPressed, isNull);
    });
  });
}
