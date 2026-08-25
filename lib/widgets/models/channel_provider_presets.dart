import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/llm/vendors/vendors.dart';

/// The headings the provider picker groups presets under, in display order.
///
/// **These are about "who is this", not about the wire protocol.** The picker
/// used to group by protocol family — "OPENAI 兼容协议 (REST)", "GOOGLE GENAI
/// 协议 (REST)" — which is an implementation detail wearing a heading: nobody
/// sets out to add "an OpenAI-compatible thing", they set out to add Alibaba
/// DashScope. The family is still what the dispatcher routes on, but it is
/// now *derived* from the chosen provider rather than being the way in.
///
/// Spec D2 frame `16a`, note ①.
enum ChannelProviderGroup {
  /// First-party suppliers. Endpoint is known, so the user only brings a key.
  vendor,

  /// Relays and proxies: the protocol is known, the host is the user's own.
  relay,

  /// Anything else speaking a known dialect at an address only the user knows.
  custom,

  /// Locally-hosted runtimes. Default to localhost and need no API key.
  local,
}

/// What a preset row promises about the *next* step, printed at its end.
///
/// Spec D2 `16a` note ③: the row says what you will have to supply, so the
/// choice is made knowing whether a key, an address, or nothing is needed.
enum ChannelProviderNeed { keyOnly, endpoint, keyless }

/// One of the two-or-three ways a single provider can be reached.
///
/// Only three presets have these — Google GenAI (native vs its OpenAI-compat
/// face), MiniMax (its ① and its ④ endpoint) and NewAPI (three relay formats)
/// — and all three change *which channel type is stored* and *what the
/// endpoint ends with*. That coupling is the whole reason the picker renders
/// them as a segmented control sitting directly above the endpoint field
/// rather than as sub-rows in the rail: the switch and the field it rewrites
/// have to be visible at the same time (spec D2 `16b`).
class ChannelProviderVariant {
  /// Identifies the variant for its label lookup; scoped to its preset.
  final String id;

  /// The vendor id this variant resolves to — what lands in
  /// `llm_channels.type`.
  final String channelType;

  /// Endpoint prefilled when this variant is chosen; null for relays whose
  /// host only the user knows.
  final String? defaultEndpoint;

  /// Version-path suffix appended to a user-typed relay host ('' = verbatim).
  final String endpointSuffix;

  const ChannelProviderVariant({
    required this.id,
    required this.channelType,
    this.defaultEndpoint,
    this.endpointSuffix = '',
  });
}

/// A provider offered by the add-channel picker, and — since the redesign —
/// by the channel editor's "change preset" overlay as well. One catalogue,
/// two dialogs: the editor used to carry its own hand-written list of channel
/// types, which is how DashScope came to be offered when adding a channel but
/// missing when editing one.
class ChannelProviderPreset {
  final String id;

  /// Vendor id stored in `llm_channels.type`. For a preset with [variants]
  /// this is the first variant's type — the default selection.
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

  /// The two-or-three ways this provider can be reached; empty for the
  /// fourteen-minus-three that have exactly one.
  final List<ChannelProviderVariant> variants;

  /// Extra search terms that should land on this row.
  ///
  /// Carries the names a provider is known by other than the one printed:
  /// 千问 / Qwen / 通义 all reach DashScope, which is what let the separate
  /// "Qianwen Platform" row — same API, same key, same host — be folded back
  /// into it rather than making users pick between two spellings of one
  /// service (spec D2 `16a`, the 千问 recommendation).
  final List<String> searchAliases;

  /// What this row promises the user will have to supply next.
  final ChannelProviderNeed need;

  final IconData icon;

  const ChannelProviderPreset({
    required this.id,
    required this.channelType,
    required this.group,
    this.defaultEndpoint,
    this.endpointSuffix = '',
    this.variants = const [],
    this.searchAliases = const [],
    this.need = ChannelProviderNeed.keyOnly,
    required this.icon,
  });

  /// True for the New API-style relays, whose base URL gains a version path.
  bool get isRelayBase => endpointSuffix.isNotEmpty;

  bool get hasVariants => variants.isNotEmpty;
}

