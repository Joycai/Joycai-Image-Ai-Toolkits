import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/llm/vendors/vendors.dart';

/// The headings the provider picker groups presets under, in display order. A
/// preset's [ChannelProviderPreset.group] is about the *wire protocol* the
/// preset produces, not about the company — which is why MiniMax appears under
/// both OpenAI and Anthropic.
enum ChannelProviderGroup { openai, google, anthropic, other }

/// A provider preset offered by the add-channel dialog. Merges what used to be
/// separate protocol and provider steps: picking a preset implies both the
/// channel dialect and (when known) the endpoint.
class ChannelProviderPreset {
  final String id;
  final String channelType;

  /// Which heading this preset sits under. The picker renders every preset by
  /// filtering on this, so a preset added below cannot go missing from the UI
  /// — which is exactly what happened while the grid was driven by
  /// hand-written id lists (DeepSeek, MiniMax and DashScope were all defined
  /// here yet unreachable).
  final ChannelProviderGroup group;

  /// Endpoint prefilled for providers with a well-known host; null when there
  /// is nothing sensible to suggest (relays, proxies, custom).
  ///
  /// A suggestion, never a lock — the field stays editable either way. Every
  /// hosted provider here has addresses the preset cannot know about: an
  /// international host (`dashscope-intl.aliyuncs.com`), a corporate gateway,
  /// a relay fronting the same API. Hiding the field, as this once did, left
  /// no way to reach them but the `custom` preset, which resolves to a
  /// different channel type and so silently drops the vendor's own behavior.
  final String? defaultEndpoint;

  /// Version-path suffix auto-appended to New API hosts ('' = keep verbatim).
  final String endpointSuffix;
  final IconData icon;

  const ChannelProviderPreset({
    required this.id,
    required this.channelType,
    required this.group,
    this.defaultEndpoint,
    this.endpointSuffix = '',
    required this.icon,
  });

  /// True for the New API-style relays, whose base URL gains a version path.
  bool get isRelayBase => endpointSuffix.isNotEmpty;
}

