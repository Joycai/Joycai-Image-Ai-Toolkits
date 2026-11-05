import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_snackbar.dart';
import 'settings_layout.dart';

/// User-composed reports only: never attach prompts, credentials or media.
class ContentSafetySection extends StatelessWidget {
  const ContentSafetySection({super.key});

  static const email = 'joycai@joycai.cn';

  Future<void> _email(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    var opened = false;
    try {
      opened = await launchUrl(Uri(scheme: 'mailto', path: email));
    } catch (_) {
      // The address and copy action remain available without a mail handler.
    }
    if (!opened && context.mounted) AppSnackBar.error(context, l10n.contentSafetyEmailFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsBlock(
      caption: l10n.contentSafetyReport,
      child: SettingsGroup(
        ruled: false,
        children: [
          Text(l10n.contentSafetyReportNote),
          const SelectableText(email),
          Wrap(
            spacing: AppSpace.s10,
            runSpacing: AppSpace.s10,
            children: [
              AppButton(
                label: l10n.contentSafetyEmail,
                icon: Icons.mail_outline,
                variant: AppButtonVariant.secondary,
                onPressed: () => _email(context),
              ),
              AppButton(
                label: l10n.contentSafetyCopyEmail,
                icon: Icons.copy,
                variant: AppButtonVariant.secondary,
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(text: email));
                  if (context.mounted) AppSnackBar.success(context, l10n.contentSafetyEmailCopied);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
