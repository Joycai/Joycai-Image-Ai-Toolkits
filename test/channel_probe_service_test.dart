import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_probe_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins the probe's judgement rules (playbook 6.31-6.35): /models first, the
/// ENDPOINT_ABSENT set falls back to a completion probe judged by the shape
/// of the rejection, and "no /models" is a normal configuration — never an
/// error the user reads as "my key is wrong".
class _FakeDispatcher extends LLMDispatcher {
  _FakeDispatcher({this.onDiscover, this.onGenerate});

  final Future<List<DiscoveredModel>> Function()? onDiscover;
  final Future<LLMResponse> Function()? onGenerate;
  int discoverCalls = 0;
  int generateCalls = 0;
  String? generateModelId;

  @override
  Future<List<DiscoveredModel>> discoverModels(LLMModelConfig config) {
    discoverCalls++;
    return onDiscover!();
  }

  @override
  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) {
    generateCalls++;
    generateModelId = config.modelId;
    return onGenerate!();
  }
}

void main() {
  LLMModelConfig config({String type = Vendors.openAIRest}) => LLMModelConfig(
        modelId: 'any',
        channelType: type,
        endpoint: 'https://relay.example.com/v1',
        apiKey: 'k',
      );

  DiscoveredModel model(String id) =>
      DiscoveredModel(modelId: id, displayName: id, rawData: const {});

  test('/models answering is the whole story: ok + count', () async {
    final probe = ChannelProbeService(
        dispatcher: _FakeDispatcher(
            onDiscover: () async => [model('a'), model('b')]));
    final r = await probe.probe(config());
    expect(r.status, ChannelProbeStatus.ok);
    expect(r.modelCount, 2);
  });

  test('401/403 is auth, not unreachable', () async {
    final probe = ChannelProbeService(
        dispatcher: _FakeDispatcher(
            onDiscover: () async =>
                throw LLMApiException('nope', statusCode: 401)));
    expect((await probe.probe(config())).status, ChannelProbeStatus.authFailed);
  });

  test('missing /models falls back; a protocol-shaped rejection = connected',
      () async {
    // "No /models" is how many relays are configured — the completion probe
    // asks the API surface itself, with an impossible model name so nothing
    // can bill a real generation.
    final fake = _FakeDispatcher(
      onDiscover: () async => throw LLMApiException('gone', statusCode: 404),
      onGenerate: () async =>
          throw LLMApiException('unknown model', statusCode: 400),
    );
    final r = await ChannelProbeService(dispatcher: fake).probe(config());
    expect(r.status, ChannelProbeStatus.connectedNoModels);
    expect(fake.generateModelId, ChannelProbeService.probeModelId);
  });

  test('a 2xx completion for the impossible model still means connected',
      () async {
    final fake = _FakeDispatcher(
      onDiscover: () async => throw LLMApiException('gone', statusCode: 405),
      onGenerate: () async => LLMResponse(text: 'hello'),
    );
    expect((await ChannelProbeService(dispatcher: fake).probe(config())).status,
        ChannelProbeStatus.connectedNoModels);
  });

  test('an HTML answer on either step is "not an API", not a key problem',
      () async {
    final direct = ChannelProbeService(
        dispatcher: _FakeDispatcher(
            onDiscover: () async =>
                throw LLMApiException('html', isNonJsonBody: true)));
    expect((await direct.probe(config())).status, ChannelProbeStatus.notAnApi);

    final onFallback = ChannelProbeService(
        dispatcher: _FakeDispatcher(
      onDiscover: () async => throw LLMApiException('gone', statusCode: 404),
      onGenerate: () async =>
          throw LLMApiException('html', isNonJsonBody: true),
    ));
    expect((await onFallback.probe(config())).status,
        ChannelProbeStatus.notAnApi);
  });

  test('402 is an empty wallet, not a connected channel', () async {
    // Seen live: a relay answers every real request 402 with a complete JSON
    // error before resolving the model — a protocol-shaped rejection, which
    // the completion probe used to read as "connected".
    final outOfCredit = LLMApiException(
        "You're out of credits — this request needs \$0.000074", statusCode: 402);

    final viaProbe = ChannelProbeService(
        dispatcher: _FakeDispatcher(
            onDiscover: () async => throw LLMApiException('no', statusCode: 404),
            onGenerate: () async => throw outOfCredit));
    final r = await viaProbe.probe(config());
    expect(r.status, ChannelProbeStatus.unreachable);
    expect(r.detail, contains('out of credits'));

    // And on /models itself, where some hosts gate it too.
    final viaModels = ChannelProbeService(
        dispatcher: _FakeDispatcher(onDiscover: () async => throw outOfCredit));
    expect((await viaModels.probe(config())).status, ChannelProbeStatus.unreachable);
  });

  test('network-level failure reads as unreachable with the detail', () async {
    final probe = ChannelProbeService(
        dispatcher:
            _FakeDispatcher(onDiscover: () async => throw Exception('refused')));
    final r = await probe.probe(config());
    expect(r.status, ChannelProbeStatus.unreachable);
    expect(r.detail, contains('refused'));
  });

  test('midjourney channels are not probed at all', () async {
    // Its discovery returns a built-in catalog without a request — trusting
    // it would report success against any URL — and a real request would
    // start a paid generation.
    final fake = _FakeDispatcher();
    final r = await ChannelProbeService(dispatcher: fake)
        .probe(config(type: Vendors.midjourneyProxy));
    expect(r.status, ChannelProbeStatus.notSupported);
    expect(fake.discoverCalls, 0);
    expect(fake.generateCalls, 0);
  });
}
