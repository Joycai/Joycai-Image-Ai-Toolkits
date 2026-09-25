import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/db/repositories/cookie_repository.dart';
import '../../../state/app_state.dart';
import '../../../state/downloader_state.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_dialog.dart';
import '../../../widgets/ui/app_segmented_control.dart';
import 'downloader_inputs.dart';

/// Advanced options (`B3 · 1d`): filename prefix, cookies, cookie import and
/// the cookie history, which opens in place under its button rather than in a
/// sheet of its own.
Future<void> showDownloaderAdvancedDialog(
  BuildContext context, {
  required TextEditingController prefixController,
  required TextEditingController cookieController,
  required VoidCallback onImportCookie,
}) {
  final l10n = AppLocalizations.of(context)!;
  final state = Provider.of<AppState>(context, listen: false).downloaderState;

  return AppDialog.show<void>(
    context,
    icon: Icons.settings_outlined,
    title: l10n.advancedOptions,
    subtitle: l10n.downloaderAdvancedSubtitle,
    maxWidth: 520,
    maxHeight: 720,
    scrollable: true,
    content: _AdvancedOptionsBody(
      state: state,
      prefixController: prefixController,
      cookieController: cookieController,
      onImportCookie: onImportCookie,
    ),
    actions: [AppButton(label: l10n.finish, onPressed: () => Navigator.pop(context))],
  );
}

class _AdvancedOptionsBody extends StatefulWidget {
  const _AdvancedOptionsBody({
    required this.state,
    required this.prefixController,
    required this.cookieController,
    required this.onImportCookie,
  });

  final DownloaderState state;
  final TextEditingController prefixController;
  final TextEditingController cookieController;
  final VoidCallback onImportCookie;

  @override
  State<_AdvancedOptionsBody> createState() => _AdvancedOptionsBodyState();
}

class _AdvancedOptionsBodyState extends State<_AdvancedOptionsBody> {
  bool _historyOpen = false;

