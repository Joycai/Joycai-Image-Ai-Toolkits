import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_section.dart';

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

    return AppSection(
      title: l10n.about,
      children: [
        Column(
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
        const SizedBox(height: 24),
        ListTile(
          title: Text(l10n.aboutGithubRepo),
          subtitle: Text(l10n.aboutViewSource),
          shape: RoundedRectangleBorder(side: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHigh), borderRadius: BorderRadius.circular(AppRadius.md)),
          leading: const Icon(Icons.code),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => FileUtils.openUri(Uri.parse(_githubUrl)),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: Text(l10n.aboutLicense),
          subtitle: const Text('MIT License'),
          shape: RoundedRectangleBorder(side: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHigh), borderRadius: BorderRadius.circular(AppRadius.md)),
          leading: const Icon(Icons.gavel_outlined),
        ),
        const SizedBox(height: 24),
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
