import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/glass/app_glass.dart';
import '../../widgets/glass/glass_controls.dart';
import 'settings_identity.dart';
import 'widgets/about_section.dart';
import 'widgets/appearance_section.dart';
import 'widgets/application_section.dart';
import 'widgets/connectivity_section.dart';
import 'widgets/data_section.dart';

enum SettingsCategory { appearance, connectivity, application, data, about }

/// Settings — design `E1`.
///
/// Desktop and tablet: two opaque cards on the aurora, a category card (232,
/// tablet 200) and a content card with a 56px header and the content centred
/// at up to 720. Phone: a large-title category list that pushes a page per
/// category. The only glass is the phone's header; the shell's own title bar
/// is the desktop's.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveBuilder(
      mobile: _PhoneCategoryList(),
      tablet: _TwoPaneView(),
      desktop: _TwoPaneView(),
    );
  }
}

// ── Category metadata ──────────────────────────────────────────────────────

String _categoryLabel(SettingsCategory category, AppLocalizations l10n) => switch (category) {
      SettingsCategory.appearance => l10n.appearance,
      SettingsCategory.connectivity => l10n.connectivity,
      SettingsCategory.application => l10n.application,
      SettingsCategory.data => l10n.dataManagement,
      SettingsCategory.about => l10n.about,
    };

/// The second line under a category's name — what is inside it, composed from
/// the names of the settings themselves so it is translated wherever they are.
String _categoryNote(SettingsCategory category, AppLocalizations l10n) => switch (category) {
      SettingsCategory.appearance => '${l10n.themeColor} · ${l10n.font} · ${l10n.language}',
      SettingsCategory.connectivity => '${l10n.proxySettings} · ${l10n.mcpServerSettings}',
      SettingsCategory.application => '${l10n.outputDirectory} · ${l10n.knowledgeBaseFolder}',
      SettingsCategory.data => '${l10n.exportSettings} · ${l10n.importSettings} · ${l10n.resetAllSettings}',
      SettingsCategory.about => '${l10n.aboutGithubRepo} · ${l10n.aboutLicense}',
    };

Widget _categoryContent(SettingsCategory category, {required bool phone}) => switch (category) {
      SettingsCategory.appearance => const AppearanceSection(),
      SettingsCategory.connectivity => ConnectivitySection(isMobile: phone),
      SettingsCategory.application => const ApplicationSection(),
      SettingsCategory.data => DataSection(isMobile: phone),
      SettingsCategory.about => const AboutSection(),
    };

/// The app's version, once the platform reports it, handed to [builder].
class _VersionText extends StatefulWidget {
  const _VersionText({required this.builder, this.textAlign});

  final String Function(String version) builder;
  final TextAlign? textAlign;

  @override
  State<_VersionText> createState() => _VersionTextState();
}

class _VersionTextState extends State<_VersionText> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      _version.isEmpty ? '' : widget.builder(_version),
      textAlign: widget.textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
            fontWeight: FontWeight.w400,
            color: colorScheme.outline,
          ),
    );
  }
}

// ── Desktop / tablet: category card + content card ─────────────────────────

class _TwoPaneView extends StatefulWidget {
  const _TwoPaneView();

  @override
  State<_TwoPaneView> createState() => _TwoPaneViewState();
}

class _TwoPaneViewState extends State<_TwoPaneView> {
  // Transient UI state: which category is shown in the content card.
  SettingsCategory _selected = SettingsCategory.appearance;