const kChannelProviderPresets = <ChannelProviderPreset>[
  // --- 厂商 · first-party suppliers -----------------------------------------
  ChannelProviderPreset(
    id: 'anthropic-official',
    channelType: Vendors.anthropicRest,
    group: ChannelProviderGroup.vendor,
    defaultEndpoint: 'https://api.anthropic.com/v1',
    searchAliases: ['claude'],
    icon: Icons.forum_outlined,
  ),
  // Google serves the same models through two faces, and which one a channel
  // uses decides its protocol family — so it is one row with a switch, not
  // two rows a user has to know the difference between.
  ChannelProviderPreset(
    id: 'google',
    channelType: Vendors.googleRest,
    group: ChannelProviderGroup.vendor,
    defaultEndpoint: 'https://generativelanguage.googleapis.com/v1beta',
    variants: [
      ChannelProviderVariant(
        id: 'native',
        channelType: Vendors.googleRest,
        defaultEndpoint: 'https://generativelanguage.googleapis.com/v1beta',
      ),
      ChannelProviderVariant(
        id: 'openai-compatible',
        channelType: Vendors.openAIRest,
        defaultEndpoint:
            'https://generativelanguage.googleapis.com/v1beta/openai',
      ),
    ],
    searchAliases: ['gemini', 'genai'],
    icon: Icons.auto_awesome,
  ),
  ChannelProviderPreset(
    id: 'openai-official',
    channelType: Vendors.openAIRest,
    group: ChannelProviderGroup.vendor,
    defaultEndpoint: 'https://api.openai.com/v1',
    searchAliases: ['gpt', 'chatgpt'],
    icon: Icons.api,
  ),
  ChannelProviderPreset(
    id: 'xai-official',
    channelType: Vendors.xaiApi,
    group: ChannelProviderGroup.vendor,
    defaultEndpoint: 'https://api.x.ai/v1',
    searchAliases: ['grok'],
    icon: Icons.rocket_launch_outlined,
  ),
  // The former separate "Qianwen Platform" row folded in as aliases: the
  // rebranded console points at the same host with the same key, so two rows
  // only ever made people wonder which of them was the right one.
  ChannelProviderPreset(
    id: 'dashscope',
    channelType: Vendors.dashscope,
    group: ChannelProviderGroup.vendor,
    // Mainland host only. The international one (dashscope-intl.aliyuncs.com)
    // needs no preset of its own: the image protocol derives its native base
    // from the *path*, so a hand-typed intl endpoint works the same way.
    defaultEndpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    searchAliases: ['qianwen', 'qwen', '千问', '通义', '百炼', 'bailian'],
    icon: Icons.water_drop_outlined,
  ),
  // One company, two protocol families: MiniMax serves its Anthropic-format
  // endpoint at `/anthropic/v1`, beside its OpenAI-format `/v1`. A channel
  // pointed at the wrong one fails with a 404 that says nothing about which
  // half of the URL is wrong, which is why the switch rewrites the path.
  ChannelProviderPreset(
    id: 'minimax',
    channelType: Vendors.minimax,
    group: ChannelProviderGroup.vendor,
    defaultEndpoint: 'https://api.minimaxi.com/v1',
    variants: [
      // Both faces prefill. The ① one used to supply no address at all, which
      // left the field empty until you switched to ④ and full again when you
      // switched back — a preset that fills the endpoint only half the time
      // reads as a bug in the switch.
      ChannelProviderVariant(
        id: 'openai',
        channelType: Vendors.minimax,
        defaultEndpoint: 'https://api.minimaxi.com/v1',
      ),
      ChannelProviderVariant(
        id: 'anthropic',
        channelType: Vendors.minimaxAnthropic,
        defaultEndpoint: 'https://api.minimaxi.com/anthropic/v1',
      ),
    ],
    icon: Icons.grain_outlined,
  ),
  ChannelProviderPreset(
    id: 'deepseek',
    channelType: Vendors.deepseek,
    group: ChannelProviderGroup.vendor,
    defaultEndpoint: 'https://api.deepseek.com',
    icon: Icons.psychology_outlined,
  ),

  // --- 中转站 · relays -------------------------------------------------------
  // Three formats behind one row: the supplier is the same New API host, and
  // the format decides both the stored type and the version path appended to
  // whatever host the user types.
  ChannelProviderPreset(
    id: 'newapi',
    channelType: Vendors.newApiOpenAI,
    group: ChannelProviderGroup.relay,
    endpointSuffix: '/v1',
    variants: [
      ChannelProviderVariant(
        id: 'openai',
        channelType: Vendors.newApiOpenAI,
        endpointSuffix: '/v1',
      ),
      ChannelProviderVariant(
        id: 'gemini',
        channelType: Vendors.newApiGemini,
        endpointSuffix: '/v1beta',
      ),
      ChannelProviderVariant(
        id: 'anthropic',
        channelType: Vendors.newApiAnthropic,
        endpointSuffix: '/v1',
      ),
    ],
    searchAliases: ['new api', 'oneapi'],
    need: ChannelProviderNeed.endpoint,
    icon: Icons.hub_outlined,
  ),
  ChannelProviderPreset(
    id: 'midjourney-proxy',
    channelType: Vendors.midjourneyProxy,
    group: ChannelProviderGroup.relay,
    need: ChannelProviderNeed.endpoint,
    icon: Icons.brush_outlined,
  ),

  // --- 自定义 · known dialect, unknown host ----------------------------------
  // What used to be one `custom` row plus a separate dialect segmented
  // control. Three explicit rows instead: picking one settles the protocol,
  // which is one interaction fewer and one fewer thing to get wrong.
  ChannelProviderPreset(
    id: 'custom-openai',
    channelType: Vendors.openAIRest,
    group: ChannelProviderGroup.custom,
    need: ChannelProviderNeed.endpoint,
    icon: Icons.data_object,
  ),
  ChannelProviderPreset(
    id: 'custom-google',
    channelType: Vendors.googleRest,
    group: ChannelProviderGroup.custom,
    need: ChannelProviderNeed.endpoint,
    icon: Icons.data_object,
  ),
  ChannelProviderPreset(
    id: 'custom-anthropic',
    channelType: Vendors.anthropicRest,
    group: ChannelProviderGroup.custom,
    need: ChannelProviderNeed.endpoint,
    icon: Icons.data_object,
  ),

  // --- 本地 · localhost runtimes --------------------------------------------
  ChannelProviderPreset(
    id: 'ollama',
    channelType: Vendors.ollama,
    group: ChannelProviderGroup.local,
    defaultEndpoint: 'http://localhost:11434/v1',
    need: ChannelProviderNeed.keyless,
    icon: Icons.dns_outlined,
  ),
  ChannelProviderPreset(
    id: 'lm-studio',
    channelType: Vendors.lmStudio,
    group: ChannelProviderGroup.local,
    defaultEndpoint: 'http://localhost:1234/v1',
    need: ChannelProviderNeed.keyless,
    icon: Icons.dns_outlined,
  ),
];

