import 'package:flutter/material.dart';

import 'settings_screen.dart';

/// The glyph and plate colours of each settings category — `E1` 「分类图标块」.
///
/// Identity, not meaning and not the accent: 外观 violet · 连接 blue · 应用
/// green · 数据管理 amber · 关于 neutral, in both brightnesses, whatever the
/// theme colour. The blue, green and amber pairs are the semantic info /
/// success / warning values of `00 · 1b`, copied rather than read from
/// `AppSemanticColors` on purpose: if success turns a different green for a
/// *meaning* reason, the 应用 plate must not follow it. The violet is the
/// DeepPurple preset's pair over the panel at 18%, for the same reason
/// frozen here rather than read from the preset.
///
/// 关于 is the neutral ramp, which never follows the accent either.
@immutable
class SettingsIdentity {
  const SettingsIdentity({required this.icon, required this.plate, required this.ink});

  final IconData icon;

  /// The opaque plate behind the glyph.
  final Color plate;

  /// The glyph.
  final Color ink;

  static SettingsIdentity of(SettingsCategory category, ColorScheme scheme) {
    final bool dark = scheme.brightness == Brightness.dark;
    return switch (category) {
      SettingsCategory.appearance => SettingsIdentity(
          icon: Icons.palette_outlined,
          plate: dark ? const Color(0xFF383045) : const Color(0xFFECE4FA),
          ink: dark ? const Color(0xFFA97DFF) : const Color(0xFF7A4ECB),
        ),
      SettingsCategory.connectivity => SettingsIdentity(
          icon: Icons.lan_outlined,
          plate: dark ? const Color(0xFF1B3350) : const Color(0xFFDDEAF8),
          ink: dark ? const Color(0xFF6AA7E8) : const Color(0xFF2F6FB0),
        ),
      SettingsCategory.application => SettingsIdentity(
          icon: Icons.tune,
          plate: dark ? const Color(0xFF173A24) : const Color(0xFFDDF2E3),
          ink: dark ? const Color(0xFF4FB86F) : const Color(0xFF1F7A3E),
        ),
      SettingsCategory.data => SettingsIdentity(
          icon: Icons.storage_outlined,
          plate: dark ? const Color(0xFF3F2C10) : const Color(0xFFFBEBD0),
          ink: dark ? const Color(0xFFE5A040) : const Color(0xFFA1620A),
        ),
      SettingsCategory.about => SettingsIdentity(
          icon: Icons.info_outline,
          plate: scheme.surfaceContainer,
          ink: scheme.onSurfaceVariant,
        ),
    };
  }
}

/// A category's glyph on its plate, at [size] with radius [radius].
class SettingsIdentityPlate extends StatelessWidget {
  const SettingsIdentityPlate({
    super.key,
    required this.category,
    required this.size,
    required this.radius,
    this.iconSize = 16,
  });

  final SettingsCategory category;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final identity = SettingsIdentity.of(category, Theme.of(context).colorScheme);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: identity.plate,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(identity.icon, size: iconSize, color: identity.ink),
    );
  }
}
