import 'package:flutter/material.dart';

/// The app's dialog chrome: rounded [Dialog] surface, title in
/// [TextTheme.titleLarge], right-aligned action row.
///
/// Every dialog in `lib/widgets/dialogs/` and `lib/widgets/models/` currently
/// hand-builds this — its own padding, its own corner radius, its own title
/// [TextStyle] — so no two dialogs in the app match exactly. This is the
/// shared shell they should build on instead.
///
/// Use [AppDialog.show] for the common title/content/actions shape. For a
/// dialog that needs full control over its body (a full-screen editor
/// pop-out, for instance) construct [AppDialog] directly inside your own
/// `showDialog`/`showGeneralDialog` call and pass whatever `content` you
/// need — the chrome still applies, but nothing about the shape is assumed.
class AppDialog extends StatelessWidget {
  final String? title;
  final Widget content;
  final List<Widget>? actions;

  /// Caps how wide the dialog grows on desktop; it still shrinks to fit
  /// smaller viewports.
  final double maxWidth;

  const AppDialog({
    super.key,
    this.title,
    required this.content,
    this.actions,
    this.maxWidth = 480,
  });

  /// Shows an [AppDialog] and returns whatever the caller pops with
  /// `Navigator.pop(context, result)`.
  static Future<T?> show<T>(
    BuildContext context, {
    String? title,
    required Widget content,
    List<Widget>? actions,
    double maxWidth = 480,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => AppDialog(title: title, content: content, actions: actions, maxWidth: maxWidth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      // A tone above the canvas, same family PanelCard draws its surface
      // from, so a dialog reads as one more surface in the app rather than
      // Material's own stock white/near-black sheet.
      backgroundColor: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(title!, style: textTheme.titleLarge),
                const SizedBox(height: 16),
              ],
              Flexible(child: content),
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions![i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
