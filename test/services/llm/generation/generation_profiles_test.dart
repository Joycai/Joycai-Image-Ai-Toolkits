import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_profile_store.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_profiles.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_config_resolver.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();
  test('alias profile persistence reaches the runtime through its injected database', () async {
    final database = await openTestDatabase();
    addTearDown(() => closeTestDatabase(database));
    final channel = await database.addChannel(
      LLMChannel(
        displayName: 'relay',
        endpoint: 'https://relay.invalid/v1',
        apiKey: 'unused',
        type: Vendors.openAIRest,
      ),
    );
    final model = await database.addModel(
      LLMModel(
        modelId: 'studio-alias',
        modelName: 'Studio',
        tag: 'image',
        channelId: channel,
        wireProtocol: WireProtocol.openaiImages.id,
      ),
    );
    await GenerationProfileStore.write(database, model, 'openaiImage2');
    final config = await LLMConfigResolver(database: database).resolveConfig(model);
    expect(config.generationProfile, 'openaiImage2');
    expect(config.channelId, channel);
    expect(
      LLMDispatcher().resolveTarget(config).model.capabilities,
      same(ModelCapabilities.profiles['openaiImage2']),
    );
    await GenerationProfileStore.write(database, model, null);
    expect(await GenerationProfileStore.read(database, model), isNull);
  });
  test('wire profile declarations have unique registered identities and valid defaults', () {
    for (final entry in GenerationProfiles.byWire.entries) {
      expect(entry.value.toSet(), hasLength(entry.value.length));
      for (final profile in entry.value) {
        final caps = GenerationProfiles.resolve(profile, entry.key)!;
        expect(caps, same(ModelCapabilities.profiles[profile]));
        final params = [...caps.imageParams, ...caps.videoParams];
        expect(params.map((p) => p.key).toSet(), hasLength(params.length));
        for (final param in params) {
          expect(param.isValid(param.defaultValue), isTrue, reason: '$profile.${param.key}');
        }
      }
    }
  });

  test('an alias profile updates schema and encoder target without changing routing family', () {
    final base = LLMModelConfig(
      modelId: 'studio-alias',
      channelType: Vendors.openAIRest,
      endpoint: 'http://127.0.0.1:1',
      apiKey: 'unused',
      tag: 'image',
      wireProtocol: WireProtocol.openaiImages.id,
    );
    final selected = LLMModelConfig(
      modelId: base.modelId,
      channelType: base.channelType,
      endpoint: base.endpoint,
      apiKey: base.apiKey,
      tag: base.tag,
      wireProtocol: base.wireProtocol,
      generationProfile: 'openaiImage2',
    );
    final dispatcher = LLMDispatcher();
    expect(
      dispatcher.resolveTarget(base).model.family,
      dispatcher.resolveTarget(selected).model.family,
    );
    expect(
      dispatcher.resolveTarget(selected).model.capabilities,
      same(ModelCapabilities.profiles['openaiImage2']),
    );
    expect(selected.withEndpoint('https://relay.invalid').generationProfile, 'openaiImage2');
    expect(selected.withModelId('other-alias').generationProfile, 'openaiImage2');
  });

  test('incompatible profile is visible and blocks submission before transport', () async {
    final schema = LLMDispatcher.generationSchemaFor(
      channelType: Vendors.xaiApi,
      modelId: 'alias',
      tag: 'image',
      profile: 'seedream50Pro',
    );
    expect(schema.configurationDiagnostics.single.code, 'incompatibleProfile');
    final config = LLMModelConfig(
      modelId: 'alias',
      channelType: Vendors.xaiApi,
      endpoint: 'http://127.0.0.1:1',
      apiKey: 'unused',
      tag: 'image',
      generationProfile: 'seedream50Pro',
    );
    await expectLater(
      LLMDispatcher().generate(config, [LLMMessage(role: LLMRole.user, content: 'cat')]),
      throwsA(
        isA<LLMApiException>().having(
          (e) => e.toString(),
          'reason',
          contains('incompatibleProfile'),
        ),
      ),
    );
  });
}