const kChannelProviderPresets = <ChannelProviderPreset>[
  ChannelProviderPreset(
    id: 'openai-official',
    channelType: Vendors.openAIRest,
    group: ChannelProviderGroup.openai,
    defaultEndpoint: 'https://api.openai.com/v1',
    icon: Icons.api,
  ),
  ChannelProviderPreset(
    id: 'xai-official',
    channelType: Vendors.xaiApi,
    group: ChannelProviderGroup.openai,
    defaultEndpoint: 'https://api.x.ai/v1',
    icon: Icons.rocket_launch_outlined,
  ),
  ChannelProviderPreset(
    id: 'google-compatible',
    channelType: Vendors.openAIRest,
    group: ChannelProviderGroup.openai,
    defaultEndpoint: 'https://generativelanguage.googleapis.com/v1beta/openai',
    icon: Icons.swap_horiz,
  ),
  ChannelProviderPreset(
    id: 'deepseek',
    channelType: Vendors.deepseek,
    group: ChannelProviderGroup.openai,
    defaultEndpoint: 'https://api.deepseek.com',
    icon: Icons.psychology_outlined,
  ),
  ChannelProviderPreset(
    id: 'minimax',
    channelType: Vendors.minimax,
    group: ChannelProviderGroup.openai,
    icon: Icons.grain_outlined,
  ),
  ChannelProviderPreset(
    id: 'newapi-openai',
    channelType: Vendors.newApiOpenAI,
    group: ChannelProviderGroup.openai,
    endpointSuffix: '/v1',
    icon: Icons.hub_outlined,
  ),
  ChannelProviderPreset(
    id: 'dashscope',
    channelType: Vendors.dashscope,
    group: ChannelProviderGroup.openai,
    // Mainland host only. The international one (dashscope-intl.aliyuncs.com)
    // needs no preset of its own: the image protocol derives its native base
    // from the *path*, so a hand-typed intl endpoint works the same way.
    defaultEndpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    icon: Icons.water_drop_outlined,
  ),
  // Qianwen Platform (platform.qianwenai.com) — the rebranded front of the
  // same service: its docs point API calls at dashscope.aliyuncs.com with the
  // same key, so this is the [Vendors.dashscope] profile under the name users
  // of that console will look for, not a second vendor.
  ChannelProviderPreset(
    id: 'qianwen',
    channelType: Vendors.dashscope,
    group: ChannelProviderGroup.openai,
    defaultEndpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    icon: Icons.question_answer_outlined,
  ),
  ChannelProviderPreset(
    id: 'google-official',
    channelType: Vendors.googleRest,
    group: ChannelProviderGroup.google,
    defaultEndpoint: 'https://generativelanguage.googleapis.com/v1beta',
    icon: Icons.auto_awesome,
  ),
  ChannelProviderPreset(
    id: 'newapi-gemini',
    channelType: Vendors.newApiGemini,
    group: ChannelProviderGroup.google,
    endpointSuffix: '/v1beta',
    icon: Icons.hub_outlined,
  ),
  ChannelProviderPreset(
    id: 'anthropic-official',
    channelType: Vendors.anthropicRest,
    group: ChannelProviderGroup.anthropic,
    defaultEndpoint: 'https://api.anthropic.com/v1',
    icon: Icons.forum_outlined,
  ),
  ChannelProviderPreset(
    id: 'newapi-anthropic',
    channelType: Vendors.newApiAnthropic,
    group: ChannelProviderGroup.anthropic,
    endpointSuffix: '/v1',
    icon: Icons.hub_outlined,
  ),
  // The one Anthropic endpoint whose path is not `/v1`: MiniMax serves it
  // under `/anthropic/v1`, next to its OpenAI-format `/v1`. Worth a preset
  // purely so nobody has to know that — a channel pointed at the wrong one of
  // the two fails with a 404 that says nothing about which half of the URL is
  // wrong.
  ChannelProviderPreset(
    id: 'minimax-anthropic',
    channelType: Vendors.minimaxAnthropic,
    group: ChannelProviderGroup.anthropic,
    defaultEndpoint: 'https://api.minimaxi.com/anthropic/v1',
    icon: Icons.grain_outlined,
  ),
  ChannelProviderPreset(
    id: 'midjourney-proxy',
    channelType: Vendors.midjourneyProxy,
    group: ChannelProviderGroup.other,
    icon: Icons.brush_outlined,
  ),
  ChannelProviderPreset(
    id: 'custom',
    channelType: Vendors.openAIRest, // resolved by the dialog's dialect picker
    group: ChannelProviderGroup.other,
    icon: Icons.settings_input_component,
  ),
];

/// Heading a group sits under, in the picker's declaration order.
String channelProviderGroupLabel(
  AppLocalizations l10n,
  ChannelProviderGroup group,
) {
  switch (group) {
    case ChannelProviderGroup.openai:
      return l10n.protocolOpenAI;
    case ChannelProviderGroup.google:
      return l10n.protocolGoogle;
    case ChannelProviderGroup.anthropic:
      return l10n.protocolAnthropic;
    case ChannelProviderGroup.other:
      return l10n.providerGroupOther;
  }
}

String channelProviderTitle(AppLocalizations l10n, String id) {
  switch (id) {
    case 'openai-official':
      return l10n.providerOpenAIOfficial;
    case 'xai-official':
      return l10n.providerXaiOfficial;
    case 'google-compatible':
      return l10n.providerGoogleCompatible;
    case 'deepseek':
      return 'DeepSeek';
    case 'minimax':
      return 'MiniMax';
    case 'newapi-openai':
      return l10n.providerNewApiOpenAI;
    case 'google-official':
      return l10n.providerGoogleOfficial;
    case 'newapi-gemini':
      return l10n.providerNewApiGemini;
    case 'anthropic-official':
      return l10n.providerAnthropicOfficial;
    case 'newapi-anthropic':
      return l10n.providerNewApiAnthropic;
    case 'minimax-anthropic':
      return l10n.providerMiniMaxAnthropic;
    case 'dashscope':
      return l10n.providerDashScope;
    case 'qianwen':
      return l10n.providerQianwen;
    case 'midjourney-proxy':
      return l10n.protocolMidjourney;
    default:
      return l10n.providerCustom;
  }
}

