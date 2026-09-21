part of '../optimizer_config_panel.dart';

/// A deep-ink text action with no box — the knowledge card's Rescan and Open
/// in Folder.
///
/// Not a text [AppButton]: that one insets its label 10px, and `A3b 1b` draws
/// these flush with the path and counts beside them.
class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap, this.loading = false});

  final String label;
  final VoidCallback? onTap;

  /// Shows a spinner before the label and takes the action out of reach.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onTap != null && !loading;
    final color = enabled ? colorScheme.accentText : colorScheme.outline;

    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                SizedBox.square(
                  dimension: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
                ),
                const SizedBox(width: AppSpace.s6),
              ],
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A filesystem path that loses its *head* when it does not fit, never its
/// tail.
///
/// `TextOverflow.ellipsis` cuts the end, which on a path throws away the one
/// segment that identifies it — `D:\github\gemini-prompt-generater\knowl…`
/// tells the user nothing they did not already know, while `…\knowledge` tells
/// them exactly which folder the assistant is reading. Whole segments are
/// dropped rather than characters, so what remains is always a real path
/// fragment.
class _ElidedPath extends StatelessWidget {
  final String path;
  final TextStyle? style;

  const _ElidedPath({required this.path, this.style});

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        double widthOf(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            maxLines: 1,
            textScaler: scaler,
          )..layout();
          return painter.width;
        }

        var shown = path;
        if (widthOf(shown) > constraints.maxWidth) {
          // Both separators, because the path comes from the host filesystem
          // and a Windows path is displayed unchanged on any platform.
          final segments = path.split(RegExp(r'[/\\]'))..removeWhere((s) => s.isEmpty);
          final separator = path.contains(r'\') ? r'\' : '/';
          // Never below the last segment: past that there is nothing left to
          // shorten, and a bare "…" is worse than an overflowing name.
          for (var keep = segments.length - 1; keep >= 1; keep--) {
            final candidate = '…$separator${segments.sublist(segments.length - keep).join(separator)}';
            shown = candidate;
            if (widthOf(candidate) <= constraints.maxWidth) break;
          }
        }

        return Text(
          shown,
          maxLines: 1,
          // Still set: the final fallback is one very long segment, and it has
          // to end somewhere rather than overflow the row.
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}