/// The preset a stored channel type came from, or null when none matches.
///
/// Used by the editor's shortcut bar to say which preset a channel is sitting
/// on. Null is a first-class answer, not a failure: a channel created by an
/// older build can carry a type no current preset offers (the deprecated
/// `official-google-genai-api`), and the editor shows it as "no matching
/// preset" and leaves it alone rather than rewriting it (spec D2 `16e`).
ChannelProviderPreset? presetForChannelType(String channelType) {
  for (final preset in kChannelProviderPresets) {
    if (preset.hasVariants) {
      for (final variant in preset.variants) {
        if (variant.channelType == channelType) return preset;
      }
    } else if (preset.channelType == channelType) {
      return preset;
    }
  }
  return null;
}

/// The variant of [preset] a stored channel type corresponds to, or null.
ChannelProviderVariant? variantForChannelType(
  ChannelProviderPreset preset,
  String channelType,
) {
  for (final variant in preset.variants) {
    if (variant.channelType == channelType) return variant;
  }
  return null;
}

/// Heading a group sits under, in the picker's declaration order.
String channelProviderGroupLabel(
  AppLocalizations l10n,
  ChannelProviderGroup group,
) {
  switch (group) {
    case ChannelProviderGroup.vendor:
      return l10n.providerGroupVendor;
    case ChannelProviderGroup.relay:
      return l10n.providerGroupRelay;
    case ChannelProviderGroup.custom:
      return l10n.providerGroupCustom;
    case ChannelProviderGroup.local:
      return l10n.providerGroupLocal;
  }
}

