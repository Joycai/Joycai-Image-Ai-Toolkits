import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// A section write stages the whole spliced file, as it always did, and now
/// also tells the card which section it targeted — a hunk deep in a long file
/// otherwise says nothing about where it is.
void main() {
  usePrivateDataDir('joycai_kb_section_scope_test');
  late Directory root;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('kb_scope_');
    File(p.join(root.path, 'README.md')).writeAsStringSync('# KB\n');
    File(
      p.join(root.path, 'rules.md'),
    ).writeAsStringSync('# Rules\n\n## Lighting\n\n- soft\n\n## Composition\n\n- thirds\n');
  });
  tearDown(() {
    PromptOptimizerAgent.debugRequestOverride = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<OptimizerChatEntry> stage(Map<String, dynamic> writeArgs) async {
    final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
    session.addUserTurn('tidy the rules');
    var requests = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      return switch (requests) {
        1 => LLMResponse(
          text: '',
          toolCalls: [
            LLMToolCall(
              id: 'r',
              name: 'read_knowledge_file',
              arguments: const {'path': 'rules.md'},
            ),
          ],
        ),
        2 => LLMResponse(
          text: '',
          toolCalls: [LLMToolCall(id: 'w', name: 'write_knowledge_file', arguments: writeArgs)],
        ),
        _ => LLMResponse(text: 'done'),
      };
    };
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
      knowledgeRoot: root.path,
      knowledgeEntryContent: KnowledgeBaseService().readFullFile(root.path, 'README.md')!,
    );
    return session.transcript.singleWhere((e) => e.kind == OptimizerEntryKind.kbEdit);
  }

  test('replace_section records its heading', () async {
    final entry = await stage(const {
      'path': 'rules.md',
      'mode': 'replace_section',
      'section': '## Composition',
      'content': '## Composition\n\n- golden ratio',
    });
    expect(entry.editScope, KbEditScope.replaceSection);
    expect(entry.editSection, '## Composition');
    expect(entry.newContent, contains('- golden ratio'));
    expect(entry.newContent, contains('- soft'), reason: 'still the whole file');
  });

  test('append with no section records the end of the file', () async {
    final entry = await stage(const {
      'path': 'rules.md',
      'mode': 'append',
      'content': '## Colour\n\n- muted',
    });
    expect(entry.editScope, KbEditScope.append);
    expect(entry.editSection, isNull);
  });

  test('a whole-file write records no section', () async {
    final entry = await stage(const {'path': 'rules.md', 'content': '# Rules\n'});
    expect(entry.editScope, KbEditScope.file);
    expect(entry.editSection, isNull);
  });
}
