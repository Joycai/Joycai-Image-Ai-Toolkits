import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart' show reportedCostKey;
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// What the xAI Images wire puts in the body for the workbench's quality and
/// size choices — the two dimensions grok-imagine-image-2.0 is priced by
/// (docs/api/usage.md §5). A field that is not on the wire is billed at
/// upstream's default, whatever the app thought it asked for.
void main() {
  late HttpServer server;
  late Map<String, dynamic> lastBody;

  /// What the loopback upstream puts under `usage`; null leaves it out.
  Map<String, dynamic>? usage = const {'cost_in_usd_ticks': 600000000};

  setUp(() async {
    usage = const {'cost_in_usd_ticks': 600000000};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      lastBody = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': [
          {'b64_json': base64Encode(_png)},
        ],
        'usage': ?usage,
      }));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  LLMModelConfig config(String modelId) => LLMModelConfig(
        modelId: modelId,
        channelType: Vendors.xaiApi,
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
      );

  Future<Map<String, dynamic>> send(String modelId, Map<String, dynamic> options) async {
    await LLMDispatcher().generate(
      config(modelId),
      [LLMMessage(role: LLMRole.user, content: 'a red apple')],
      options: options,
    );
    return lastBody;
  }

  /// The options the workbench sends when nothing was chosen: every
  /// declared parameter at its default (`AppState.effectiveImageParams`).
  Map<String, dynamic> defaultsOf(String modelId) => {
        for (final p in ModelCapabilities.forModel(modelId).imageParams)
          p.key: p.defaultValue,
      };

  test('2.0 defaults go out as resolution 1k and quality medium, spelled out', () async {
    // Medium is upstream's own default, but saying it lets the usage row
    // carry `1K · medium` and a rate row of that name match it.
    final body = await send('grok-imagine-image-2.0', defaultsOf('grok-imagine-image-2.0'));
    expect(body['resolution'], '1k');
    expect(body['quality'], 'medium');
    expect(body.containsKey('aspect_ratio'), isFalse);
  });

  test('low and 1.5k reach the wire', () async {
    final body = await send('grok-imagine-image-2.0', {'imageSize': '1.5k', 'quality': 'low'});
    expect(body['resolution'], '1.5k');
    expect(body['quality'], 'low');
  });

  test('a quality the model does not price is left out, not sent', () async {
    // `auto` lets the model choose (and bills unpredictably); `high` is
    // refused with a 400. Neither is offered, and neither leaks through
    // from a store written for another family.
    for (final q in ['auto', 'high', 'not_set', '']) {
      final body = await send('grok-imagine-image-2.0', {'quality': q});
      expect(body.containsKey('quality'), isFalse, reason: q);
    }
  });

  group('the reported cost', () {
    Future<Map<String, dynamic>> metadataOf() async {
      final response = await LLMDispatcher().generate(
        config('grok-imagine-image-2.0'),
        [LLMMessage(role: LLMRole.user, content: 'a red apple')],
        options: defaultsOf('grok-imagine-image-2.0'),
      );
      return response.metadata;
    }

    test('cost_in_usd_ticks is republished in dollars, the raw field kept', () async {
      final metadata = await metadataOf();
      expect(metadata[reportedCostKey], closeTo(0.06, 1e-12));
      expect(metadata['cost_in_usd_ticks'], 600000000);
    });

    test('a usage block without ticks, or none at all, reports no cost', () async {
      usage = const {'total_tokens': 12};
      expect((await metadataOf()).containsKey(reportedCostKey), isFalse);
      usage = null;
      expect((await metadataOf()).containsKey(reportedCostKey), isFalse);
    });
  });

  test('the legacy model sends no quality and is re-sized off 1.5k', () async {
    // The two families share one parameter store: a `1.5k` chosen on 2.0 is
    // not a size the first generation takes (400 upstream), so the shared
    // size guard swaps in the legacy default before the body is built.
    final body = await send('grok-imagine-image', {'imageSize': '1.5k', 'quality': 'low'});
    expect(body.containsKey('quality'), isFalse);
    expect(body['resolution'], '1k');
  });
}

final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
