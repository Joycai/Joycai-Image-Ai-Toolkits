import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/services/catalogue/builtin_model_specs.dart';

void main() {
  group('BuiltinModelSpecs catalog', () {
    test('all preset IDs are unique and have valid tags and pricing', () {
      final ids = <String>{};
      const validTags = {'chat', 'multimodal', 'image', 'video'};
      for (final spec in BuiltinModelSpecs.all) {
        expect(ids.add(spec.id), isTrue, reason: 'Duplicate preset id: ${spec.id}');
        expect(validTags.contains(spec.tag), isTrue, reason: 'Invalid tag for ${spec.id}');
        final group = spec.pricing.toPricingGroup(name: spec.displayName);
        if (group.billingMode == 'token') {
          expect(group.inputPrice, greaterThan(0), reason: '${spec.id} inputPrice');
          expect(group.outputPrice, greaterThan(0), reason: '${spec.id} outputPrice');
        } else if (group.isSpecBilled) {
          expect(group.outputRates, isNotEmpty, reason: '${spec.id} outputRates');
          expect(
            group.outputRates.every((r) => r.price > 0),
            isTrue,
            reason: '${spec.id} spec rate prices',
          );
        } else {
          expect(group.requestPrice, greaterThan(0), reason: '${spec.id} requestPrice');
        }
      }
    });

    test('covers all requested model series with expected parameters', () {
      final expectations = <String, ({String id, String tag, int? ctx, int? out})>{
        // Qwen
        'qwen3.7-max': (id: 'qwen3.7-max', tag: 'multimodal', ctx: 1000000, out: 131072),
        'qwen3.8-max': (id: 'qwen3.8-max', tag: 'multimodal', ctx: 1000000, out: 131072),
        'qwen4-max': (id: 'qwen4-max', tag: 'multimodal', ctx: 1000000, out: 131072),
        'qwen-image-3.0': (id: 'qwen-image-3.0', tag: 'image', ctx: 4500, out: null),
        'wan2.7-image': (id: 'wan2.7-image', tag: 'image', ctx: null, out: null),
        'wan3.0-video': (id: 'wan3.0-video', tag: 'video', ctx: null, out: null),
        // GPT
        'gpt-5.6-sol': (id: 'gpt-5.6-sol', tag: 'multimodal', ctx: 1050000, out: 128000),
        'gpt-6-sol': (id: 'gpt-6-sol', tag: 'multimodal', ctx: 1050000, out: 128000),
        'gpt-6.1-sol': (id: 'gpt-6.1-sol', tag: 'multimodal', ctx: 1050000, out: 128000),
        'gpt-6.2-astra': (id: 'gpt-6.2-astra', tag: 'multimodal', ctx: 1050000, out: 128000),
        'gpt-image-2': (id: 'gpt-image-2', tag: 'image', ctx: null, out: null),
        'gpt-image-2.5-flare': (id: 'gpt-image-2.5-flare', tag: 'image', ctx: null, out: null),
        'gpt-image-2.6-sunburst': (
          id: 'gpt-image-2.6-sunburst',
          tag: 'image',
          ctx: null,
          out: null,
        ),
        // Gemini / Nano Banana / Omni / Veo
        'gemini-3.8-flash': (id: 'gemini-3.8-flash', tag: 'multimodal', ctx: 1048576, out: 65536),
        'gemini-4-neon': (id: 'gemini-4-neon', tag: 'multimodal', ctx: 1048576, out: 65536),
        'gemini-3-pro-image': (id: 'gemini-3-pro-image', tag: 'image', ctx: 131072, out: 32768),
        'gemini-3.1-flash-image': (
          id: 'gemini-3.1-flash-image',
          tag: 'image',
          ctx: 131072,
          out: 32768,
        ),
        'gemini-nano-banana-2.1': (
          id: 'gemini-nano-banana-2.1',
          tag: 'image',
          ctx: 131072,
          out: 32768,
        ),
        'gemini-omni-1.2-flash': (id: 'gemini-omni-1.2-flash', tag: 'video', ctx: null, out: null),
        'veo-3.1-generate-001': (id: 'veo-3.1', tag: 'video', ctx: null, out: null),
        // Claude
        'claude-opus-4-6': (id: 'claude-opus-4-6', tag: 'multimodal', ctx: 1000000, out: 128000),
        'claude-opus-4-7': (id: 'claude-opus-4-7', tag: 'multimodal', ctx: 1000000, out: 128000),
        'claude-opus-4-8': (id: 'claude-opus-4-8', tag: 'multimodal', ctx: 1000000, out: 128000),
        'claude-opus-5': (id: 'claude-opus-5', tag: 'multimodal', ctx: 1000000, out: 128000),
        'claude-opus-5-5': (id: 'claude-opus-5-5', tag: 'multimodal', ctx: 1000000, out: 128000),
        // DeepSeek / Grok / Seedream
        'deepseek-flash': (id: 'deepseek-v4.1-flash', tag: 'multimodal', ctx: 1048576, out: 384000),
        'grok-4.7': (id: 'grok-4.7', tag: 'multimodal', ctx: 500000, out: 131072),
        'doubao-seedream-5-0-pro-260628': (
          id: 'doubao-seedream-5-0-pro',
          tag: 'image',
          ctx: null,
          out: null,
        ),
        'doubao-seedream-5-0-260128': (
          id: 'doubao-seedream-5-0-lite',
          tag: 'image',
          ctx: null,
          out: null,
        ),
      };

      for (final entry in expectations.entries) {
        final matched = BuiltinModelSpecs.match(entry.key);
        expect(matched, isNotNull, reason: 'Expected match for ${entry.key}');
        expect(matched!.spec.id, entry.value.id, reason: 'For ${entry.key}');
        expect(matched.spec.tag, entry.value.tag, reason: 'Tag for ${entry.key}');
        expect(matched.spec.contextWindow, entry.value.ctx, reason: 'Context for ${entry.key}');
        expect(matched.spec.maxOutputTokens, entry.value.out, reason: 'Max out for ${entry.key}');
      }
    });
  });

  group('BuiltinModelSpecs fuzzy matching', () {
    test('handles namespaces, dates, separator variants, and swapped tokens', () {
      final cases = <String, String>{
        'openai/gpt-6.2-astra:thinking': 'gpt-6.2-astra',
        'anthropic/claude-opus-5.5-20260901': 'claude-opus-5-5',
        'claude-4.6-opus': 'claude-opus-4-6',
        'models/gemini-3.8-flash-preview': 'gemini-3.8-flash',
        'NanoBanana Pro': 'gemini-3-pro-image',
        'nano-banana-2': 'gemini-3.1-flash-image',
        'nano-banana-2.1': 'gemini-nano-banana-2.1',
        'omni1.2': 'gemini-omni-1.2-flash',
        'qwan-image-3.0': 'qwen-image-3.0',
        'wan-image-2.7': 'wan2.7-image',
        'wan-video-3.0': 'wan3.0-video',
        'Pro/deepseek-ai/DeepSeek-V4.1-Flash': 'deepseek-v4.1-flash',
        'deepseek-4.1': 'deepseek-v4.1-flash',
        'Seedream5.0pro': 'doubao-seedream-5-0-pro',
        'seedream-5.0': 'doubao-seedream-5-0-lite',
        'gpt-image-2-2026-04-21': 'gpt-image-2',
        'gpt-image-2.5-sunburst-2026-09-08': 'gpt-image-2.5-sunburst',
      };

      for (final entry in cases.entries) {
        final matched = BuiltinModelSpecs.match(entry.key);
        expect(matched?.spec.id, entry.value, reason: 'Fuzzy match failed for "${entry.key}"');
      }
    });

    test('does not cross-match conflicting model versions', () {
      expect(BuiltinModelSpecs.match('gpt-9.9-unknown'), isNull);
      expect(BuiltinModelSpecs.match('claude-opus-3-5'), isNull);
      expect(BuiltinModelSpecs.match('my-custom-internal-model'), isNull);
      expect(BuiltinModelSpecs.match(''), isNull);
    });

    test('Seedream 5.0 Pro official pricing includes first-free input image fee', () {
      final spec = BuiltinModelSpecs.byId('doubao-seedream-5-0-pro')!;
      expect(spec.pricing.billingMode, 'spec');
      expect(spec.pricing.outputUnit, OutputUnit.image);
      expect(spec.pricing.inputUnitPrice, 0.003);
      expect(spec.pricing.inputFreeUnits, 1);
    });

    test('search returns relevant presets for manual selection', () {
      final results = BuiltinModelSpecs.search('seedream');
      expect(
        results.map((s) => s.id),
        containsAll(['doubao-seedream-5-0-pro', 'doubao-seedream-5-0-lite']),
      );
      expect(BuiltinModelSpecs.search('').length, BuiltinModelSpecs.all.length);
    });
  });
}
