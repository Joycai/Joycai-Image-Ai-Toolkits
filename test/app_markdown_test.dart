import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_markdown.dart';

/// `A1e`: what rendered markdown has to get right wherever it appears. The
/// look is the gallery's job; these pin the rules a stylesheet cannot express
/// and a refactor could quietly lose.
void main() {
  const h2Bar = ValueKey('app-markdown-h2-bar');

  Future<void> pump(
    WidgetTester tester,
    String data, {
    AppMarkdownDensity density = AppMarkdownDensity.prose,
    double width = 600,
    TextStyle? style,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: AppMarkdown(data: data, density: density, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Every span drawn, flattened, with the style it ends up in.
  List<(String, TextStyle)> spans(WidgetTester tester) {
    final out = <(String, TextStyle)>[];
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      void walk(InlineSpan span, TextStyle inherited) {
        if (span is! TextSpan) return;
        final style = inherited.merge(span.style);
        if (span.text != null) out.add((span.text!, style));
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child, style);
        }
      }

      walk(rich.text, const TextStyle());
    }
    return out;
  }

  double sizeOf(WidgetTester tester, String text) =>
      spans(tester).firstWhere((s) => s.$1.contains(text)).$2.fontSize!;

  testWidgets('headings step down to the body, from whatever size the body is', (tester) async {
    for (final double body in [12, 14]) {
      await pump(tester, '# one\n\n## two\n\n### three\n\n#### four\n\nbody', style: TextStyle(fontSize: body));
      expect(sizeOf(tester, 'one'), greaterThan(sizeOf(tester, 'two')));
      expect(sizeOf(tester, 'two'), greaterThan(sizeOf(tester, 'three')));
      expect(sizeOf(tester, 'three'), greaterThan(sizeOf(tester, 'body')));
      expect(sizeOf(tester, 'body'), body);
      // The minor headings are a caption, not a fourth size of title.
      expect(sizeOf(tester, 'four'), lessThan(body));
    }
  });

  testWidgets('a heading sits closer to its own text than to the text before it', (tester) async {
    await pump(tester, 'before\n\n## heading\n\nafter');
    final before = tester.getRect(find.text('before', findRichText: true));
    final heading = tester.getRect(find.text('heading', findRichText: true));
    final after = tester.getRect(find.text('after', findRichText: true));

    final above = heading.top - before.bottom;
    final below = after.top - heading.bottom;
    expect(above, AppMarkdownMetrics.prose.headingAbove[1]);
    expect(below, AppMarkdownMetrics.prose.headingBelow[1]);
    expect(above, greaterThan(below * 2));
  });

  testWidgets('the first heading takes no space above it', (tester) async {
    await pump(tester, '# title\n\ntext');
    final md = tester.getRect(find.byType(AppMarkdown));
    expect(tester.getRect(find.text('title', findRichText: true)).top, md.top);
  });

  testWidgets('a list is one group: its items sit closer than paragraphs do', (tester) async {
    await pump(tester, 'para one\n\npara two\n\n- item one\n- item two');
    double gap(String a, String b) =>
        tester.getRect(find.text(b, findRichText: true)).top - tester.getRect(find.text(a, findRichText: true)).bottom;

    expect(gap('item one', 'item two'), AppMarkdownMetrics.prose.itemGap);
    expect(gap('para one', 'para two'), AppMarkdownMetrics.prose.blockGap);
    expect(gap('item one', 'item two'), lessThan(gap('para one', 'para two')));
  });

  testWidgets('nested bullets change with depth and stop changing at the third', (tester) async {
    await pump(tester, '- a\n  - b\n    - c\n      - d');
    expect(find.text('•'), findsOneWidget);
    expect(find.text('◦'), findsOneWidget);
    expect(find.text('▪'), findsNWidgets(2));
    // Each level is indented by one slot.
    final a = tester.getRect(find.text('a', findRichText: true)).left;
    final b = tester.getRect(find.text('b', findRichText: true)).left;
    expect(b - a, AppMarkdownMetrics.listIndent);
  });

  testWidgets('an ordered list keeps one text column from 9 to 10, and honours its start', (tester) async {
    await pump(tester, [for (int i = 0; i < 4; i++) '${i + 8}. item$i'].join('\n'));
    expect(find.text('8.'), findsOneWidget);
    expect(find.text('11.'), findsOneWidget);
    final lefts = {for (int i = 0; i < 4; i++) tester.getRect(find.text('item$i', findRichText: true)).left};
    expect(lefts, hasLength(1));
  });

  testWidgets('a task item draws a read-only box, and a done one steps back', (tester) async {
    await pump(tester, '- [x] done\n- [ ] open');
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('•'), findsNothing);

    final scheme = Theme.of(tester.element(find.byType(AppMarkdown))).colorScheme;
    final all = spans(tester);
    expect(all.firstWhere((s) => s.$1 == 'done').$2.color, scheme.onSurfaceVariant);
    expect(all.firstWhere((s) => s.$1 == 'open').$2.color, scheme.onSurface);
  });

  testWidgets('a single newline is kept: prompts are written a clause per line', (tester) async {
    await pump(tester, 'first clause\nsecond clause');
    final text = spans(tester).map((s) => s.$1).join();
    expect(text, contains('first clause\nsecond clause'));
  });

  testWidgets('prose marks H1 and H2; compact marks neither', (tester) async {
    await pump(tester, '# one\n\n## two');
    expect(find.byKey(h2Bar), findsOneWidget);
    final scheme = Theme.of(tester.element(find.byType(AppMarkdown))).colorScheme;
    expect((tester.widget<Container>(find.byKey(h2Bar)).decoration! as BoxDecoration).color, scheme.primary);

    await pump(tester, '# one\n\n## two', density: AppMarkdownDensity.compact);
    expect(find.byKey(h2Bar), findsNothing);
  });

  testWidgets('an image is a placeholder: nothing is fetched', (tester) async {
    await pump(tester, '![street reference](https://example.com/a.png)');
    expect(find.byType(Image), findsNothing);
    expect(find.text('street reference'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline marks: strong, emphasis, strike, code', (tester) async {
    await pump(tester, 'a **strong** b *soft* c ~~gone~~ d `code`');
    final all = spans(tester);
    TextStyle of(String t) => all.firstWhere((s) => s.$1 == t).$2;
    expect(of('strong').fontWeight, FontWeight.w700);
    expect(of('soft').fontStyle, FontStyle.italic);
    expect(of('gone').decoration, TextDecoration.lineThrough);
    expect(of('code').backgroundColor, isNotNull);
    expect(of('code').fontSize, lessThan(of('strong').fontSize!));
  });

  testWidgets('a link is coloured and inert', (tester) async {
    await pump(tester, 'see [the **reference**](https://example.com) here');
    final all = spans(tester);
    final link = all.firstWhere((s) => s.$1.contains('reference'));
    final plain = all.firstWhere((s) => s.$1.contains('see'));
    expect(link.$2.color, isNot(plain.$2.color));
    expect(link.$2.decoration, TextDecoration.underline);

    GestureRecognizer? recognizerOf(InlineSpan span) {
      GestureRecognizer? found;
      span.visitChildren((s) {
        if (s is TextSpan && s.recognizer != null) found = s.recognizer;
        return found == null;
      });
      return found;
    }

    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      expect(recognizerOf(rich.text), isNull);
    }
  });

  testWidgets('a code block keeps its lines, names its language and copies whole', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    const code = '{\n  "lens": "35mm f/1.8, a line long enough that it would wrap if it were allowed to wrap at all"\n}';
    await pump(tester, '```json\n$code\n```', width: 300);
    expect(tester.takeException(), isNull);
    expect(find.text('json'), findsOneWidget);
    expect(tester.widget<Text>(find.text(code)).softWrap, isFalse);

    await tester.tap(find.byIcon(Icons.content_copy));
    await tester.pump();
    expect(copied, code);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byIcon(Icons.content_copy), findsOneWidget);
  });

  testWidgets('compact offers no copy button', (tester) async {
    await pump(tester, '```\ncode\n```', density: AppMarkdownDensity.compact);
    expect(find.byIcon(Icons.content_copy), findsNothing);
  });

  testWidgets('a table fills the measure, and scrolls by itself when it cannot fit', (tester) async {
    const table = '| param | value |\n|---|:-:|\n| lens | **35mm** |\n| stop | f/1.8 |';
    await pump(tester, table, width: 500);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Table)).width, closeTo(498, 0.01)); // the measure, less the frame
    expect(sizeOf(tester, 'param'), lessThan(sizeOf(tester, 'lens')));

    await pump(tester, '| a | b |\n|---|---|\n| ${'wide ' * 40} | x |', width: 200);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Table)).width, greaterThan(200));
    expect(tester.getSize(find.byType(AppMarkdown)).width, 200);
  });

  testWidgets('a quote is neutral and spaces its own paragraphs', (tester) async {
    await pump(tester, '> first\n>\n> second');
    final scheme = Theme.of(tester.element(find.byType(AppMarkdown))).colorScheme;
    expect(spans(tester).firstWhere((s) => s.$1 == 'first').$2.color, scheme.onSurfaceVariant);
    final gap = tester.getRect(find.text('second', findRichText: true)).top -
        tester.getRect(find.text('first', findRichText: true)).bottom;
    expect(gap, AppMarkdownMetrics.prose.blockGap);
  });

  testWidgets('new data re-renders; empty data renders nothing and does not throw', (tester) async {
    await pump(tester, 'one');
    expect(find.text('one', findRichText: true), findsOneWidget);
    await pump(tester, 'two');
    expect(find.text('one', findRichText: true), findsNothing);
    expect(find.text('two', findRichText: true), findsOneWidget);
    await pump(tester, '');
    expect(tester.takeException(), isNull);
  });
}
