import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';

/// The `20a` feedback overlay: collects the user's critique of one generated
/// result before it is fed back into the assistant conversation.
///
/// Pure collection — it stages nothing itself. Returns the trimmed critique,
/// or null when cancelled, and the caller does the actual
/// `sendResultFeedback`; a dialog that wrote into the session on its own
/// would be a second place the feedback flow lives.
Future<String?> showResultFeedbackDialog(
  BuildContext context, {
  required AppImage image,
  required int promptVersion,
}) {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;
      return StatefulBuilder(
        builder: (context, setDialogState) => AppDialog(
          icon: Icons.chat_bubble_outline,
          title: l10n.optResultFeedbackAction,
          maxWidth: 400,
          onClose: () => Navigator.pop(context),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Image(image: image.imageProvider, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'v$promptVersion',
                            style: textTheme.labelSmall?.mono.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          image.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.mono.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  hintText: l10n.optResultFeedbackHint,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.optResultFeedbackHelper(promptVersion),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  height: AppType.looseHeight,
                ),
              ),
            ],
          ),
          actions: [
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.pop(context),
            ),
            AppButton(
              label: l10n.optSend,
              icon: Icons.send_rounded,
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, controller.text.trim()),
            ),
          ],
        ),
      );
    },
  );
}