  void _useCookies(Map<String, dynamic> entry) {
    final cookies = '${entry['cookies'] ?? ''}';
    widget.cookieController.text = cookies;
    widget.state.setState(cookies: cookies);
    setState(() => _historyOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final caption = downloaderCaptionStyle(context);
    final prefixStyle = textTheme.bodySmall!.mono;
    final cookieStyle = textTheme.labelSmall!.mono.copyWith(fontWeight: FontWeight.w400);

    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final history = widget.state.cookieHistory;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.filenamePrefix, style: caption),
            const SizedBox(height: AppSpace.s6),
            SizedBox(
              height: AppSize.control,
              child: TextField(
                controller: widget.prefixController,
                style: prefixStyle,
                textAlignVertical: TextAlignVertical.center,
                decoration: downloaderFieldDecoration(
                  context,
                  style: prefixStyle,
                  fill: scheme.surfaceContainerLow,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s16),
            Text(l10n.cookiesHint, style: caption),
            const SizedBox(height: AppSpace.s6),
            SizedBox(
              height: 96,
              child: TextField(
                controller: widget.cookieController,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: cookieStyle,
                onChanged: (v) => widget.state.setState(cookies: v),
                decoration: downloaderFieldDecoration(
                  context,
                  style: cookieStyle,
                  fill: scheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.all(AppSpace.s10),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s10),
            Wrap(
              spacing: AppSpace.s6,
              runSpacing: AppSpace.s6,
              children: [
                DownloaderActionButton(
                  icon: Icons.upload_file,
                  label: l10n.importCookieFile,
                  fill: scheme.surfaceContainerLow,
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onImportCookie();
                  },
                ),
                DownloaderActionButton(
                  icon: Icons.history,
                  label: l10n.cookieHistory,
                  fill: scheme.surfaceContainerLow,
                  selected: _historyOpen,
                  onPressed: () => setState(() => _historyOpen = !_historyOpen),
                ),
              ],
            ),
            AnimatedSize(
              duration: AppMotion.durationOf(context, AppMotion.reveal),
              curve: AppMotion.enter,
              alignment: Alignment.topCenter,
              child: !_historyOpen
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpace.s10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CookieRetentionRow(
                            value: widget.state.cookieRetention,
                            onChanged: widget.state.setCookieRetention,
                          ),
                          const SizedBox(height: AppSpace.s10),
                          if (history.isEmpty)
                            const _EmptyCookieHistory()
                          else ...[
                            _CookieHistoryList(
                              entries: history,
                              onUse: _useCookies,
                              onForget: (entry) =>
                                  widget.state.forgetCookie('${entry['host'] ?? ''}'),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: widget.state.clearCookieHistory,
                                style: TextButton.styleFrom(foregroundColor: scheme.error),
                                child: Text(l10n.cookieHistoryClearAll),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// How long cookies are remembered (S3), with what that storage means.
class _CookieRetentionRow extends StatelessWidget {
  const _CookieRetentionRow({required this.value, required this.onChanged});

  final CookieRetention value;
  final ValueChanged<CookieRetention> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final caption = downloaderCaptionStyle(context);
    final label = <CookieRetention, String>{
      CookieRetention.off: l10n.cookieRetentionOff,
      CookieRetention.week: l10n.cookieRetentionWeek,
      CookieRetention.month: l10n.cookieRetentionMonth,
      CookieRetention.untilCleared: l10n.cookieRetentionForever,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.cookieRetention, style: caption),
        const SizedBox(height: AppSpace.s6),
        AppSegmentedControl<CookieRetention>(
          expand: true,
          compact: true,
          segments: [
            for (final r in CookieRetention.values) AppSegment(value: r, label: label[r]!),
          ],
          value: value,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpace.s4),
        Text(
          l10n.cookieRetentionNote,
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            fontWeight: FontWeight.w400,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CookieHistoryList extends StatelessWidget {
  const _CookieHistoryList({required this.entries, required this.onUse, required this.onForget});

  final List<Map<String, dynamic>> entries;
  final ValueChanged<Map<String, dynamic>> onUse;
  final ValueChanged<Map<String, dynamic>> onForget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final (i, entry) in entries.indexed) ...[
            if (i > 0) const Divider(height: 1),
            _CookieHistoryRow(
              entry: entry,
              onUse: () => onUse(entry),
              onForget: () => onForget(entry),
            ),
          ],
        ],
      ),
    );
  }
}

/// One saved host (`行 44`): glyph, mono host over when it was last used, and
/// the deep-ink action that puts its cookies back in the field.
class _CookieHistoryRow extends StatelessWidget {
  const _CookieHistoryRow({required this.entry, required this.onUse, required this.onForget});

  final Map<String, dynamic> entry;
  final VoidCallback onUse;
  final VoidCallback onForget;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String? _lastUsed(Object? raw, AppLocalizations l10n) {
    final at = DateTime.tryParse('${raw ?? ''}');
    if (at == null) return null;
    final now = DateTime.now();
    final time = '${_two(at.hour)}:${_two(at.minute)}';
    if (at.year == now.year && at.month == now.month && at.day == now.day) {
      return '${l10n.today} $time';
    }
    return '${at.year}-${_two(at.month)}-${_two(at.day)} $time';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // The row already holds the raw cookie string, so the pair count is
    // derived from it rather than stored.
    final lastUsed = _lastUsed(entry['last_used'], l10n);
    final pairs = '${entry['cookies'] ?? ''}'
        .split(';')
        .where((pair) => pair.trim().isNotEmpty)
        .length;
    final details = [?lastUsed, if (pairs > 0) l10n.cookieHistoryPairs(pairs)];
    final String? used = details.isEmpty ? null : details.join(' · ');

    return SizedBox(
      height: AppSize.touch,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 12, end: AppSpace.s6),
        child: Row(
          children: [
            Icon(Icons.cookie_outlined, size: AppSize.iconMd, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry['host'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall!.mono.copyWith(color: scheme.onSurface),
                  ),
                  if (used != null)
                    Text(
                      used,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall!.copyWith(
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            DownloaderActionButton(
              label: l10n.cookieHistoryUse,
              outlined: false,
              height: AppSize.compact,
              onPressed: onUse,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: AppSize.iconSm),
              tooltip: l10n.cookieHistoryForget,
              color: scheme.onSurfaceVariant,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: AppSize.compact,
                height: AppSize.compact,
              ),
              onPressed: onForget,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCookieHistory extends StatelessWidget {
  const _EmptyCookieHistory();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s22, horizontal: AppSpace.s16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.cookie_outlined, size: 28, color: scheme.outline),
          const SizedBox(height: AppSpace.s6),
          Text(
            l10n.noCookieHistory,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpace.s4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              l10n.cookieHistoryEmptyDesc,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
