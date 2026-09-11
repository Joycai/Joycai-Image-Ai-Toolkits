import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import 'settings_layout.dart';

const String _githubUrl = 'https://github.com/Joycai/Joycai-Image-Ai-Toolkits';
const String _licenseUrl = '$_githubUrl/blob/main/LICENSE';
const String _copyrightHolder = 'BigBaicai';

/// `E1 · 1d` 「关于」: one column-coloured card — the app's icon, its name and
/// version, the repository and licence as two compact buttons — and the
/// copyright line under it.
class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Widget buttons = Wrap(
      spacing: AppSpace.s6,
      runSpacing: AppSpace.s6,
      children: [
        Tooltip(
          message: '${l10n.aboutGithubRepo} · ${l10n.aboutViewSource}',
          child: AppButton(
            // A brand name, like the font names: not translated.
            label: 'GitHub',
            icon: Icons.code,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.compact,
            accentLabel: true,
            onPressed: () => FileUtils.openUri(Uri.parse(_githubUrl)),
          ),
        ),
        Tooltip(
          message: 'MIT License',
          child: AppButton(
            label: l10n.aboutLicense,
            icon: Icons.description_outlined,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.compact,
            accentLabel: true,
            onPressed: () => FileUtils.openUri(Uri.parse(_licenseUrl)),
          ),
        ),
      ],
    );

    final Widget identity = Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Image.asset('assets/icon/icon.png', width: 44, height: 44),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.appTitle,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                _version.isEmpty ? '' : l10n.aboutVersion(_version),
                style: textTheme.labelSmall?.mono.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return SettingsSections(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              // The buttons sit beside the name where there is room for both
              // at their natural widths, and under it where there is not.
              child: LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth >= 420) {
                  return Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 12),
                      buttons,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [identity, const SizedBox(height: 12), buttons],
                );
              }),
            ),
            const SizedBox(height: AppSpace.s10),
            Text(
              l10n.aboutCopyright(DateTime.now().year, _copyrightHolder),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: AppType.proseHeight,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
