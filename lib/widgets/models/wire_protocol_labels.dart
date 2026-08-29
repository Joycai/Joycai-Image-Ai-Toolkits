import '../../l10n/app_localizations.dart';
import '../../services/llm/vendors/vendors.dart';

/// User-language display names for [WireProtocol] values, per spec D2 18a:
/// protocol names speak the user's language ("OpenAI 兼容", "异步任务"), never
/// wire/protocol jargon, and come from one enum → name table so the editor,
/// the model-card chip and the stale tooltip can never disagree.
///
/// Values that never appear in a menu (single fixed routes) keep readable
/// technical names untranslated — they are only ever seen in a stale tooltip
/// after a channel-type change, naming a thing that no longer applies.
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
    case WireProtocol.geminiChat:
      return 'Gemini';
    case WireProtocol.midjourney:
      return 'Midjourney';
    case WireProtocol.openaiImages:
      return 'Images API';
    case WireProtocol.xaiImages:
      return 'xAI Images';
    case WireProtocol.minimaxImages:
      return 'MiniMax Images';
    case WireProtocol.geminiImagen:
      return 'Imagen';
    case WireProtocol.openaiVideos:
      return 'Videos API';
    case WireProtocol.xaiVideos:
      return 'xAI Videos';
    case WireProtocol.minimaxVideo:
      return 'MiniMax Video';
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
    default:
      return null;
  }
}

/// The name shown for a *stored* selection string: the enum's label when it
/// parses, the raw string otherwise (a value from a newer build still names
/// itself in the stale notice instead of vanishing).
String storedProtocolLabel(AppLocalizations l10n, String stored) {
  final parsed = WireProtocol.tryParse(stored);
  return parsed == null ? stored : wireProtocolLabel(l10n, parsed);
}
