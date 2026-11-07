import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/file_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../services/llm/vendors/platforms.dart';
import '../../services/privacy/ai_consent_service.dart';
import '../models/route_labels.dart';
import '../ui/app_button.dart';
import '../ui/app_dialog.dart';

const aiPrivacyPolicyUrl =
    'https://github.com/Joycai/Joycai-Image-Ai-Toolkits/blob/main/PRIVACY_POLICY.md';

class AiConsentDialog extends StatelessWidget {
  final AiConsentScope scope;
  const AiConsentDialog({super.key, required this.scope});

  static Future<bool?> show(BuildContext context, AiConsentScope scope) => showDialog<bool>(
    context: context,
    animationStyle: appDialogAnimation(context),
    builder: (_) => AiConsentDialog(scope: scope),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Identify official providers by the actual recipient host, never by the
    // selected model/vendor label (a custom relay may use any protocol).
    final host = Uri.parse(scope.recipient).host;
    final platform = Platforms.all.where((p) => p.matchesHost(host)).firstOrNull;
    return AppDialog(
      title: l10n.aiConsentTitle,
      icon: Icons.privacy_tip_outlined,
      maxHeight: MediaQuery.sizeOf(context).height * .9,
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.aiConsentRecipient, style: Theme.of(context).textTheme.titleSmall),
          Text(platform == null ? l10n.platformCustom : platformLabel(l10n, platform)),
          SelectableText(scope.recipient),
          if (scope.service != scope.recipient) ...[
            const SizedBox(height: AppSpace.s10),
            Text(l10n.aiConsentConfiguredService(scope.service)),
          ],
          if (scope.proxy.isNotEmpty) ...[
            const SizedBox(height: AppSpace.s10),
            Text(l10n.aiConsentProxy(scope.proxy)),
          ],
          const SizedBox(height: AppSpace.s16),
          Text(l10n.aiConsentData),
          const SizedBox(height: AppSpace.s10),
          Text(l10n.aiConsentPurpose),
          const SizedBox(height: AppSpace.s10),
          Text(l10n.aiConsentConsequences),
          const SizedBox(height: AppSpace.s10),
          AppButton(
            label: l10n.aboutPrivacyPolicy,
            icon: Icons.open_in_new,
            variant: AppButtonVariant.text,
            onPressed: () => FileUtils.openUri(Uri.parse(aiPrivacyPolicyUrl)),
          ),
        ],
      ),
      actionsOverride: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: AppSpace.s10,
          runSpacing: AppSpace.s10,
          alignment: WrapAlignment.end,
          children: [
            AppButton(
              label: l10n.aiConsentDecline,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.large,
              onPressed: () => Navigator.pop(context, false),
            ),
            AppButton(
              label: l10n.aiConsentAllow,
              size: AppButtonSize.large,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
  }
}
