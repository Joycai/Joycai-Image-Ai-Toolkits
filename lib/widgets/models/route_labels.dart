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