/// The one-line qualifier printed beside a group heading — what this whole
/// group will ask of you (spec D2 `16a` note ③).
String channelProviderGroupHint(
  AppLocalizations l10n,
  ChannelProviderGroup group,
) {
  switch (group) {
    case ChannelProviderGroup.vendor:
      return l10n.providerGroupVendorHint;
    case ChannelProviderGroup.relay:
      return l10n.providerGroupRelayHint;
    case ChannelProviderGroup.custom:
      return l10n.providerGroupCustomHint;
    case ChannelProviderGroup.local:
      return l10n.providerGroupLocalHint;
  }
}

/// The trailing note on a preset row: what it will ask for next.
String channelProviderNeedLabel(
  AppLocalizations l10n,
  ChannelProviderNeed need,
) {
  switch (need) {
    case ChannelProviderNeed.keyOnly:
      return l10n.providerNeedKeyOnly;
    case ChannelProviderNeed.endpoint:
      return l10n.providerNeedEndpoint;
    case ChannelProviderNeed.keyless:
      return l10n.providerNeedKeyless;
  }
}

String channelProviderTitle(AppLocalizations l10n, String id) {
  switch (id) {
    case 'anthropic-official':
      return 'Anthropic';
    case 'google':
      return 'Google GenAI';
    case 'openai-official':
      return 'OpenAI';
    case 'xai-official':
      return 'xAI (Grok)';
    case 'dashscope':
      return l10n.providerDashScope;
    case 'minimax':
      return 'MiniMax';
    case 'deepseek':
      return 'DeepSeek';
    case 'newapi':
      return 'NewAPI';
    case 'midjourney-proxy':
      return l10n.protocolMidjourney;
    case 'custom-openai':
      return 'OpenAI Compatible';
    case 'custom-google':
      return 'GoogleGenAI Compatible';
    case 'custom-anthropic':
      return 'Anthropic Compatible';
    case 'ollama':
      return 'Ollama';
    case 'lm-studio':
      return 'LM Studio';
    default:
      return l10n.providerCustom;
  }
}

String channelProviderSubtitle(
  AppLocalizations l10n,
  ChannelProviderPreset preset,
) {
  switch (preset.id) {
    case 'anthropic-official':
      return 'api.anthropic.com';
    case 'google':
      return 'generativelanguage.googleapis.com';
    case 'openai-official':
      return 'api.openai.com';
    case 'xai-official':
      return l10n.providerXaiOfficialDesc;
    case 'dashscope':
      return l10n.providerDashScopeDesc;
    case 'minimax':
      return l10n.providerMiniMaxDesc;
    case 'deepseek':
      return 'api.deepseek.com';
    case 'newapi':
      return l10n.providerNewApiDesc;
    case 'midjourney-proxy':
      return l10n.protocolMidjourneyDesc;
    case 'custom-openai':
      return l10n.providerCustomOpenAIDesc;
    case 'custom-google':
      return l10n.providerCustomGoogleDesc;
    case 'custom-anthropic':
      return l10n.providerCustomAnthropicDesc;
    case 'ollama':
      return 'localhost:11434';
    case 'lm-studio':
      return 'localhost:1234';
    default:
      return l10n.providerCustomDesc;
  }
}

/// Heading of the variant switch — "接入面", "接口格式", "接入方式". Named per
/// preset because the choice means something different in each: two faces of
/// one company, three formats of one relay, two protocols of one host.
String channelProviderVariantTitle(AppLocalizations l10n, String presetId) {
  switch (presetId) {
    case 'google':
      return l10n.variantTitleGoogle;
    case 'minimax':
      return l10n.variantTitleMiniMax;
    case 'newapi':
      return l10n.variantTitleNewApi;
    default:
      return l10n.variantTitleGeneric;
  }
}

/// The sentence under the variant switch explaining what switching rewrites.
String channelProviderVariantHint(AppLocalizations l10n, String presetId) {
  switch (presetId) {
    case 'google':
      return l10n.variantHintGoogle;
    case 'minimax':
      return l10n.variantHintMiniMax;
    case 'newapi':
      return l10n.variantHintNewApi;
    default:
      return l10n.variantHintGeneric;
  }
}

