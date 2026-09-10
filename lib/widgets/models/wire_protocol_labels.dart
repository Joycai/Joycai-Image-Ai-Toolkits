import '../../l10n/app_localizations.dart';
import '../../services/llm/vendors/vendors.dart';

/// User-language display names for [WireProtocol] values, per spec D2 18a and
/// D2a: protocol names speak the user's language ("OpenAI 兼容", "对话出图"),
/// never wire jargon, and come from one enum → name table so the editor, the
/// model-card chip and the stale tooltip can never disagree.
///
/// A handful keep a product name as their name ("Images API", "Imagen",
/// "Veo") because that is the word a relay's documentation uses for them —
/// the path at the end of the menu row ([wireProtocolPath]) is what lets a
/// user match the two up.
String wireProtocolLabel(AppLocalizations l10n, WireProtocol protocol) {
  switch (protocol) {
    case WireProtocol.openaiChat:
      return l10n.protocolOpenAICompat;
    case WireProtocol.anthropicChat:
      return l10n.protocolAnthropicCompat;
    case WireProtocol.dashscopeChat:
      return l10n.protocolDashScopeNative;
    case WireProtocol.dashscopeImagesSync:
      return l10n.protocolImageSync;
    case WireProtocol.dashscopeImagesAsync:
      return l10n.protocolImageAsync;
    case WireProtocol.chatImage:
      return l10n.protocolChatImage;
    case WireProtocol.geminiChat:
      return 'Gemini';
    case WireProtocol.midjourney:
      return 'Midjourney';
    case WireProtocol.openaiImages:
      return 'Images API';
    case WireProtocol.xaiImages:
      return l10n.protocolXaiImages;
    case WireProtocol.minimaxImages:
      return l10n.protocolMinimaxImages;
    case WireProtocol.geminiImagen:
      return 'Imagen';
    case WireProtocol.openaiVideos:
      return 'Videos API';
    case WireProtocol.xaiVideos:
      return l10n.protocolXaiVideos;
    case WireProtocol.minimaxVideo:
      return l10n.protocolMinimaxVideo;
    case WireProtocol.minimaxH3BaseVideo:
      return 'MiniMax H3 (Local)';
    case WireProtocol.geminiVeo:
      return 'Veo';
    case WireProtocol.dashscopeVideo:
      return l10n.protocolVideoTask;
  }
}

/// One-line description for a menu entry, or null where the name says it all.
String? wireProtocolDescription(AppLocalizations l10n, WireProtocol protocol) {
  switch (protocol) {
    case WireProtocol.dashscopeChat:
      return l10n.protocolDashScopeNativeDesc;
    case WireProtocol.dashscopeImagesSync:
      return l10n.protocolImageSyncDesc;
    case WireProtocol.dashscopeImagesAsync:
      return l10n.protocolImageAsyncDesc;
    case WireProtocol.chatImage:
      return l10n.protocolChatImageDesc;
    case WireProtocol.openaiImages:
      return l10n.protocolImagesApiDesc;
    case WireProtocol.geminiImagen:
      return l10n.protocolImagenDesc;
    case WireProtocol.openaiVideos:
      return l10n.protocolVideosApiDesc;
    case WireProtocol.geminiVeo:
      return l10n.protocolVeoDesc;
    default:
      return null;
  }
}

/// The endpoint a protocol is served on, spelled the way a relay's docs spell
/// it, or null where there is no single path worth showing.
///
/// Shown only at the end of an expanded menu row and in the phone's bottom
/// sheet (D2a ruling 3) — never in the closed field or on a card, and never
/// translated. The name keeps speaking the user's language; the path is for
/// the relay user who has the relay's documentation open beside the dialog.
///
/// [channelFamily] matters for one entry alone: images through chat ride
/// whichever chat wire the channel speaks.
String? wireProtocolPath(WireProtocol protocol, ProtocolFamily channelFamily) {
  switch (protocol) {
    case WireProtocol.openaiChat:
      return '/v1/chat/completions';
    case WireProtocol.anthropicChat:
      return '/v1/messages';
    case WireProtocol.geminiChat:
      return ':generateContent';
    case WireProtocol.openaiImages:
      return '/v1/images/generations';
    case WireProtocol.geminiImagen:
      return ':predict';
    case WireProtocol.openaiVideos:
      return '/v1/videos';
    case WireProtocol.geminiVeo:
      return ':predictLongRunning';
    case WireProtocol.chatImage:
      switch (channelFamily) {
        case ProtocolFamily.openai:
          return '/v1/chat/completions';
        case ProtocolFamily.gemini:
          return ':generateContent';
        case ProtocolFamily.anthropic:
          return '/v1/messages';
        case ProtocolFamily.dashscope:
        case ProtocolFamily.midjourney:
          return null;
      }
    default:
      return null;
  }
}

/// A channel's wire format as a short brand name, for sentences like
/// 「此渠道是 Claude 格式」. Untranslated: these are names, and the
/// channel editor's own family label is a technical path rather than
/// something to put in prose.
String protocolFamilyFormatName(ProtocolFamily family) {
  switch (family) {
    case ProtocolFamily.openai:
      return 'OpenAI';
    case ProtocolFamily.gemini:
      return 'Gemini';
    case ProtocolFamily.anthropic:
      return 'Claude';
    case ProtocolFamily.midjourney:
      return 'Midjourney';
    case ProtocolFamily.dashscope:
      return 'DashScope';
  }
}

/// What is worth knowing about [protocol] on a channel of [channelFamily],
/// stated as a fact rather than a warning, or null when nothing is.
///
/// One case today (D2a 9′): images through chat on a Claude-format channel.
/// The protocol itself hardly ever returns images, but the relay behind it
/// may well be fronting a backend that does — so it is said, not blocked.
String? wireProtocolCaveat(
    AppLocalizations l10n, WireProtocol protocol, ProtocolFamily channelFamily) {
  if (protocol == WireProtocol.chatImage &&
      channelFamily == ProtocolFamily.anthropic) {
    return l10n.protocolChatImageUnlikely(protocolFamilyFormatName(channelFamily));
  }
  return null;
}

/// The name shown for a *stored* selection string: the enum's label when it
/// parses, the raw string otherwise (a value from a newer build still names
/// itself in the stale notice instead of vanishing).
String storedProtocolLabel(AppLocalizations l10n, String stored) {
  final parsed = WireProtocol.tryParse(stored);
  return parsed == null ? stored : wireProtocolLabel(l10n, parsed);
}
