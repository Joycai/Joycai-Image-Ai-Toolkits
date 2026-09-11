import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/scroll_edge_fade.dart';
import 'downloader_inputs.dart';

enum _LogTone { plain, ok, warn, err }

/// The analysis log (`B3 · 1a`, `1b`): a fixed 196px opaque panel — content,
/// not a control, so never glass — with a 40px header, a 2px progress line
/// while analyzing, and a mono body that follows the tail.
///
/// Following stops the moment the user scrolls away from the bottom and
/// resumes once they scroll back to it. The panel's height never changes with
/// the number of lines; the parent animates it open and closed.
class DownloaderLogPanel extends StatefulWidget {
  const DownloaderLogPanel({
    super.key,
    required this.logs,
    required this.isAnalyzing,
    required this.onClose,
  });

  /// The panel's fixed height (`日志面板 196`).
  static const double height = 196;

  final List<String> logs;
  final bool isAnalyzing;
  final VoidCallback onClose;

  @override
  State<DownloaderLogPanel> createState() => _DownloaderLogPanelState();
}

class _DownloaderLogPanelState extends State<DownloaderLogPanel> {
  static final RegExp _linePattern = RegExp(r'^\[(.+?)\]\s*(.*)$');

  /// How close to the bottom still counts as "at the tail".
  static const double _followSlack = 8;

  final ScrollController _scroll = ScrollController();
  bool _following = true;

  /// [DownloaderState] appends to one list in place, so the length is what
  /// tells a rebuild with new lines from any other rebuild.
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _seen = widget.logs.length;
    _jumpToTail();
  }

  @override
  void didUpdateWidget(DownloaderLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final length = widget.logs.length;
    if (length == _seen) return;
    // A shorter list is a fresh analysis: start at its tail again.
    if (length < _seen) _following = true;
    _seen = length;
    if (_following) _jumpToTail();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels < position.maxScrollExtent) {
        _scroll.jumpTo(position.maxScrollExtent);
      }
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification ||
        notification is UserScrollNotification) {
      _following = notification.metrics.extentAfter <= _followSlack;
    }
    return false;
  }

  /// A presentation heuristic over the scraper's English log wording: which
  /// lines read as a hit, a caution or a failure.
  static _LogTone _toneOf(String message) {
    final m = message.toLowerCase();
    if (m.startsWith('error') || m.startsWith('failed') || m.contains('failed:')) {
      return _LogTone.err;
    }
    if (m.startsWith('no images') ||
        m.contains('no matching images') ||
        m.startsWith('rejected') ||
        m.contains('asking again') ||
        m.startsWith('warning')) {
      return _LogTone.warn;
    }
    if (m.startsWith('found ') ||
        m.startsWith('html saved') ||
        m.startsWith('pasted html') ||
        m.startsWith('llm analysis complete') ||
        m.startsWith('model selected')) {
      return _LogTone.ok;
    }
    return _LogTone.plain;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final base = Theme.of(context).textTheme.labelSmall!.mono.copyWith(
          fontWeight: FontWeight.w400,
          height: 1.75,
          color: scheme.onSurfaceVariant,
        );

    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: AppSize.large,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: kDownloaderGutter, end: 12),
                child: Row(
                  children: [
                    Icon(Icons.terminal, size: AppSize.iconMd, color: scheme.primary),
                    const SizedBox(width: AppSpace.s10),
                    Expanded(
                      child: Text(
                        l10n.logs.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: downloaderTrackedCaptionStyle(context),
                      ),
                    ),
                    DownloaderActionButton(
                      icon: Icons.copy,
                      label: l10n.copyLogs,
                      outlined: false,
                      height: AppSize.compact,
                      iconSize: AppSize.iconSm,
                      onPressed: () => Clipboard.setData(ClipboardData(text: widget.logs.join('\n'))),
                    ),
                    const SizedBox(width: AppSpace.s4),
                    DownloaderActionButton(
                      icon: Icons.close,
                      tooltip: l10n.close,
                      outlined: false,
                      height: AppSize.compact,
                      foreground: scheme.onSurfaceVariant,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 2,
              width: double.infinity,
              child: widget.isAnalyzing
                  ? LinearProgressIndicator(
                      minHeight: 2,
                      color: scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    )
                  : null,
            ),
            Expanded(
              child: ScrollEdgeFade(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: kDownloaderGutter, vertical: AppSpace.s10),
                    itemCount: widget.logs.length,
                    itemBuilder: (context, i) {
                      final line = widget.logs[i];
                      final match = _linePattern.firstMatch(line);
                      final time = match?.group(1);
                      final message = match?.group(2) ?? line;
                      final Color ink = switch (_toneOf(message)) {
                        _LogTone.err => scheme.onErrorContainer,
                        _LogTone.warn => semantic.onWarningContainer,
                        _LogTone.ok => semantic.onSuccessContainer,
                        _LogTone.plain => scheme.onSurfaceVariant,
                      };
                      return Text.rich(
                        TextSpan(
                          style: base,
                          children: [
                            if (time != null)
                              TextSpan(text: '$time  ', style: TextStyle(color: scheme.outline)),
                            TextSpan(text: message, style: TextStyle(color: ink)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