  @override
  Widget build(BuildContext context) {
    final bool desktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        // `E1` 「尺寸」: 16/20 around the cards on a desktop, 12/14 on a tablet.
        padding: desktop
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: AppSpace.s16)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: desktop ? 232 : 200,
              child: _Card(child: _buildNav(context, desktop: desktop)),
            ),
            SizedBox(width: desktop ? AppSpace.s16 : 12),
            Expanded(child: _Card(child: _buildContent(context, desktop: desktop))),
          ],
        ),
      ),
    );
  }

  Widget _buildNav(BuildContext context, {required bool desktop}) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 56,
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: desktop ? AppSpace.s16 : 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Text(
            l10n.settings,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final category in SettingsCategory.values)
                _NavRow(
                  category: category,
                  selected: category == _selected,
                  compact: !desktop,
                  onTap: () => setState(() => _selected = category),
                ),
            ],
          ),
        ),
        if (desktop)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: _VersionText(builder: (v) => 'v$v · MIT'),
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, {required bool desktop}) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: desktop ? 24 : 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              SettingsIdentityPlate(category: _selected, size: 28, radius: AppRadius.sm),
              const SizedBox(width: AppSpace.s10),
              Expanded(
                child: Text(
                  _categoryLabel(_selected, l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey(_selected),
            padding: desktop
                ? const EdgeInsets.symmetric(horizontal: 28, vertical: 24)
                : const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _categoryContent(_selected, phone: false),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An opaque panel card at r16 with a hairline — both cards of the two-pane
/// layout.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A category in the nav card — `1a`: 52 tall with a 32px plate and the note
/// under the name; `1c` (tablet): 48 with a 28px plate and the name alone.
/// Selected: the accent wash, a 1px accent edge, the name in the deep accent.
class _NavRow extends StatefulWidget {
  const _NavRow({
    required this.category,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final SettingsCategory category;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bool selected = widget.selected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hovered = v),
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            curve: AppMotion.quick,
            height: widget.compact ? 48 : 52,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.accentTint
                  : _hovered
                      ? colorScheme.surfaceContainerLow
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: selected ? colorScheme.primary : Colors.transparent),
            ),
            child: Row(
              children: [
                SettingsIdentityPlate(
                  category: widget.category,
                  size: widget.compact ? 28 : 32,
                  radius: AppRadius.sm,
                ),
                const SizedBox(width: AppSpace.s10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _categoryLabel(widget.category, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? colorScheme.onAccentTint : colorScheme.onSurface,
                        ),
                      ),
                      if (!widget.compact)
                        Text(
                          _categoryNote(widget.category, l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Phone: large-title list → detail page ──────────────────────────────────

/// The height of the phone headers' own band, under whatever the status bar
/// takes — `1e`: 76 for the large title, 56 for a detail page.
const double _largeTitleBand = 76;
const double _detailBand = 56;

class _PhoneCategoryList extends StatelessWidget {
  const _PhoneCategoryList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final padding = MediaQuery.paddingOf(context);
    final double header = padding.top + _largeTitleBand;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              // The dock's clearance arrives as the bottom padding.
              padding: EdgeInsets.fromLTRB(12, header + 12, 12, padding.bottom + 12),
              children: [
                for (final category in SettingsCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PhoneCategoryRow(
                      category: category,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => _PhoneDetailPage(category: category)),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: _VersionText(
                    textAlign: TextAlign.center,
                    builder: (v) => '${l10n.appTitle} · v$v',
                  ),
                ),
              ],
            ),
          ),
          // 玻璃一: the screen's one full-width glass, over the list.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AppGlass(
              grade: GlassGrade.bar,
              edges: GlassEdges.bottom,
              shadow: false,
              child: SizedBox(
                height: header,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(AppSpace.s16, padding.top, AppSpace.s16, 14),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      l10n.settings,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineLarge?.metricsOnly,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `1e` left: a 64px panel row — a 36px plate, the name and what is inside it,
/// and a chevron.
class _PhoneCategoryRow extends StatelessWidget {
  const _PhoneCategoryRow({required this.category, required this.onTap});

  final SettingsCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                SettingsIdentityPlate(
                  category: category,
                  size: 36,
                  radius: AppRadius.control,
                  iconSize: AppSize.iconLg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _categoryLabel(category, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium,
                      ),
                      Text(
                        _categoryNote(category, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: AppSize.iconMd, color: colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `1e` middle: a category's page, under a glass header with back and the
/// category's name.
class _PhoneDetailPage extends StatelessWidget {
  const _PhoneDetailPage({required this.category});

  final SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final padding = MediaQuery.paddingOf(context);
    final double header = padding.top + _detailBand;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(12, header + 14, 12, padding.bottom + 24),
              child: _categoryContent(category, phone: true),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AppGlass(
              grade: GlassGrade.bar,
              edges: GlassEdges.bottom,
              shadow: false,
              child: SizedBox(
                height: header,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(6, padding.top, AppSpace.s16, 0),
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: Icons.arrow_back,
                        tooltip: l10n.back,
                        size: AppSize.large,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: AppSpace.s6),
                      Expanded(
                        child: Text(
                          _categoryLabel(category, l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.metricsOnly,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
