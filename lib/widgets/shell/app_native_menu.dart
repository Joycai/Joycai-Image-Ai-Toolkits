import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_shortcuts.dart';
import '../../l10n/app_localizations.dart';
import '../../services/system/native_menu_service.dart';
import 'app_destinations.dart';
import 'native_menu_labels.dart';

/// Synchronizes the native menu without introducing a layout or focus boundary.
/// The owning route supplies actions; no screen or application state is imported.
class AppNativeMenu extends StatefulWidget {
  const AppNativeMenu({
    super.key,
    required this.onNavigate,
    required this.onShortcuts,
    required this.child,
  });

  final ValueChanged<int> onNavigate;
  final VoidCallback onShortcuts;
  final Widget child;

  @override
  State<AppNativeMenu> createState() => _AppNativeMenuState();
}

class _AppNativeMenuState extends State<AppNativeMenu> {
  late final _service = NativeMenuService(onCommand: _onCommand);

  void _onCommand(String command) {
    // Recheck at dispatch time: an OS menu can have been opened before a dialog.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (command == AppShortcutIds.openSettings) {
      widget.onNavigate(AppDestination.settings.index);
    } else if (command == AppShortcutIds.showShortcutPanel) {
      widget.onShortcuts();
    } else if (command.startsWith('destination:')) {
      final index = int.tryParse(command.substring('destination:'.length));
      if (index != null && AppDestination.available.any((d) => d.index == index)) {
        widget.onNavigate(index);
      }
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!NativeMenuService.supported) return widget.child;
    final l10n = AppLocalizations.of(context)!;
    final enabled = ModalRoute.isCurrentOf(context) == true;
    Map<String, Object> command(String id, String label, ShortcutKey key) => {
      'id': id,
      'label': label,
      'enabled': enabled,
      // All application shortcuts originate in AppShortcuts, including modifiers.
      'key': key.key.keyLabel.toLowerCase(),
      'command': key.primary,
      'shift': key.shift,
      'option': key.alt,
    };
    unawaited(
      _service.update(
        labels: nativeMenuLabels(l10n),
        commands: [
          command(
            AppShortcutIds.openSettings,
            l10n.nativeMenuSettings,
            AppShortcuts.byId(AppShortcutIds.openSettings).keys.first,
          ),
          for (final destination in AppDestination.available)
            command(
              'destination:${destination.index}',
              destination.label(l10n),
              AppShortcuts.byId(AppShortcutIds.navigateToDestination).keys[destination.index],
            ),
          command(
            AppShortcutIds.showShortcutPanel,
            l10n.shortcutShowShortcutPanel,
            AppShortcuts.byId(AppShortcutIds.showShortcutPanel).keys.last,
          ),
        ],
      ),
    );
    return widget.child;
  }
}
