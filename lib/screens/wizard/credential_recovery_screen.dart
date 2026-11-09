import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/app_button.dart';

/// Bootstrap only: no AppState, live tasks or credential-dependent services exist
/// until the caller has successfully reopened the database.
class CredentialRecoveryScreen extends StatefulWidget {
  const CredentialRecoveryScreen({
    super.key,
    required this.onRetry,
    this.onReset,
    this.requiresSignedMacBuild = false,
  });
  final bool requiresSignedMacBuild;
  final Future<void> Function() onRetry;
  final Future<void> Function()? onReset;

  @override
  State<CredentialRecoveryScreen> createState() => _CredentialRecoveryScreenState();
}

class _CredentialRecoveryScreenState extends State<CredentialRecoveryScreen> {
  bool _busy = false;
  bool _confirmed = false;

  Future<void> _retry({bool reset = false}) async {
    if (_busy || (reset && !_confirmed)) return;
    setState(() => _busy = true);
    try {
      await (reset ? widget.onReset!() : widget.onRetry());
    } catch (_) {
      // Keep the recovery instructions visible; never expose native error data.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainer,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.s28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: AppSpace.s16),
                  Text(l10n.credentialRecoveryTitle, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: AppSpace.s16),
                  Text(
                    widget.requiresSignedMacBuild
                        ? l10n.credentialRecoveryDirectMacBody
                        : widget.onReset == null
                        ? l10n.credentialRecoveryBody
                        : l10n.credentialRecoveryWindowsBody,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpace.s28),
                  AppButton(label: l10n.credentialRecoveryRetry, loading: _busy, onPressed: _retry),
                  if (widget.onReset != null) ...[
                    const SizedBox(height: AppSpace.s28),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _confirmed,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _confirmed = value ?? false),
                      title: Text(l10n.credentialRecoveryResetConsent),
                    ),
                    const SizedBox(height: AppSpace.s16),
                    AppButton(
                      label: l10n.credentialRecoveryReset,
                      variant: AppButtonVariant.destructiveOutline,
                      onPressed: !_busy && _confirmed ? () => _retry(reset: true) : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
