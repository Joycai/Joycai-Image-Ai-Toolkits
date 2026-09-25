import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_provider_presets.dart';

/// `D1f · 4b`: a new channel gets every route its platform offers — a
/// custom one only the protocol it names.
void main() {
  ChannelProviderPreset preset(String id) => kChannelProviderPresets.firstWhere((p) => p.id == id);

  test('New API gets all four routes, Chat Completions primary', () {
    final r = plannedChannelRoutes(
      preset('newapi'),
      preset('newapi').channelType,
      'https://relay.example.com/v1',
    );
    expect(r.kinds.first, RouteKind.chat);
    expect(r.kinds.toSet(), {
      RouteKind.chat,
      RouteKind.responses,
      RouteKind.anthropic,
      RouteKind.gemini,
    });
    expect(r.addressOf(RouteKind.gemini), 'https://relay.example.com/v1beta');
  });

  test('DashScope is one channel with its native route', () {
    final p = preset('dashscope');
    final r = plannedChannelRoutes(p, p.channelType, p.defaultEndpoint!);
    expect(r.primary.kind, RouteKind.chat);
    expect(r.has(RouteKind.dashscope), isTrue);
    expect(r.addressOf(RouteKind.dashscope), 'https://dashscope.aliyuncs.com/api/v1');
  });

  test('a custom preset gets only the protocol it names', () {
    final p = preset('custom-openai');
    final r = plannedChannelRoutes(p, p.channelType, 'https://gw.example.com/v1');
    expect(r.kinds, [RouteKind.chat]);
  });

  test('which presets ask for a way in', () {
    expect(channelPresetVariantsAreRoutes(preset('newapi')), isTrue);
    expect(channelPresetVariantsAreRoutes(preset('google')), isTrue);
    expect(channelPresetVariantsAreRoutes(preset('minimax')), isTrue);
    // Two addresses, two keys, one protocol: still a choice.
    expect(channelPresetVariantsAreRoutes(preset('volcengine-ark')), isFalse);
  });
}
