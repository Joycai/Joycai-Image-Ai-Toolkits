import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_section.dart';
import '../../../widgets/app_setting_row.dart';

const String _githubUrl = 'https://github.com/Joycai/Joycai-Image-Ai-Toolkits';
const String _copyrightHolder = 'BigBaicai';

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

    // No title — the pane header already says 「关于」.
    return AppSection(
      gap: 10,
      children: [
        // Full width, or the Column shrink-wraps to its widest text and the
        // whole block lands at the pane's left edge (AppSection aligns its
        // children to the start) — the icon then only looks centred relative
        // to the title, not the pane.
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/icon/icon.png', width: 72, height: 72),
              ),
            const SizedBox(height: 12),
            Text(
              l10n.appTitle,
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              _version.isEmpty ? '' : l10n.aboutVersion(_version),
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // `D1`'s rows carry no leading glyph. Dropped rather than kept: a
        // code bracket beside 「GitHub 仓库」 and a gavel beside 「许可证」 were
        // restating the words next to them.
        AppSettingRow(
          title: l10n.aboutGithubRepo,
          description: l10n.aboutViewSource,
          trailing: Icon(Icons.open_in_new,
              size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
          onTap: () => FileUtils.openUri(Uri.parse(_githubUrl)),
        ),
        AppSettingRow(
          title: l10n.aboutLicense,
          description: 'MIT License',
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            l10n.aboutCopyright(DateTime.now().year, _copyrightHolder),
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
