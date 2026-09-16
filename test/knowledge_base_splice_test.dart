import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/knowledge_base_service.dart';

/// `write_knowledge_file`'s section modes: one heading's span replaced or
/// extended, the rest of the file byte-identical. What is staged is the
/// spliced whole file, so every rule here is about not touching the wrong
/// lines — the failure mode is a rule silently lost or duplicated.
void main() {
  const file = '# Rules\n'
      '\n'
      'intro\n'
      '\n'
      '## Lighting\n'
      '\n'
      '- soft light\n'
      '\n'
      '### Golden hour\n'
      '\n'
      '- warm\n'
      '\n'
      '## Composition\n'
      '\n'
      '- rule of thirds\n';

  String splice(String heading, String body, {bool append = false}) =>
      KnowledgeBaseService.spliceSection(file, heading, body, append: append);

  group('replace_section', () {
    test('replaces the heading and everything under it up to the next heading of its level', () {
      final out = splice('## Lighting', '## Lighting\n\n- hard light\n');
      expect(out, '# Rules\n\nintro\n\n## Lighting\n\n- hard light\n\n## Composition\n\n- rule of thirds\n');
    });

    test('a nested sub-heading belongs to its parent section and goes with it', () {
      final out = splice('## Lighting', '## Lighting\n- flat');
      expect(out, isNot(contains('Golden hour')));
      expect(out, contains('## Composition'));
    });

    test('a sub-section can be replaced on its own, and stops at the next same-level heading', () {
      final out = splice('### Golden hour', '### Golden hour\n- orange');
      expect(out, contains('- soft light'));
      expect(out, contains('- orange'));
      expect(out, isNot(contains('- warm')));
      expect(out, contains('## Composition\n\n- rule of thirds\n'));
    });

    test('the last section is replaced without inventing a trailing blank line', () {
      final out = splice('## Composition', '## Composition\n- centred');
      expect(out, endsWith('## Composition\n- centred\n'));
    });

    test('a body without a heading keeps the original heading line above it', () {
      final out = splice('## Composition', '- centred');
      expect(out, endsWith('## Composition\n- centred\n'));
    });

    test('the first of two identical headings is the one replaced', () {
      const twice = '## A\none\n## A\ntwo\n';
      final out = KnowledgeBaseService.spliceSection(twice, '## A', '## A\nuno', append: false);
      expect(out, '## A\nuno\n\n## A\ntwo\n');
    });

    test('a heading-looking line inside a code fence is not a heading', () {
      const fenced = '## A\n```\n## not a heading\n```\n- a\n## B\n- b\n';
      final out = KnowledgeBaseService.spliceSection(fenced, '## A', '## A\n- changed', append: false);
      expect(out, '## A\n- changed\n\n## B\n- b\n');
      expect(() => KnowledgeBaseService.spliceSection(fenced, '## not a heading', 'x', append: false),
          throwsA(isA<KbSectionNotFound>()));
    });

    test('CRLF files keep CRLF', () {
      final crlf = file.replaceAll('\n', '\r\n');
      final out = KnowledgeBaseService.spliceSection(crlf, '## Lighting', '## Lighting\n- hard', append: false);
      expect(out, isNot(contains(RegExp(r'[^\r]\n'))));
      expect(out, contains('## Lighting\r\n- hard\r\n\r\n## Composition'));
    });

    test('a heading not in the file throws, naming the ones that are', () {
      expect(
        () => splice('## Lightning', '## Lightning\n- x'),
        throwsA(isA<KbSectionNotFound>().having(
          (e) => e.message,
          'message',
          allOf(contains('## Lighting'), contains('## Composition'), contains('### Golden hour')),
        )),
      );
    });

    test('a section argument that is not a heading line throws too', () {
      expect(() => splice('Lighting', '- x'), throwsA(isA<KbSectionNotFound>()));
    });
  });

  group('append', () {
    test('into a section: before the next heading, inside the section', () {
      final out = splice('## Lighting', '- rim light', append: true);
      expect(out, contains('- warm\n- rim light\n\n## Composition'));
    });

    test('into the last section: at the end of the file', () {
      final out = splice('## Composition', '- leading lines', append: true);
      expect(out, endsWith('- rule of thirds\n- leading lines\n'));
    });

    test('with no section: at the end of the file, after one blank line', () {
      final out = KnowledgeBaseService.spliceSection(file, null, '## Colour\n- muted', append: true);
      expect(out, endsWith('- rule of thirds\n\n## Colour\n- muted\n'));
    });

    test('into an empty file', () {
      expect(KnowledgeBaseService.spliceSection('', null, '# New', append: true), '# New\n');
    });
  });

  test('sectionHeadings lists ATX headings in order, skipping fences', () {
    expect(KnowledgeBaseService.sectionHeadings(file),
        ['# Rules', '## Lighting', '### Golden hour', '## Composition']);
    expect(KnowledgeBaseService.sectionHeadings('```\n# no\n```\n#nospace\n####### seven\n'), isEmpty);
  });
}
