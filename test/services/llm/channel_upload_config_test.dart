import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_upload_config.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_upload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  const endpoint = 'https://token-plan.cn-beijing.maas.aliyuncs.com/api/v1';
  const upload = ChannelUploadConfig(
    tokenPlan: true,
    endpoint: 'https://dashscope.aliyuncs.com/api/v1',
    apiKey: 'upload-key',
  );
  LLMModelConfig config(ChannelUploadConfig? value) => LLMModelConfig(
    modelId: 'wan3.0-video',
    channelType: Vendors.dashscopeNative,
    endpoint: endpoint,
    apiKey: 'plan-key',
    uploadConfig: value,
  );

  test('upload configuration survives route edits, normalization and config copies', () {
    final routes = ChannelRoutes.resolve(
      Vendors.dashscopeNative,
      endpoint,
      null,
    ).withUploadConfig(upload);
    final edited = routes.withPath(routes.primary.kind, '/api/v1').withHost(routes.host);
    final restored = ChannelRoutes.resolve(
      edited.primaryVendorId,
      edited.primaryAddress,
      edited.encode(),
    );
    expect(restored.uploadConfig!.toJson(), upload.toJson());
    final copy = config(restored.uploadConfig).withEndpoint(endpoint).withModelId('other');
    expect(copy.uploadConfig!.apiKey, 'upload-key');
    expect(copy.apiKey, 'plan-key');
    expect(dashscopeMediaUploadBase(copy), upload.endpoint);
  });

  test('missing, disabled or unsafe plan upload settings cannot fall back to the plan key', () {
    for (final value in [
      null,
      const ChannelUploadConfig(tokenPlan: false, endpoint: '', apiKey: ''),
      const ChannelUploadConfig(tokenPlan: true, endpoint: endpoint, apiKey: 'upload-key'),
      const ChannelUploadConfig(
        tokenPlan: true,
        endpoint: 'http://upload.test',
        apiKey: 'upload-key',
      ),
      const ChannelUploadConfig(tokenPlan: true, endpoint: 'https://upload.test', apiKey: ''),
      for (final host in [
        'dashscope-intl.aliyuncs.com',
        'ap-southeast-1.maas.aliyuncs.com',
        'workspace.ap-southeast-1.maas.aliyuncs.com',
      ])
        ChannelUploadConfig(
          tokenPlan: true,
          endpoint: 'https://$host/api/v1',
          apiKey: 'upload-key',
        ),
    ]) {
      expect(() => dashscopeMediaUploadBase(config(value)), throwsA(isA<LLMApiException>()));
    }
  });

  test('regular channels keep existing upload authentication and endpoints', () {
    final regular = LLMModelConfig(
      modelId: 'opaque',
      channelType: Vendors.dashscopeNative,
      endpoint: upload.endpoint,
      apiKey: 'regular-key',
    );
    expect(dashscopeMediaUploadBase(regular), upload.endpoint);
    expect(ChannelUploadConfig.fromJson({'apiKey': 3})!.apiKey, isEmpty);
  });
}
