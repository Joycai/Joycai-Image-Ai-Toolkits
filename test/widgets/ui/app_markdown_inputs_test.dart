import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_markdown.dart';

/// [AppMarkdown] walks the parser's tree itself, so every shape the parser can
/// hand it is a shape it has to survive: empty markers, ragged tables, blocks
/// nested in list items, raw HTML, CRLF. Each is rendered in both densities,
/// at a phone-panel width and a narrow one, under an [IntrinsicHeight] — the
/// way the workbench's config panel holds the editor's preview. Nothing may
/// throw or overflow.
///
/// Not covered, knowingly: list nesting deeper than the width has slots for
/// (each level costs 16–23px of fixed indent).
void main() {
  const inputs = <String>[
    '#', '##  ', '- ', '1. ', '- [ ]', '- [x]', '>', '> ', '```', '```\n', '```json', '---', '|a|\n|-|', '|a|b|\n|-|-|\n|c|',
    '|a|b|\n|-|-|\n|c|d|e|', '[](x)', '[![img](a.png)](http://x)', '![](a.png)', '![]()', '<div>html</div>', 'a<br>b', '<b>x</b>',
    '- a\n\n  para\n\n  ```\n  code\n  ```\n\n  > q\n\n  | t |\n  |---|\n  | c |', '1. a\n   - [x] b\n     1. c',
    '> - a\n> - b\n>\n> ## h\n> ```\n> c\n> ```',
    '# h\n---\n## h2\n---\ntext', '999999999. big', '0. zero', '-1. neg', 'https://example.com auto', '<https://example.com>',
    'a  \nb', 'a\\\nb',
    '* * *', '***bold-italic***', '`a` `b` `c`', '~~a **b** c~~', '## [link](x) in heading', '- [x] **b** `c` [l](x)',
    '\r\n# crlf\r\n\r\ntext\r\n',
    '&amp; &lt; &copy;', '[^1]: foot', 'Term\n: def', '    indented code', '\t- tab list', '- a\n- b\n\n- c', 'emoji **x**',
    '| a |\n|:-:|\n| **x** `y` ![i](z) |', '## h\n## h\n## h', '####### seven', 'Setext\n===\nSetext2\n---',
  ];
  for (final density in AppMarkdownDensity.values) {
    for (final double width in [120, 320]) {
      testWidgets('odd input renders · ${density.name} @ $width', (tester) async {
        for (final input in inputs) {
          await tester.pumpWidget(MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: width,
                  child: IntrinsicHeight(child: AppMarkdown(data: input, density: density, selectable: true)),
                ),
              ),
            ),
          ));
          final e = tester.takeException();
          expect(e, isNull, reason: 'input: ${input.replaceAll('\n', r'\n')}');
        }
      });
    }
  }
}
