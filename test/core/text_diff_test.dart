// The diff behind `A2 10h`'s knowledge-edit card. Its job is to make a small
// change inside a large document visible, so what is asserted here is mostly
// about what it *leaves out*: untouched stretches, and the trailing blank line
// a well-formed file's final newline would otherwise invent.
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/text_diff.dart';

void main() {
  String render(List<DiffHunk> hunks) => hunks
      .map((h) => '@@ -${h.oldStart} +${h.newStart}\n'
          '${h.lines.map((l) => '${switch (l.kind) {
                DiffLineKind.added => '+',
                DiffLineKind.removed => '-',
                DiffLineKind.context => ' ',
              }}${l.text}').join('\n')}')
      .join('\n');

  test('identical text produces no hunks at all', () {
    expect(TextDiff.unified('a\nb\nc\n', 'a\nb\nc\n'), isEmpty);
  });

  test('a trailing newline is not a blank final line', () {
    // Without the fix in `_split`, every file that ends the way a text file is
    // supposed to end would diff against itself as one added empty line.
    expect(TextDiff.unified('a\nb', 'a\nb\n'), isEmpty);
    expect(TextDiff.counts('a\nb\n', 'a\nb\n'), (0, 0));
  });

  test('one changed line in the middle of a document carries only its context', () {
    final oldText = List.generate(20, (i) => 'line $i').join('\n');
    final newText = List.generate(20, (i) => i == 10 ? 'CHANGED' : 'line $i').join('\n');

    final hunks = TextDiff.unified(oldText, newText);
    expect(hunks, hasLength(1));
    // Two lines of context, the removal, the addition, two more of context.
    expect(hunks.single.lines, hasLength(6));
    expect(hunks.single.oldStart, 9);
    expect(render(hunks), '''
@@ -9 +9
 line 8
 line 9
-line 10
+CHANGED
 line 11
 line 12''');
  });

  test('two distant changes come out as two hunks', () {
    final oldText = List.generate(40, (i) => 'line $i').join('\n');
    final newText = List.generate(40, (i) {
      if (i == 5) return 'FIRST';
      if (i == 30) return 'SECOND';
      return 'line $i';
    }).join('\n');

    final hunks = TextDiff.unified(oldText, newText);
    expect(hunks, hasLength(2));
    expect(hunks.first.oldStart, 4);
    expect(hunks.last.oldStart, 29);
  });

  test('two adjacent changes share one hunk rather than splitting it', () {
    final oldText = List.generate(20, (i) => 'line $i').join('\n');
    final newText = List.generate(20, (i) {
      if (i == 10 || i == 12) return 'CHANGED $i';
      return 'line $i';
    }).join('\n');

    expect(TextDiff.unified(oldText, newText), hasLength(1));
  });

  test('counts report each side separately', () {
    // Three lines replaced by five: the header's `+5 −3`.
    final oldText = 'head\n${List.generate(3, (i) => 'old $i').join('\n')}\ntail';
    final newText = 'head\n${List.generate(5, (i) => 'new $i').join('\n')}\ntail';
    expect(TextDiff.counts(oldText, newText), (5, 3));
  });

  test('a pure insertion removes nothing', () {
    expect(TextDiff.counts('a\nb\n', 'a\nnew\nb\n'), (1, 0));
  });

  test('creating a file from nothing is all additions', () {
    expect(TextDiff.counts('', 'a\nb\nc\n'), (3, 0));
  });

  test('an oversized document is reported as a wholesale replacement', () {
    // Not a claim about the algorithm's limit so much as about its promise:
    // past the cap it must still return something truthful, and "everything
    // was replaced" is truthful even when it is coarse.
    final oldText = List.generate(4100, (i) => 'a $i').join('\n');
    final newText = List.generate(4100, (i) => 'b $i').join('\n');
    final hunks = TextDiff.unified(oldText, newText);
    expect(hunks, hasLength(1));
    expect(hunks.single.lines.where((l) => l.kind == DiffLineKind.context), isEmpty);
    expect(TextDiff.counts(oldText, newText), (4100, 4100));
  });
}
