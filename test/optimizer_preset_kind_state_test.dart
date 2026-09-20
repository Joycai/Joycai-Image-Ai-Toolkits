// `A3e`: what a turn is queued with follows the preset that was loaded — its
// text and what it hands back together, through every way the two can part.
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/prompt.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';

SystemPrompt preset(int id, PresetOutputKind kind, {String content = 'TEXT'}) => SystemPrompt(
      id: id,
      title: 'p$id',
      content: content,
      type: SystemPrompt.typeRefiner,
      outputKind: kind,
    );

void main() {
  late WorkbenchUIState wui;
  setUp(() => wui = WorkbenchUIState());

  Map<String, dynamic> queued() => wui.optimizerTurnParameters(wui.optimizerSession);

  test('a loaded preset is queued with its text and its kind', () {
    wui.loadOptimizerPreset(preset(1, PresetOutputKind.analysis));
    expect(queued()['systemPrompt'], 'TEXT');
    expect(queued()['outputKind'], 'analysis');
  });

  test('the built-in hands back a prompt, whatever was loaded before', () {
    wui.loadOptimizerPreset(preset(1, PresetOutputKind.analysis));
    wui.loadOptimizerPreset(null);
    expect(wui.optSysPromptTemplateId, isNull);
    expect(queued()['systemPrompt'], '');
    expect(queued()['outputKind'], 'prompt');
  });

  test('an unsaved edit keeps the kind of the preset it was made on', () {
    wui.loadOptimizerPreset(preset(1, PresetOutputKind.analysis));
    wui.setOptimizerSysPrompt('TEXT, edited');
    expect(queued()['systemPrompt'], 'TEXT, edited');
    expect(queued()['outputKind'], 'analysis');
  });

  test('text cleared down to nothing is the built-in, and hands back a prompt', () {
    wui.loadOptimizerPreset(preset(1, PresetOutputKind.analysis));
    wui.setOptimizerSysPrompt('');
    expect(wui.effectivePresetOutputKind, PresetOutputKind.prompt);
    expect(queued()['outputKind'], 'prompt');
    // Typing again is still an edit of the analysis preset.
    wui.setOptimizerSysPrompt('TEXT again');
    expect(queued()['outputKind'], 'analysis');
  });

  test('a preset deleted from the library leaves text and kind as they were', () {
    wui.loadOptimizerPreset(preset(1, PresetOutputKind.analysis));
    wui.syncOptimizerPresetKind([preset(2, PresetOutputKind.prompt)]);
    expect(queued()['outputKind'], 'analysis');
  });

  test('a kind changed in the library reaches the loaded preset, once', () {
    wui.loadOptimizerPreset(preset(1, PresetOutputKind.prompt));
    wui.setOptimizerSysPrompt('TEXT, edited');
    var notified = 0;
    wui.addListener(() => notified++);

    wui.syncOptimizerPresetKind([preset(1, PresetOutputKind.analysis, content: 'NEW')]);
    expect(queued()['outputKind'], 'analysis');
    expect(queued()['systemPrompt'], 'TEXT, edited', reason: 'the edit is the user\'s');
    expect(notified, 1);

    wui.syncOptimizerPresetKind([preset(1, PresetOutputKind.analysis)]);
    expect(notified, 1);
  });

  test('a knowledge session is queued without a preset', () {
    wui.loadOptimizerPreset(preset(1, PresetOutputKind.analysis));
    final params = wui.optimizerTurnParameters(
        PromptOptimizerSession(mode: AssistantMode.knowledgeBase));
    expect(params.containsKey('systemPrompt'), isFalse);
    expect(params.containsKey('outputKind'), isFalse);
  });
}
