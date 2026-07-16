import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';

/// Page boundaries for knowledge files.
///
/// Pages used to be cut at raw character offsets, which lands mid-sentence,
/// mid-table or mid-code-fence and hands the model half a rule. These pin that
/// boundaries snap to a real break where one is near, and — because page
/// numbers are used as cache keys — that the mapping stays deterministic.
void main() {
  const pageSize = KnowledgeBaseService.pageSize;

  group('pageBoundaries', () {
    test('an empty file is one page starting at zero', () {
      expect(KnowledgeBaseService.pageBoundaries('', pageSize), [0]);
    });

    test('content that fits is a single page', () {
      expect(KnowledgeBaseService.pageBoundaries('short', pageSize), [0]);
      expect(KnowledgeBaseService.pageBoundaries('x' * pageSize, pageSize), [0]);
    });

    test('is deterministic — the same input always maps to the same pages', () {
      final content = ('para\n\n' * 4000);
      final first = KnowledgeBaseService.pageBoundaries(content, pageSize);
      final second = KnowledgeBaseService.pageBoundaries(content, pageSize);
      expect(first, second);
      expect(first.length, greaterThan(1));
    });

    test('boundaries are strictly increasing and cover the whole file', () {
      final content = ('para\n\n' * 4000);
      final starts = KnowledgeBaseService.pageBoundaries(content, pageSize);
      for (int i = 1; i < starts.length; i++) {
        expect(starts[i], greaterThan(starts[i - 1]));
      }
      expect(starts.first, 0);
      expect(starts.last, lessThan(content.length));
    });

    test('a page break lands on a heading rather than mid-sentence', () {
      // A heading sits just inside the snap window before the raw cut.
      final head = 'a' * (pageSize - 200);
      final content = '$head\n# Section Two\n${'b' * pageSize}';
      final starts = KnowledgeBaseService.pageBoundaries(content, pageSize);

      expect(starts.length, greaterThan(1));
      expect(content.substring(starts[1]), startsWith('# Section Two'));
    });

    test('falls back to a blank line when there is no heading', () {
      final head = 'a' * (pageSize - 200);
      final content = '$head\n\n${'b' * pageSize}';
      final starts = KnowledgeBaseService.pageBoundaries(content, pageSize);

      expect(starts.length, greaterThan(1));
      expect(content.substring(starts[1]), startsWith('b'));
    });

    test('cuts at the limit when no break is close enough', () {
      // One unbroken run — a minified blob or a giant table. Snapping must not
      // walk backwards indefinitely looking for a break that is not there.
      final content = 'x' * (pageSize * 2);
      final starts = KnowledgeBaseService.pageBoundaries(content, pageSize);
      expect(starts, [0, pageSize]);
    });

    test('a break outside the tolerance is ignored rather than gutting a page', () {
      // The only break sits at the very start, far outside the window before
      // the cut. Honouring it would make page one almost empty.
      final content = 'a\n\n${'b' * (pageSize * 2)}';
      final starts = KnowledgeBaseService.pageBoundaries(content, pageSize);
      expect(starts[1], greaterThan((pageSize * 0.75).round()));
    });

    test('every page carries real content — no empty pages', () {
      final content = List.generate(500, (i) => '# H$i\n${'text ' * 40}').join('\n\n');
      final starts = KnowledgeBaseService.pageBoundaries(content, pageSize);
      for (int i = 0; i < starts.length; i++) {
        final end = i + 1 < starts.length ? starts[i + 1] : content.length;
        expect(end - starts[i], greaterThan(0), reason: 'page ${i + 1} is empty');
      }
    });
  });
}
