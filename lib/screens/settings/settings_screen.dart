import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/panel_resizer.dart';
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
      tablet: _SettingsTwoPaneView(l10n: l10n),
      desktop: _SettingsTwoPaneView(l10n: l10n),
    );
  }
}

// ── Shared category metadata (icons/colors match the mobile list) ──────────

IconData _categoryIcon(SettingsCategory category) {
  switch (category) {
    case SettingsCategory.appearance:
      return Icons.palette_outlined;
    case SettingsCategory.connectivity:
      return Icons.lan_outlined;
    case SettingsCategory.application:
      return Icons.settings_applications_outlined;
    case SettingsCategory.data:
      return Icons.storage_outlined;
  }
}

Color _categoryColor(SettingsCategory category) {
  switch (category) {
    case SettingsCategory.appearance:
      return Colors.blue;
    case SettingsCategory.connectivity:
      return Colors.green;
    case SettingsCategory.application:
      return Colors.orange;
    case SettingsCategory.data:
      return Colors.purple;
  }
}

String _categoryLabel(SettingsCategory category, AppLocalizations l10n) {
  switch (category) {
    case SettingsCategory.appearance:
      return l10n.appearance;
    case SettingsCategory.connectivity:
      return l10n.connectivity;
    case SettingsCategory.application:
      return l10n.application;
    case SettingsCategory.data:
      return l10n.dataManagement;
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

// ── Desktop / Tablet: inset-panel canvas with nav card + content card ───────

class _SettingsTwoPaneView extends StatefulWidget {
  final AppLocalizations l10n;
  const _SettingsTwoPaneView({required this.l10n});

  @override
  State<_SettingsTwoPaneView> createState() => _SettingsTwoPaneViewState();
}

class _SettingsTwoPaneViewState extends State<_SettingsTwoPaneView> {
  // Transient UI state: which category is shown in the content card.
  SettingsCategory _selected = SettingsCategory.appearance;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final navWidth = Responsive.isNarrow(context) ? 200.0 : 232.0;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            PanelCard(
              width: navWidth,
              child: _buildNavPane(colorScheme),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PanelCard(
                child: _buildContentPane(colorScheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavPane(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Screen title header, aligned with the content card's header row.
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
          ),
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 22, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                widget.l10n.settings,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: SettingsCategory.values
                .map((category) => _buildNavTile(category, colorScheme))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildNavTile(SettingsCategory category, ColorScheme colorScheme) {
    final isSelected = category == _selected;
    final color = _categoryColor(category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedTileColor: colorScheme.primaryContainer.withAlpha(90),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_categoryIcon(category), color: color, size: 18),
        ),
        title: Text(
          _categoryLabel(category, widget.l10n),
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? colorScheme.primary : null,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => setState(() => _selected = category),
      ),
    );
  }

  Widget _buildContentPane(ColorScheme colorScheme) {
    Widget content;
    switch (_selected) {
      case SettingsCategory.appearance:
        content = const AppearanceSection();
      case SettingsCategory.connectivity:
        content = const ConnectivitySection();
      case SettingsCategory.application:
        content = const ApplicationSection();
      case SettingsCategory.data:
        content = const DataSection();
    }

    return Column(
      children: [
        // Category title as an in-card header row.
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
          ),
          child: Row(
            children: [
              Icon(_categoryIcon(_selected), size: 22, color: _categoryColor(_selected)),
              const SizedBox(width: 10),
              Text(
                _categoryLabel(_selected, widget.l10n),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey(_selected),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: content,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
