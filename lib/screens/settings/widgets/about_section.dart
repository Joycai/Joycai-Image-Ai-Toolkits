import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/runtime_info.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_section_label.dart';
import '../../../widgets/app_setting_row.dart';
import '../../../widgets/app_snackbar.dart';
import 'settings_layout.dart';

const String _githubUrl = 'https://github.com/Joycai/Joycai-Image-Ai-Toolkits';
const String _licenseUrl = '$_githubUrl/blob/main/LICENSE';
const String _releasesUrl = '$_githubUrl/releases';
const String _issuesUrl = '$_githubUrl/issues/new';
const String _copyrightHolder = 'BigBaicai';

/// `E1 · 2a` 「关于」 as a category page of its own: the identity block, the
/// five links, the runtime block a bug report is pasted from, and the notices.
///
/// The design's 「检查更新」 — the button on the identity block, the status line
/// under the version, and the 「发现新版本」 dialog of `2b` — is deliberately
/// absent: nothing in the app talks to a release feed yet, and a button that
/// only ever answers 「已是最新版本」 would be lying. The 更新日志 link is what
/// answers "is there a newer one" until then.
class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  RuntimeInfo? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await RuntimeInfo.load();
    if (mounted) setState(() => _info = info);
  }

  Future<void> _copyRuntime() async {
    final info = _info;
    if (info == null) return;
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: info.report));
    if (mounted) AppSnackBar.success(context, l10n.aboutRuntimeCopied);
  }

  void _open(String url) => FileUtils.openUri(Uri.parse(url));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SettingsSections(
      children: [
        _Identity(info: _info),
        _links(context, l10n),
        _runtime(context, l10n),
        _notices(context, l10n),
      ],
    );
  }

  /// The five rows: four that leave the app, and the third-party licences,
  /// which Flutter draws in a page of its own.
  Widget _links(BuildContext context, AppLocalizations l10n) {
    return SettingsGroup(
      children: [
        _LinkRow(
          icon: Icons.code,
          // A brand name, like the font names: not translated.
          title: 'GitHub',
          note: l10n.aboutViewSource,
          action: l10n.aboutActionOpen,
          external: true,
          onTap: () => _open(_githubUrl),
        ),
        _LinkRow(
          icon: Icons.history,
          title: l10n.aboutChangelog,
          note: l10n.aboutChangelogNote,
          action: l10n.aboutActionOpen,
          external: true,
          onTap: () => _open(_releasesUrl),
        ),
        _LinkRow(
          icon: Icons.description_outlined,
          title: l10n.aboutLicense,
          // The licence's name, not a sentence about it.
          note: 'MIT License',
          action: l10n.aboutActionOpen,
          external: true,
          onTap: () => _open(_licenseUrl),
        ),
        _LinkRow(
          icon: Icons.inventory_2_outlined,
          title: l10n.aboutThirdParty,
          note: l10n.aboutThirdPartyNote,
          action: l10n.aboutActionView,
          external: false,
          onTap: () => showLicensePage(
            context: context,
            applicationName: l10n.appTitle,
            applicationVersion: _info?.versionLine ?? '',
            applicationLegalese:
                l10n.aboutCopyright(DateTime.now().year, _copyrightHolder),
          ),
        ),
        _LinkRow(
          icon: Icons.bug_report_outlined,
          title: l10n.aboutFeedback,
          note: l10n.aboutFeedbackNote,
          action: l10n.aboutActionOpen,
          external: true,
          onTap: () => _open(_issuesUrl),
        ),
      ],
    );
  }

  /// 「运行信息」: the four lines nobody can read off the screen, and the button
  /// that puts them on the clipboard as one block.
  Widget _runtime(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final info = _info;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionLabel(
          l10n.aboutRuntime,
          padding: EdgeInsets.zero,
          trailing: AppButton(
            label: l10n.copy,
            icon: Icons.content_copy,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.compact,
            accentLabel: true,
            onPressed: info == null ? null : _copyRuntime,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.aboutRuntimeHint,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w400,
            color: theme.colorScheme.onSurfaceVariant,
            height: AppType.proseHeight,
          ),
        ),
        const SizedBox(height: AppSpace.s10),
        _RuntimeTable(info: info),
      ],
    );
  }

  /// The copyright, and what this app is not: it carries no weights, so what
  /// comes out of a channel is that channel's terms to answer for.
  Widget _notices(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w400,
      color: theme.colorScheme.onSurfaceVariant,
      height: AppType.proseHeight,
    );

    return Container(
      padding: const EdgeInsets.only(top: AppSpace.s16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.aboutCopyright(DateTime.now().year, _copyrightHolder), style: style),
          const SizedBox(height: 2),
          Text(l10n.aboutModelNotice, style: style),
        ],
      ),
    );
  }
}

/// The 64 icon, the name at 20/600, and the version in mono under it.
///
/// Centred in a column on a phone (`2b`), in a row everywhere else (`2a`).
class _Identity extends StatelessWidget {
  const _Identity({required this.info});

  final RuntimeInfo? info;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bool phone = Responsive.isMobile(context);

    final Widget icon = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Image.asset('assets/icon/icon.png', width: 64, height: 64),
    );
    final Widget name = Text(
      l10n.appTitle,
      style: theme.textTheme.headlineSmall,
      textAlign: phone ? TextAlign.center : TextAlign.start,
    );
    // Blank until the platform answers, rather than a placeholder version:
    // a wrong build number in a bug report is worse than a missing one.
    final Widget version = Text(
      info == null ? '' : l10n.aboutVersionBuild(info!.version, info!.buildNumber),
      style: theme.textTheme.bodySmall?.mono.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    if (phone) {
      return Column(
        children: [
          icon,
          const SizedBox(height: AppSpace.s10),
          name,
          const SizedBox(height: AppSpace.s4),
          version,
        ],
      );
    }

    return Row(
      children: [
        icon,
        const SizedBox(width: AppSpace.s16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [name, const SizedBox(height: AppSpace.s4), version],
          ),
        ),
      ],
    );
  }
}

/// One About link: its glyph on a plate, what it is, and the button that
/// opens it. The whole row is the target — the button says where it goes.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.note,
    required this.action,
    required this.external,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String note;
  final String action;

  /// Whether the link leaves the app, which is what the glyph on the button
  /// says. The third-party licences are a page of this app's own.
  final bool external;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppSettingRow(
      framed: false,
      title: title,
      description: note,
      onTap: onTap,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(icon, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
      ),
      trailing: AppButton(
        label: action,
        icon: external ? Icons.open_in_new : Icons.chevron_right,
        variant: AppButtonVariant.secondary,
        size: AppButtonSize.compact,
        accentLabel: true,
        onPressed: onTap,
      ),
    );
  }
}

/// The runtime lines as a mono two-column block on the column colour.
class _RuntimeTable extends StatelessWidget {
  const _RuntimeTable({required this.info});

  final RuntimeInfo? info;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final TextStyle? mono = theme.textTheme.bodySmall?.mono;

    final rows = <(String, String)>[
      (l10n.aboutMetaVersion, info?.versionLine ?? ''),
      (l10n.aboutMetaEngine, info?.engine ?? ''),
      (l10n.aboutMetaPlatform, info?.platform ?? ''),
      (l10n.aboutMetaDataDir, info?.dataDirectory ?? ''),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (final (String label, String value) in rows)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.s16, bottom: AppSpace.s6),
                  child: Text(label, style: mono?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.s6),
                  child: Text(
                    value,
                    style: mono,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
