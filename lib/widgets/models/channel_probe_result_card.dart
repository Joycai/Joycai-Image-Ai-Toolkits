import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/llm/channel_probe_service.dart';
import '../app_button.dart';

/// The verdict of a connection test as a card (`D1b 1c`, six results): a 44
/// icon plate, a 600 title, an 11px line of detail, and — where trying again
/// can change the answer — a Retry.
///
/// Built from [ChannelProbeResult] exactly as the probe service reports it;
/// every status the service can return has a card, and the detail line is the
/// provider's own words where the service passed them on.
class ChannelProbeResultCard extends StatelessWidget {
  const ChannelProbeResultCard({
    super.key,
    required this.l10n,
    required this.result,
    this.onRetry,
  });

  final AppLocalizations l10n;
  final ChannelProbeResult result;

  /// Offered on the two failures a second attempt can fix (a rejected key
  /// once corrected, a network that comes back). Null hides it — pass null
  /// while a probe is already running.
  final VoidCallback? onRetry;

  static String _clip(String s) =>
      s.length > 160 ? '${s.substring(0, 160)}…' : s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.semantic;

    // (glyph, fill, ink, verdict, what to do next, provider's own words, retry)
    final (
      IconData icon,
      Color background,
      Color ink,
      String title,
      String next,
      String? detail,
      bool retryable,
    ) = switch (result.status) {
      ChannelProbeStatus.ok => (
          Icons.check_circle,
          semantic.successContainer,
          semantic.onSuccessContainer,
          l10n.probeOk,
          '${result.modelCount ?? 0} ${l10n.probeModels} · ${l10n.probeOkNext}',
          null,
          false,
        ),
      ChannelProbeStatus.connectedNoModels => (
          Icons.cloud_done,
          semantic.warningContainer,
          semantic.onWarningContainer,
          l10n.probeConnectedNoModels,
          l10n.probeNoModelsNext,
          null,
          false,
        ),
      ChannelProbeStatus.authFailed => (
          Icons.key_off,
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
          l10n.probeAuthFailed,
          l10n.probeAuthFailedNext,
          result.detail,
          true,
        ),
      ChannelProbeStatus.notAnApi => (
          Icons.help_outline,
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
          l10n.probeNotAnApi,
          l10n.probeNotAnApiNext,
          result.detail,
          false,
        ),
      ChannelProbeStatus.unreachable => (
          Icons.wifi_off,
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
          l10n.probeUnreachable,
          l10n.probeUnreachableNext,
          result.detail,
          true,
        ),
      ChannelProbeStatus.notSupported => (
          Icons.block,
          semantic.warningContainer,
          semantic.onWarningContainer,
          l10n.probeNotSupported,
          l10n.probeNotSupportedNext,
          null,
          false,
        ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.s10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: ink.withValues(alpha: AppAlpha.ring)),
        ),
        child: Row(
          children: [
            Container(
              width: AppSize.touch,
              height: AppSize.touch,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: AppAlpha.tint),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Icon(icon, size: 24, color: ink),
            ),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600, color: ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    next,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w400, color: ink),
                  ),
                  if (detail != null && detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _clip(detail),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.mono
                          .copyWith(fontWeight: FontWeight.w400, color: ink),
                    ),
                  ],
                ],
              ),
            ),
            if (retryable && onRetry != null) ...[
              const SizedBox(width: AppSpace.s6),
              AppButton(
                label: l10n.probeRetry,
                variant: AppButtonVariant.text,
                size: AppButtonSize.compact,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
