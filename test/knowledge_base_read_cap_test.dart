import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/context_budget.dart';
import 'package:path/path.dart' as p;

/// How much of a knowledge file one read returns, given what the context has
/// room for.
///
/// The point of the cap is that a file small enough to fit comes back whole
/// rather than sliced at an arbitrary offset, while a big one still cannot
/// swallow the window.
void main() {
  late Directory root;
  final kb = KnowledgeBaseService();

  setUp(() {
    root = Directory.systemTemp.createTempSync('joycai_kb_cap_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void write(String name, String content) {
    File(p.join(root.path, name)).writeAsStringSync(content);
  }

  group('readFile with a cap', () {
    test('a file that fits comes back whole, in one page', () {
      final body = 'rule\n\n' * 500; // ~3000 chars
      write('a.md', body);

      final result = kb.readFile(root.path, 'a.md', maxChars: 50000);
      expect(result.totalPages, 1);
      expect(result.page, 1);
      expect(result.content, body, reason: 'no truncation when there is room');
    });

    test('a file larger than the cap is split', () {
      write('big.md', 'para\n\n' * 5000); // ~30000 chars

      final result = kb.readFile(root.path, 'big.md', maxChars: 10000);
      expect(result.totalPages, greaterThan(1));
      expect(result.content.length, lessThanOrEqualTo(KnowledgeBaseService.pageSize));
    });

    test('without a cap the old paging behaviour is unchanged', () {
      final body = 'para\n\n' * 5000;
      write('big.md', body);

      final capped = kb.readFile(root.path, 'big.md');
      expect(capped.totalPages, greaterThan(1));
    });

    test('a window too small for a full page shrinks the page instead of blowing the budget', () {
      // A 4K-token model has ~4600 chars of headroom — less than one 8000-char
      // page. Returning a full page anyway would overflow the very window the
      // cap exists to protect.
      write('big.md', 'para\n\n' * 5000);

      final result = kb.readFile(root.path, 'big.md', maxChars: 3000);
      expect(result.content.length, lessThanOrEqualTo(3000));
      expect(result.totalPages, greaterThan(1));
    });

    test('paging still covers the file with no gaps', () {
      final body = List.generate(400, (i) => '# H$i\n${'text ' * 30}').join('\n\n');
      write('big.md', body);

      final buffer = StringBuffer();
      final first = kb.readFile(root.path, 'big.md', maxChars: 1000);
      for (int page = 1; page <= first.totalPages; page++) {
        buffer.write(kb.readFile(root.path, 'big.md', page: page, maxChars: 1000).content);
      }
      expect(buffer.toString(), body,
          reason: 'concatenating every page must reproduce the file exactly');
    });

    test('an out-of-range page clamps rather than throwing', () {
      write('a.md', 'small');
      expect(kb.readFile(root.path, 'a.md', page: 99).page, 1);
      expect(kb.readFile(root.path, 'a.md', page: 0).page, 1);
    });

    test('the cap the agent would compute lets a typical rule file through whole', () {
      // An 8K-token model, empty context: ~9200 chars of window, ~2300 held
      // back for the reply. A 3000-char rule file should still arrive intact.
      final cap = ContextBudget.readCapChars(8192, 0);
      final body = 'rule text\n\n' * 250; // ~2750 chars
      write('a.md', body);

      expect(cap, greaterThan(body.length));
      expect(kb.readFile(root.path, 'a.md', maxChars: cap).totalPages, 1);
    });
  });
}
