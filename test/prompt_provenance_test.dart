import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_provenance.dart';

/// The three hand-offs of generation→prompt-version provenance, pinned as
/// pure functions: version lookup at apply time, tagging at submit time, and
/// the path→version projection the gallery badge reads.
void main() {
  OptimizerChatEntry promptEntry(int version, String text) =>
      OptimizerChatEntry(kind: OptimizerEntryKind.prompt, text: text, version: version);

  group('versionForPromptText', () {
    test('finds the version whose card carries this exact text', () {
      final transcript = [
        OptimizerChatEntry(kind: OptimizerEntryKind.user, text: 'go'),
        promptEntry(1, 'first prompt'),
        promptEntry(2, 'second prompt'),
      ];
      expect(PromptProvenance.versionForPromptText(transcript, 'first prompt'), 1);
      expect(PromptProvenance.versionForPromptText(transcript, 'second prompt'), 2);
    });

    test('matches trimmed, and an edited text matches nothing', () {
      final transcript = [promptEntry(1, 'a prompt\n')];
      expect(PromptProvenance.versionForPromptText(transcript, '  a prompt  '), 1);
      expect(PromptProvenance.versionForPromptText(transcript, 'a prompt edited'), isNull);
      expect(PromptProvenance.versionForPromptText(transcript, ''), isNull);
    });

    test('identical text resubmitted credits the newest version bearing it', () {
      final transcript = [promptEntry(1, 'same'), promptEntry(3, 'same')];
      expect(PromptProvenance.versionForPromptText(transcript, 'same'), 3);
    });
  });

  group('AppliedAssistantPrompt.taskParamsFor', () {
    const applied = AppliedAssistantPrompt(sessionId: 's1', version: 3, text: 'the text');

    test('an unchanged prompt is tagged with session and version', () {
      expect(applied.taskParamsFor(' the text '), {
        PromptProvenance.sessionParamKey: 's1',
        PromptProvenance.versionParamKey: 3,
      });
    });

    test('an edited or empty prompt gets no tag', () {
      expect(applied.taskParamsFor('the text, but edited'), isNull);
      expect(applied.taskParamsFor(''), isNull);
    });
  });

  group('resultVersionsFromTasks', () {
    TaskItem task(String session, Object version, List<String> results) => TaskItem(
          id: 'id_${results.join()}',
          imagePaths: const [],
          modelId: 'm',
          parameters: {
            PromptProvenance.sessionParamKey: session,
            PromptProvenance.versionParamKey: version,
          },
          resultPaths: results,
        );

    test('projects only the asked-for session, later tasks win collisions', () {
      final map = PromptProvenance.resultVersionsFromTasks([
        task('s1', 1, ['a.png', 'b.png']),
        task('other', 9, ['c.png']),
        task('s1', 2, ['b.png']),
      ], 's1');
      expect(map, {'a.png': 1, 'b.png': 2});
    });

    test('string versions (JSON round trips, old rows) still decode', () {
      final map = PromptProvenance.resultVersionsFromTasks([task('s1', '4', ['a.png'])], 's1');
      expect(map, {'a.png': 4});
    });

    test('a task without a decodable version contributes nothing', () {
      final broken = TaskItem(
        id: 'x',
        imagePaths: const [],
        modelId: 'm',
        parameters: {PromptProvenance.sessionParamKey: 's1'},
        resultPaths: ['a.png'],
      );
      expect(PromptProvenance.resultVersionsFromTasks([broken], 's1'), isEmpty);
      expect(PromptProvenance.decodeVersionParam(broken.parameters), isNull);
    });

    test('round-trips through TaskItem persistence encoding', () {
      final original = task('s1', 2, ['a.png']);
      final revived = TaskItem.fromMap(original.toMap());
      expect(PromptProvenance.resultVersionsFromTasks([revived], 's1'), {'a.png': 2});
    });
  });
}