String channelProviderSubtitle(
  AppLocalizations l10n,
  ChannelProviderPreset preset,
) {
  switch (preset.id) {
    case 'openai-official':
      return 'api.openai.com';
    case 'xai-official':
      return l10n.providerXaiOfficialDesc;
    case 'google-compatible':
      return l10n.providerGoogleCompatibleDesc;
    case 'google-official':
      return 'generativelanguage.googleapis.com';
    case 'deepseek':
      return 'api.deepseek.com';
    case 'minimax':
      return l10n.providerMiniMaxDesc;
    case 'minimax-anthropic':
      return 'api.minimaxi.com/anthropic/v1';
    case 'anthropic-official':
      return l10n.providerAnthropicOfficialDesc;
    case 'newapi-openai':
    case 'newapi-gemini':
    case 'newapi-anthropic':
      return l10n.providerNewApiDesc;
    case 'dashscope':
      return l10n.providerDashScopeDesc;
    case 'qianwen':
      return l10n.providerQianwenDesc;
    case 'midjourney-proxy':
      return l10n.protocolMidjourneyDesc;
    default:
      return l10n.providerCustomDesc;
  }
}

/// Every channel type the app can store, in the order the type dropdowns
/// offer them: grouped by protocol family, registry order within a family.
///
/// Derived from [Vendors.all] rather than hand-listed. A hand-listed dropdown
/// does not merely hide the vendor it forgets — Material asserts that a
/// dropdown's current value is among its items, so a channel of an omitted
/// type could not be opened for editing at all. DashScope shipped missing
/// from exactly that list; deriving it means the next vendor added to the
/// registry cannot repeat it.
List<String> channelTypesInDisplayOrder() => <String>[
      for (final family in const [
        ProtocolFamily.openai,
        ProtocolFamily.gemini,
        ProtocolFamily.anthropic,
        ProtocolFamily.midjourney,
      ])
        for (final vendor in Vendors.all)
          if (vendor.family == family) vendor.id,
    ];

/// How a channel type is named in the type dropdowns.
///
/// Presentation only — nothing branches on the answer — which is why a switch
/// over vendor ids is allowed to live here and not in `vendors/`. Every id in
/// [Vendors.all] must have a case: the `default` exists for channels carrying
/// a type this build no longer knows, not as a place for new vendors to land.
String channelTypeLabel(AppLocalizations l10n, String type) {
  switch (type) {
    case Vendors.openAIRest:
      return l10n.protocolOpenAI;
    case Vendors.newApiOpenAI:
      return l10n.providerNewApiOpenAI;
    case Vendors.xaiApi:
      return l10n.protocolXai;
    case Vendors.deepseek:
      return 'DeepSeek';
    case Vendors.minimax:
      return 'MiniMax';
    case Vendors.dashscope:
      return l10n.providerDashScope;
    case Vendors.googleRest:
      return l10n.protocolGoogle;
    case Vendors.officialGoogle:
      return 'Official Google GenAI API (Deprecated)';
    case Vendors.newApiGemini:
      return l10n.providerNewApiGemini;
    case Vendors.anthropicRest:
      return l10n.protocolAnthropic;
    case Vendors.newApiAnthropic:
      return l10n.providerNewApiAnthropic;
    case Vendors.minimaxAnthropic:
      return l10n.providerMiniMaxAnthropic;
    case Vendors.midjourneyProxy:
      return l10n.protocolMidjourney;
    default:
      return type;
  }
}
