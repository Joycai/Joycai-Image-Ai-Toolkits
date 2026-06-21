import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import 'widgets/appearance_section.dart';
import 'widgets/application_section.dart';
import 'widgets/connectivity_section.dart';
import 'widgets/data_section.dart';

enum SettingsCategory { appearance, connectivity, application, data }

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ResponsiveBuilder(
      mobile: _SettingsMobileView(l10n: l10n),
      tablet: _SettingsSingleColumnView(l10n: l10n),
      desktop: _SettingsSingleColumnView(l10n: l10n),
    );
  }
}

// ── Mobile: list → push to detail ──────────────────────────────────────────

class _SettingsMobileView extends StatelessWidget {
  final AppLocalizations l10n;
  const _SettingsMobileView({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(l10n.settings)),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildCategoryTile(context, SettingsCategory.appearance, Icons.palette_outlined, l10n.appearance, Colors.blue),
              _buildCategoryTile(context, SettingsCategory.connectivity, Icons.lan_outlined, l10n.connectivity, Colors.green),
              _buildCategoryTile(context, SettingsCategory.application, Icons.settings_applications_outlined, l10n.application, Colors.orange),
              _buildCategoryTile(context, SettingsCategory.data, Icons.storage_outlined, l10n.dataManagement, Colors.purple),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(BuildContext context, SettingsCategory category, IconData icon, String label, Color color) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, size: 16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _SettingsDetailPage(category: category, label: label, l10n: l10n),
          ),
        );
      },
    );
  }
}

class _SettingsDetailPage extends StatelessWidget {
  final SettingsCategory category;
  final String label;
  final AppLocalizations l10n;

  const _SettingsDetailPage({required this.category, required this.label, required this.l10n});

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (category) {
      case SettingsCategory.appearance:
        content = const AppearanceSection();
      case SettingsCategory.connectivity:
        content = const ConnectivitySection(isMobile: true);
      case SettingsCategory.application:
        content = const ApplicationSection();
      case SettingsCategory.data:
        content = const DataSection(isMobile: true);
    }

    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }
}

// ── Desktop / Tablet: 60px header + single scrollable column ───────────────

class _SettingsSingleColumnView extends StatelessWidget {
  final AppLocalizations l10n;
  const _SettingsSingleColumnView({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 60px screen header
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
          ),
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 24, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                l10n.settings,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
        ),
        // Scrollable sections
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionBlock(
                      icon: Icons.palette_outlined,
                      title: l10n.appearance,
                      color: Colors.blue,
                      child: const AppearanceSection(),
                    ),
                    const SizedBox(height: 32),
                    _SectionBlock(
                      icon: Icons.lan_outlined,
                      title: l10n.connectivity,
                      color: Colors.green,
                      child: const ConnectivitySection(),
                    ),
                    const SizedBox(height: 32),
                    _SectionBlock(
                      icon: Icons.settings_applications_outlined,
                      title: l10n.application,
                      color: Colors.orange,
                      child: const ApplicationSection(),
                    ),
                    const SizedBox(height: 32),
                    _SectionBlock(
                      icon: Icons.storage_outlined,
                      title: l10n.dataManagement,
                      color: Colors.purple,
                      child: const DataSection(),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Widget child;

  const _SectionBlock({
    required this.icon,
    required this.title,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 11),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}
