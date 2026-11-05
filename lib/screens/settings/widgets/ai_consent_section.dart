import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/privacy/ai_consent_service.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_snackbar.dart';
import 'settings_layout.dart';

class AiConsentSection extends StatelessWidget {
  const AiConsentSection({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AiConsentService.instance;
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => SettingsBlock(
        caption: l10n.aiConsentTitle,
        child: SettingsGroup(
          ruled: false,
          children: [
            Text(l10n.aiConsentManageNote),
            if (service.recipientDecisions.isEmpty) Text(l10n.aiConsentEmpty),
            for (final decision in service.recipientDecisions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(decision.scope.recipient),
                    if (decision.scope.service != decision.scope.recipient)
                      Text(l10n.aiConsentConfiguredService(decision.scope.service)),
                    if (decision.scope.proxy.isNotEmpty)
                      Text(l10n.aiConsentProxy(decision.scope.proxy)),
                    const SizedBox(height: AppSpace.s6),
                    Wrap(
                      spacing: AppSpace.s10,
                      runSpacing: AppSpace.s6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(decision.allowed ? l10n.aiConsentAllowed : l10n.aiConsentBlocked),
                        AppButton(
                          label: decision.allowed ? l10n.aiConsentRevoke : l10n.aiConsentAskAgain,
                          variant: AppButtonVariant.secondary,
                          onPressed: () async {
                            try {
                              if (decision.allowed) {
                                await service.revoke(decision.scope);
                              } else {
                                await service.askAgain(decision.scope);
                              }
                            } catch (_) {
                              if (context.mounted) {
                                AppSnackBar.error(context, l10n.aiConsentSaveFailed);
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