String channelProviderVariantLabel(
  AppLocalizations l10n,
  String presetId,
  String variantId,
) {
  switch ('$presetId/$variantId') {
    case 'google/native':
      return l10n.variantGoogleNative;
    case 'google/openai-compatible':
      return l10n.variantGoogleOpenAI;
    case 'minimax/openai':
      return l10n.variantMiniMaxOpenAI;
    case 'minimax/anthropic':
      return l10n.variantMiniMaxAnthropic;
    case 'newapi/openai':
      return l10n.variantNewApiOpenAI;
    case 'newapi/gemini':
      return l10n.variantNewApiGemini;
    case 'newapi/anthropic':
      return l10n.variantNewApiAnthropic;
    default:
      return variantId;
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

/// The generic vendor that represents a protocol family on its own — what a
/// channel becomes when the user picks a family in the editor's protocol
/// field rather than picking a supplier.
///
/// "This host speaks Anthropic" is a claim about the wire format and nothing
/// else, so it resolves to the family's unspecified-supplier profile rather
/// than to any company's.
String genericVendorForFamily(ProtocolFamily family) {
  switch (family) {
    case ProtocolFamily.openai:
      return Vendors.openAIRest;
    case ProtocolFamily.gemini:
      return Vendors.googleRest;
    case ProtocolFamily.anthropic:
      return Vendors.anthropicRest;
    case ProtocolFamily.midjourney:
      return Vendors.midjourneyProxy;
  }
}

/// How a protocol family reads in the editor's 接口协议 field: the family and
/// the request path that identifies it, e.g. `OpenAI · chat/completions`.
/// Spec D2 `16d` note B — the old field mixed protocol and company into one
/// list; this half names only the wire format.
String protocolFamilyLabel(AppLocalizations l10n, ProtocolFamily family) {
  switch (family) {
    case ProtocolFamily.openai:
      return 'OpenAI · chat/completions';
    case ProtocolFamily.gemini:
      return 'Google GenAI · generateContent';
    case ProtocolFamily.anthropic:
      return 'Anthropic · messages';
    case ProtocolFamily.midjourney:
      return 'Midjourney · /mj';
  }
}

/// How a channel type is named where the raw vendor has to be shown — the
/// editor's protocol field when a stored type is not one of the four generic
/// families, and the deprecated entries kept only so an old channel still
/// opens.
///
/// Presentation only — nothing branches on the answer — which is why a switch
/// over vendor ids is allowed to live here and not in `vendors/`. Every id in
/// [Vendors.all] must have a case: the `default` exists for channels carrying
/// a type this build no longer knows, not as a place for new vendors to land.
String channelTypeLabel(AppLocalizations l10n, String type) {
  switch (type) {
    case Vendors.openAIRest:
      return protocolFamilyLabel(l10n, ProtocolFamily.openai);
    case Vendors.googleRest:
      return protocolFamilyLabel(l10n, ProtocolFamily.gemini);
    case Vendors.anthropicRest:
      return protocolFamilyLabel(l10n, ProtocolFamily.anthropic);
    case Vendors.midjourneyProxy:
      return protocolFamilyLabel(l10n, ProtocolFamily.midjourney);
    case Vendors.newApiOpenAI:
      return l10n.providerNewApiOpenAI;
    case Vendors.newApiGemini:
      return l10n.providerNewApiGemini;
    case Vendors.newApiAnthropic:
      return l10n.providerNewApiAnthropic;
    case Vendors.xaiApi:
      return l10n.protocolXai;
    case Vendors.deepseek:
      return 'DeepSeek';
    case Vendors.minimax:
      return 'MiniMax';
    case Vendors.minimaxAnthropic:
      return l10n.providerMiniMaxAnthropic;
    case Vendors.dashscope:
      return l10n.providerDashScope;
    case Vendors.ollama:
      return 'Ollama';
    case Vendors.lmStudio:
      return 'LM Studio';
    case Vendors.officialGoogle:
      return 'Official Google GenAI API';
    default:
      return type;
  }
}

/// Channel types kept in the editor's protocol list only so that a channel
/// created by an older build still opens. Rendered last and greyed, with a
/// "deprecated" note; selecting one away is a one-way trip (spec D2 `16e`).
bool isDeprecatedChannelType(String type) => type == Vendors.officialGoogle;
