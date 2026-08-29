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
  ///
  /// Note the difference from DashScope's two rows: those are two *faces*
  /// that differ in what they can do, so the choice is real and both rows
  /// carry the same aliases. Qianwen Platform was the same face under a
  /// second name, which is a choice nobody could make correctly.
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
  // Two rows rather than one row with a switch, unlike Google's pair: the two
  // faces here are not the same service in two dialects, they differ in what
  // they can do (qwen-audio only natively, Qwen-Omni's audio output only on
  // the compatible face), so which one a channel is on is worth reading off
  // the list rather than off a control inside it. Both rows name the same
  // company; the parenthetical is the whole distinction, so it is in the
  // title and not only in the subtitle.
  ChannelProviderPreset(
    id: 'dashscope',
    channelType: Vendors.dashscope,
    group: ChannelProviderGroup.vendor,
    // Mainland host only. The international one (dashscope-intl.aliyuncs.com)
    // needs no preset of its own: every native base is derived from the
    // *path*, so a hand-typed intl endpoint works the same way.
    defaultEndpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    searchAliases: [
      'qianwen',
      'qwen',
      '千问',
      '通义',
      '百炼',
      'bailian',
      'dashscope',
    ],
    icon: Icons.water_drop_outlined,
  ),
  ChannelProviderPreset(
    id: 'dashscope-native',
    channelType: Vendors.dashscopeNative,
    group: ChannelProviderGroup.vendor,
    defaultEndpoint: 'https://dashscope.aliyuncs.com/api/v1',
    // Same aliases as the row above: someone searching 千问 has to see both,
    // or the search silently picks the face for them.
    searchAliases: [
      'qianwen',
      'qwen',
      '千问',
      '通义',
      '百炼',
      'bailian',
      'dashscope',
    ],
    icon: Icons.water_drop_outlined,
  ),
  // One company, two protocol families: MiniMax serves its Anthropic-format
  // endpoint at `/anthropic/v1`, beside its OpenAI-format `/v1`. A channel
  // pointed at the wrong one fails with a 404 that says nothing about which
  // half of the URL is wrong, which is why the switch rewrites the path.
  //
  // The switch decides the *chat* wire only. Image generation (`/v1`) and
  // video (`/v2`) are the same surfaces either way, derived from whichever
  // face the channel stored — so neither variant is the one that "has
  // images", and picking the wrong one costs nothing but a chat dialect.
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
    searchAliases: [
      'minimaxi',
      '海螺',
      'hailuo',
      'MiniMax-M3',
      'MiniMax-H3',
      'image-01',
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

/// The preset a stored channel came from, or null when none matches.
///
/// Used by the editor's shortcut bar to say which preset a channel is sitting
/// on. Null is a first-class answer, not a failure: a channel created by an
/// older build can carry a type no current preset offers (the deprecated
/// `official-google-genai-api`), and the editor shows it as "no matching
/// preset" and leaves it alone rather than rewriting it (spec D2 `16e`).
///
/// [endpoint] is what disambiguates, and passing it matters. Several presets
/// legitimately store the *same* type — `openai-official` and `custom-openai`
/// both resolve to ①'s unspecified-supplier profile, `google` and
/// `custom-google` to ③'s — because "OpenAI compatible" is a wire format, not
/// a company. Type alone therefore cannot tell a channel pointed at
/// api.openai.com from one pointed at the user's own relay, and answering
/// `openai-official` for the relay is not merely a wrong label: the editor
/// then reads the address as *diverging from its preset*, flags it, and
/// offers a one-tap restore that overwrites a working endpoint with
/// `https://api.openai.com/v1`.
///
/// So: the preset whose default endpoint this channel actually sits on wins;
/// failing that, an address only the user knows *is* the custom preset, whose
/// silence about endpoints is the honest answer.
ChannelProviderPreset? presetForChannelType(String channelType,
    {String? endpoint}) {
  final matches = <ChannelProviderPreset>[
    for (final preset in kChannelProviderPresets)
      if (preset.hasVariants
          ? preset.variants.any((v) => v.channelType == channelType)
          : preset.channelType == channelType)
        preset,
  ];
  if (matches.length <= 1) return matches.isEmpty ? null : matches.first;

  final address = _normalizedEndpoint(endpoint);
  if (address != null) {
    for (final preset in matches) {
      final defaults = preset.hasVariants
          ? preset.variants.map((v) => v.defaultEndpoint)
          : [preset.defaultEndpoint];
      if (defaults.any((d) => _normalizedEndpoint(d) == address)) return preset;
    }
  }
  return matches.firstWhere(
    (p) => p.group == ChannelProviderGroup.custom,
    orElse: () => matches.first,
  );
}

/// An endpoint reduced to what makes two of them the same address: case and a
/// trailing slash are the two ways the identical host gets typed differently.
/// Null for "nothing to compare".
String? _normalizedEndpoint(String? endpoint) {
  var value = endpoint?.trim() ?? '';
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value.isEmpty ? null : value.toLowerCase();
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
      return l10n.providerDashScopeCompat;
    case 'dashscope-native':
      return l10n.providerDashScopeNative;
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
    case 'dashscope-native':
      return l10n.providerDashScopeNativeDesc;
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
    case ProtocolFamily.dashscope:
      // The one family with no "unspecified supplier": DashScope's native
      // wire is served by Alibaba's host and nowhere else, so the vendor
      // that represents the family is the company's own profile.
      return Vendors.dashscopeNative;
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
    case ProtocolFamily.dashscope:
      return 'DashScope · aigc/generation';
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
      return l10n.providerDashScopeCompat;
    case Vendors.dashscopeNative:
      return l10n.providerDashScopeNative;
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
