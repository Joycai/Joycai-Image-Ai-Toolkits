import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import 'widgets/appearance_section.dart';
import 'widgets/application_section.dart';
import 'widgets/connectivity_section.dart';
import 'widgets/data_section.dart';

enum SettingsCategory { appearance, connectivity, application, data }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsCategory _selectedCategory = SettingsCategory.appearance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ResponsiveBuilder(
      mobile: _SettingsMobileView(l10n: l10n),
      tablet: _SettingsSplitView(
        l10n: l10n,
        selectedCategory: _selectedCategory,
        onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
        isTablet: true,
      ),
      desktop: _SettingsSplitView(
        l10n: l10n,
        selectedCategory: _selectedCategory,
        onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
        isTablet: false,
      ),
    );
  }
}

class _SettingsMobileView extends StatelessWidget {
  final AppLocalizations l10n;
  const _SettingsMobileView({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(l10n.settings),
          ),
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
      case SettingsCategory.appearance: content = const AppearanceSection(); break;
      case SettingsCategory.connectivity: content = const ConnectivitySection(isMobile: true); break;
      case SettingsCategory.application: content = const ApplicationSection(); break;
      case SettingsCategory.data: content = const DataSection(isMobile: true); break;
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

class _SettingsSplitView extends StatelessWidget {
  final AppLocalizations l10n;
  final SettingsCategory selectedCategory;
  final Function(SettingsCategory) onCategoryChanged;
  final bool isTablet;

  const _SettingsSplitView({
    required this.l10n,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar (Master)
          Container(
            width: isTablet ? 280 : 320,
            color: colorScheme.surfaceContainerLow,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: Text(l10n.settings),
                  floating: true,
                  backgroundColor: Colors.transparent,
                ),
                SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),
                    _buildSidebarTile(SettingsCategory.appearance, Icons.palette_outlined, l10n.appearance, Colors.blue),
                    _buildSidebarTile(SettingsCategory.connectivity, Icons.lan_outlined, l10n.connectivity, Colors.green),
                    _buildSidebarTile(SettingsCategory.application, Icons.settings_applications_outlined, l10n.application, Colors.orange),
                    _buildSidebarTile(SettingsCategory.data, Icons.storage_outlined, l10n.dataManagement, Colors.purple),
                  ]),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Content (Detail)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildDetailContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTile(SettingsCategory category, IconData icon, String label, Color color) {
    final isSelected = selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        selected: isSelected,
        leading: Icon(icon, size: 20, color: isSelected ? null : color),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedTileColor: color.withAlpha(40),
        onTap: () => onCategoryChanged(category),
      ),
    );
  }

  Widget _buildDetailContent(BuildContext context) {
    Widget section;
    switch (selectedCategory) {
      case SettingsCategory.appearance: section = const AppearanceSection(); break;
      case SettingsCategory.connectivity: section = const ConnectivitySection(); break;
      case SettingsCategory.application: section = const ApplicationSection(); break;
      case SettingsCategory.data: section = const DataSection(); break;
    }

    return SingleChildScrollView(
      key: ValueKey(selectedCategory),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: section,
        ),
      ),
    );
  }
}
