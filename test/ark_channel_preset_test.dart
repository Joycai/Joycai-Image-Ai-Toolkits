import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_provider_presets.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_provider_row.dart';

/// The Volcengine Ark preset (design D1e · 3a): one channel type, two
/// addresses whose keys do not cross over.
void main() {
  const payg = 'https://ark.cn-beijing.volces.com/api/v3';
  const plan = 'https://ark.cn-beijing.volces.com/api/plan/v3';

  test('a first-party row with two variants of the same type', () {
    final preset = presetForChannelType(Vendors.volcengineArk, endpoint: plan);
    expect(preset?.id, 'volcengine-ark');
    expect(preset!.group, ChannelProviderGroup.vendor);
    expect([for (final v in preset.variants) v.id], ['payg', 'plan']);
    expect(
        preset.variants.every((v) => v.channelType == Vendors.volcengineArk),
        isTrue);
    expect([for (final v in preset.variants) v.defaultEndpoint], [payg, plan]);
  });

  test('a stored channel reads back onto the variant its address is', () {
    final preset = presetForChannelType(Vendors.volcengineArk)!;
    expect(variantForChannelType(preset, Vendors.volcengineArk, endpoint: plan)
        ?.id, 'plan');
    expect(
        variantForChannelType(preset, Vendors.volcengineArk,
                endpoint: '$plan/')
            ?.id,
        'plan',
        reason: 'a trailing slash is the same address');
    expect(variantForChannelType(preset, Vendors.volcengineArk, endpoint: payg)
        ?.id, 'payg');
    // An address of the user's own falls back to the first variant.
    expect(
        variantForChannelType(preset, Vendors.volcengineArk,
                endpoint: 'https://gateway.example/ark')
            ?.id,
        'payg');
  });

  test('appended last, so no existing row changed colour', () {
    expect(kChannelProviderPresets.last.id, 'volcengine-ark');
    // The row before it kept its index, and with it its identity colour.
    final before = kChannelProviderPresets[kChannelProviderPresets.length - 2];
    expect(before.id, 'minimax-h3-base');
    expect(channelPresetIdentityColor(before),
        isNot(channelPresetIdentityColor(kChannelProviderPresets.last)));
  });

  test('searchable by the names people know it by', () {
    final preset = kChannelProviderPresets.last;
    expect(preset.searchAliases,
        containsAll(['火山', '方舟', 'volcengine', 'doubao', 'seedream']));
  });
}
