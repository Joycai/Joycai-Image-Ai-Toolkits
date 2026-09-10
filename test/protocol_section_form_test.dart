import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/protocol_section_form.dart';

/// Pins spec D2a rulings 1, 2 and 4: which shape the model editor's
/// 「请求方式」 section takes, and when the 「参数」 source row appears.
///
/// Decided from the dispatcher's real menus rather than hand-built ones, so a
/// change to what a channel offers shows up here as a changed section, not
/// only as a changed list.
void main() {
  ProtocolSectionForm formFor(String channelType, String modelId, String tag,
          {bool stale = false}) =>
      protocolSectionForm(
          LLMDispatcher.protocolMenu(channelType, modelId, tag: tag),
          pinIsStale: stale);

  bool paramRowFor(String channelType, String modelId, String tag) {
    final menu = LLMDispatcher.protocolMenu(channelType, modelId, tag: tag);
    return showsParamSourceRow(
        menu, protocolSectionForm(menu, pinIsStale: false));
  }

  group('ruling 1: the section exists for a choice or an unknown id', () {
    test('an unrecognized relay image model gets the dropdown and the row',
        () {
      expect(formFor(Vendors.openAIRest, 'nano-banana-pro', 'image'),
          ProtocolSectionForm.dropdown);
      expect(paramRowFor(Vendors.openAIRest, 'nano-banana-pro', 'image'),
          isTrue);
    });

    test('a recognized one gets the dropdown and no row (20a)', () {
      expect(formFor(Vendors.openAIRest, 'gpt-image-1', 'image'),
          ProtocolSectionForm.dropdown);
      expect(paramRowFor(Vendors.openAIRest, 'gpt-image-1', 'image'), isFalse);
    });

    test('one route and an unknown id is the read-only line (20d)', () {
      expect(formFor(Vendors.openAIRest, 'my-sora', 'video'),
          ProtocolSectionForm.readOnly);
      expect(paramRowFor(Vendors.openAIRest, 'my-sora', 'video'), isTrue);
      // The Claude-format neighbour of 20e: images through chat is the only
      // route, and a one-entry dropdown has nothing to choose.
      expect(formFor(Vendors.newApiAnthropic, 'my-image', 'image'),
          ProtocolSectionForm.readOnly);
    });

    test('one route and a recognized id builds nothing (18a state ①)', () {
      expect(formFor(Vendors.openAIRest, 'sora-2', 'video'),
          ProtocolSectionForm.none);
      expect(formFor(Vendors.dashscope, 'qwen-image-3.0', 'image'),
          ProtocolSectionForm.none);
      expect(formFor(Vendors.openAIRest, 'gpt-5-chat', 'chat'),
          ProtocolSectionForm.none);
    });

    test('chat keeps 18a: a menu of three is a dropdown, never read-only', () {
      expect(formFor(Vendors.dashscope, 'qwen-max', 'chat'),
          ProtocolSectionForm.dropdown);
      // "Unrecognized" is not a thing for chat — nearly every chat id is.
      expect(paramRowFor(Vendors.dashscope, 'qwen-max', 'chat'), isFalse);
    });
  });

  group('ruling 2: no interface for the kind is a notice', () {
    test('a video model on a Claude-format relay', () {
      expect(formFor(Vendors.newApiAnthropic, 'my-video', 'video'),
          ProtocolSectionForm.notice);
      expect(paramRowFor(Vendors.newApiAnthropic, 'my-video', 'video'),
          isFalse);
    });
  });

  group('explanations that need a place', () {
    test('a stale selection on a single-route channel shows the dropdown',
        () {
      expect(
          formFor(Vendors.openAIRest, 'gpt-5-chat', 'chat', stale: true),
          ProtocolSectionForm.dropdown);
    });

    test('Midjourney is a fixed route: nothing, unless a stale pin needs it',
        () {
      expect(formFor(Vendors.midjourneyProxy, 'mj_imagine', 'image'),
          ProtocolSectionForm.none);
      expect(
          formFor(Vendors.midjourneyProxy, 'mj_imagine', 'image', stale: true),
          ProtocolSectionForm.dropdown);
    });

    test('no menu at all (no channel or no id yet) builds nothing', () {
      expect(protocolSectionForm(null, pinIsStale: false),
          ProtocolSectionForm.none);
      expect(showsParamSourceRow(null, ProtocolSectionForm.none), isFalse);
    });
  });
}
