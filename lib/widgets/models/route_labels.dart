import '../../l10n/app_localizations.dart';
import '../../services/llm/vendors/platforms.dart';

/// A route's name, from one table so the channel rail, the channel editor,
/// the model card and the model editor's route strip never disagree
/// (`D1f` 词汇). Routes are named, never numbered.
///
/// [short] is the rail and table form (Chat · Resp · Anth · Gemini · 百炼 ·
/// MJ); the full form goes wherever there is room for it — a model card's
/// tail, the editor's strip, the switch preview.
String routeLabel(AppLocalizations l10n, RouteKind kind, {bool short = false}) {
  switch (kind) {
    case RouteKind.chat:
      return short ? 'Chat' : 'Chat Completions';
    case RouteKind.responses:
      return short ? 'Resp' : 'Responses';
    case RouteKind.anthropic:
      return short ? 'Anth' : 'Anthropic';
    case RouteKind.gemini:
      return 'Gemini';
    case RouteKind.dashscope:
      return short ? l10n.routeDashScopeShort : l10n.routeDashScopeFull;
    case RouteKind.midjourney:
      return short ? 'MJ' : 'Midjourney';
  }
}

/// A platform's name — the channel rail's subline and the channel header
/// (`D1f · 4a`), in place of the vendor id the header used to print.
String platformLabel(AppLocalizations l10n, PlatformProfile platform) {
  switch (platform.id) {
    case Platforms.openai:
      return 'OpenAI';
    case Platforms.anthropic:
      return 'Anthropic';
    case Platforms.google:
      return 'Google GenAI';
    case Platforms.xai:
      return 'xAI';
    case Platforms.deepseek:
      return 'DeepSeek';
    case Platforms.minimax:
      return 'MiniMax';
    case Platforms.dashscope:
      return l10n.platformDashScope;
    case Platforms.ark:
      return l10n.providerVolcengineArk;
    case Platforms.newapi:
      return 'New API';
    case Platforms.midjourney:
      return 'Midjourney Proxy';
    case Platforms.ollama:
      return 'Ollama';
    case Platforms.lmStudio:
      return 'LM Studio';
    case Platforms.h3Base:
      return 'MiniMax H3';
    default:
      return l10n.platformCustom;
  }
}
