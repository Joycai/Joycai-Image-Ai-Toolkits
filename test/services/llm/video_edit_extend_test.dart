import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joycai_image_ai_toolkits/models/media_pricing.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/services/billing/media_accounting.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_preferences.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_validator.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_upload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  final schema = LLMDispatcher.generationSchemaFor(
    channelType: Vendors.dashscopeNative,
    modelId: 'wan3.0-video',
    tag: 'video',
  );
  const source = GenerationMedia(GenerationMediaRole.sourceVideo, 'source.mp4');
  test('operations own defaults, source requirements, inactive direction and mode preference', () {
    for (final mode in ['generate', 'edit', 'extend']) {
      final draft = schema.readLegacy({'videoTask': mode});
      final op = schema.operation(draft, mode == 'generate' ? [] : [source]);
      expect(op.name, mode == 'generate' ? 'textVideo' : '${mode}Video');
      final effective = schema.effective(draft, op);
      expect(effective['seconds']!.value, mode == 'generate' ? 5 : -1);
      expect(effective.containsKey('extendDirection'), mode == 'extend');
      expect(GenerationPreferences.key('base', op, 'videoTask'), 'base.mode');
      expect(schema.validate(effective, mode == 'generate' ? [] : [source]), isEmpty);
      if (mode != 'generate') {
        expect(schema.validate(effective, []).map((d) => d.code), contains('sourceVideoRequired'));
        expect(
          schema.validate(effective, [source, source]).map((d) => d.code),
          contains('sourceVideoRequired'),
        );
        expect(
          schema
              .validate(effective, [
                source,
                const GenerationMedia(GenerationMediaRole.firstFrame, 'frame'),
              ])
              .map((d) => d.code),
          contains('conflictingMedia'),
        );
        expect(schema.validatePrompt('', [source], op).single.code, 'promptRequired');
        expect(schema.allowsEmptyPrompt([source], operation: op), false);
      }
    }
    final relay = LLMDispatcher.generationSchemaFor(
      channelType: Vendors.openAIRest,
      modelId: 'wan3.0-video',
      tag: 'video',
    );
    expect(relay.contract.videoEdit, isNull);
    expect(relay.params.any((p) => p.key == 'videoTask'), false);
  });
  test('intent composition preserves explicit bilingual intent and is idempotent', () {
    for (final op in [GenerationOperation.editVideo, GenerationOperation.extendVideo]) {
      for (final direction in ['forward', 'backward', 'bidirectional']) {
        for (final prompt in ['小猫跳起来', 'a cat jumps', '猫が跳ぶ']) {
          final composed = composeDashScopeIntentPrompt(
            prompt: prompt,
            operation: op,
            extendDirection: direction,
          );
          expect(composed.endsWith(prompt), true);
          expect(composed, isNot(prompt));
          expect(
            composeDashScopeIntentPrompt(
              prompt: composed,
              operation: op,
              extendDirection: direction,
            ),
            composed,
          );
          if (op == GenerationOperation.extendVideo) {
            expect(
              composed,
              contains(
                direction == 'bidirectional'
                    ? (prompt == '小猫跳起来' ? '双向' : 'both directions')
                    : prompt == '小猫跳起来'
                    ? (direction == 'forward' ? '向前' : '向后')
                    : direction,
              ),
            );
          }
        }
      }
    }
    for (final p in ['replace the hat', 'Edit the video: blue sky', '去掉帽子', 'change red to blue']) {
      expect(composeDashScopeIntentPrompt(prompt: p, operation: GenerationOperation.editVideo), p);
    }
    for (final p in ['continue the shot', '向后延长', 'prepend sunrise']) {
      expect(
        composeDashScopeIntentPrompt(
          prompt: p,
          operation: GenerationOperation.extendVideo,
          extendDirection: 'forward',
        ),
        p,
      );
    }
    expect(
      () => buildDashScopeVideoPayload(
        modelId: 'unused',
        prompt: '😀' * 20000,
        options: {'videoTask': 'edit'},
        media: [
          {'type': 'reference_video', 'url': 'source'},
        ],
      ),
      throwsA(isA<LLMApiException>()),
    );
    final payload = buildDashScopeVideoPayload(
      modelId: 'unused',
      prompt: 'sunrise',
      options: {'videoTask': 'extend', 'extendDirection': 'forward'},
      media: [
        {'type': 'reference_video', 'url': 'source'},
      ],
    );
    expect(payload['parameters'], {'audio': true, 'ratio': 'adaptive', 'duration': -1});
    expect((payload['input'] as Map)['prompt'], startsWith('Extend Video 1 forward'));
  });
  test(
    'empty editing prompt fails before reading source and unsupported regions are detectable',
    () async {
      await expectLater(
        validateGeneration(
          schema,
          [
            LLMMessage(
              role: LLMRole.user,
              content: '',
              attachments: [
                LLMAttachment.fromFile(
                  File('missing.mp4'),
                  'video/mp4',
                  referenceType: LLMReferenceType.sourceVideo,
                ),
              ],
            ),
          ],
          {'videoTask': 'edit'},
        ),
        throwsA(
          isA<LLMApiException>().having((e) => e.toString(), 'reason', contains('promptRequired')),
        ),
      );
      expect(dashscopeSupportsTemporaryUpload('https://ws.cn-beijing.maas.aliyuncs.com'), true);
      expect(dashscopeSupportsTemporaryUpload('https://dashscope-us.aliyuncs.com'), false);
    },
  );
  test('poll separates input and output billing, preserving old duration fallback', () async {
    final config = LLMModelConfig(
      modelId: 'wan3.0-video',
      channelType: Vendors.dashscopeNative,
      endpoint: 'https://dashscope.aliyuncs.com/api/v1',
      apiKey: 'fake',
    );
    for (final usage in [
      {'duration': 12.5, 'input_video_duration': 5.0, 'output_video_duration': 7.5, 'SR': 720},
      {'duration': 4},
    ]) {
      LLMClientPool.disposeAll();
      await http.runWithClient(
        () async {
          final result = await LLMDispatcher().checkOperation(
            config,
            'job',
            surfaceId: schema.protocol!.id,
          );
          expect(
            result[videoRenderedSecondsKey],
            usage['output_video_duration'] ?? usage['duration'],
          );
          expect(result['input_video_seconds'], usage['input_video_duration']);
          expect(result['output_size'], usage.containsKey('SR') ? '720p' : null);
          if (usage.containsKey('input_video_duration')) {
            final pricing = PricingGroup(
              name: 'Wan',
              billingMode: 'spec',
              outputUnit: OutputUnit.second,
              outputRates: const [SpecRate(size: '720p', price: 0.2)],
              mediaPricing: const MediaPricing(
                videoInputRates: [SpecRate(size: '720p', price: 0.1)],
              ),
            );
            final pending = MediaAccounting.price(
              pricing,
              {'input_seconds': 5},
              options: {'resolution': '720p', 'seconds': -1},
              video: true,
              pending: true,
            );
            final settled = MediaAccounting.settle(pending, {
              'output_seconds': result[videoRenderedSecondsKey],
              'input_seconds': result['input_video_seconds'],
              'output_size': result['output_size'],
            });
            expect(settled.cost, closeTo(5 * 0.1 + 7.5 * 0.2, 1e-12));
          }
        },
        () => MockClient((r) async {
          expect(r.method, 'GET');
          return http.Response(
            jsonEncode({
              'output': {'task_status': 'SUCCEEDED', 'video_url': 'https://storage.test/video.mp4'},
              'usage': usage,
            }),
            200,
          );
        }),
      );
    }
    LLMClientPool.disposeAll();
  });
}
