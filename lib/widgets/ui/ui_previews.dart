import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/localizations_delegates.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'app_dialog.dart';
import 'app_dropdown.dart';
import 'app_empty_state.dart';
import 'app_icon_button.dart';
import 'app_search_field.dart';
import 'app_section_label.dart';
import 'app_segmented_control.dart';
import 'app_text_field.dart';

/// Applies the project's warm-stone light/dark theme for `@Preview` widgets.
final class JoycaiPreviewThemeData extends PreviewThemeData {
  const JoycaiPreviewThemeData({this.brightness = Brightness.light});

  final Brightness brightness;

  @override
  Widget apply(BuildContext context, Widget child) {
    final ThemeData theme = buildAppTheme(
      accent: AppConstants.presetThemes[AppConstants.defaultThemeAccentKey]!,
      brightness: brightness,
    );
    return Theme(
      data: theme,
      child: Material(color: theme.colorScheme.surfaceContainer, child: child),
    );
  }
}

PreviewLocalizationsData _joycaiPreviewLocalizations() => const PreviewLocalizationsData(
  locale: Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
);

/// Generates paired light and dark widget previews using Joycai's theme.
final class JoycaiBrightnessPreview extends MultiPreview {
  const JoycaiBrightnessPreview({required this.name, this.group = 'Joycai UI', this.size});

  final String name;
  final String group;
  final Size? size;

  static PreviewThemeData _lightTheme() =>
      const JoycaiPreviewThemeData(brightness: Brightness.light);
  static PreviewThemeData _darkTheme() => const JoycaiPreviewThemeData(brightness: Brightness.dark);

  @override
  List<Preview> get previews => const [
    Preview(brightness: Brightness.light),
    Preview(brightness: Brightness.dark),
  ];

  @override
  List<Preview> transform() {
    return super.transform().map((Preview preview) {
      final bool isDark = preview.brightness == Brightness.dark;
      final PreviewBuilder builder = preview.toBuilder()
        ..group = group
        ..name = '$name · ${isDark ? 'Dark' : 'Light'}'
        ..size = size
        ..localizations = _joycaiPreviewLocalizations
        ..theme = isDark ? _darkTheme : _lightTheme;
      return builder.build();
    }).toList();
  }
}

@JoycaiBrightnessPreview(name: 'AppButton variants', size: Size(520, 140))
Widget previewAppButtons() => Padding(
  padding: const EdgeInsets.all(AppSpace.s16),
  child: Wrap(
    spacing: AppSpace.s10,
    runSpacing: AppSpace.s10,
    children: [
      AppButton(label: 'Primary', icon: Icons.save_outlined, onPressed: () {}),
      AppButton(label: 'Secondary', variant: AppButtonVariant.secondary, onPressed: () {}),
      AppButton(label: 'Tonal', variant: AppButtonVariant.tonal, onPressed: () {}),
      AppButton(label: 'Text', variant: AppButtonVariant.text, onPressed: () {}),
      AppButton(label: 'Destructive', variant: AppButtonVariant.destructive, onPressed: () {}),
      AppIconButton(icon: Icons.tune_outlined, tooltip: 'Settings', onPressed: () {}),
    ],
  ),
);

@JoycaiBrightnessPreview(name: 'AppSegmentedControl', size: Size(420, 100))
Widget previewAppSegmentedControl() => Padding(
  padding: const EdgeInsets.all(AppSpace.s16),
  child: AppSegmentedControl<int>(
    value: 0,
    onChanged: (_) {},
    segments: const [
      AppSegment(value: 0, label: 'Chat', icon: Icons.chat_bubble_outline),
      AppSegment(value: 1, label: 'Image', icon: Icons.image_outlined),
      AppSegment(value: 2, label: 'Video', icon: Icons.movie_outlined),
    ],
  ),
);

@JoycaiBrightnessPreview(name: 'Inputs & Dropdown', size: Size(460, 220))
Widget previewInputsAndDropdown() => Padding(
  padding: const EdgeInsets.all(AppSpace.s16),
  child: AppCard(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSearchField(controller: TextEditingController(), hint: 'Search...'),
        const SizedBox(height: AppSpace.s10),
        const AppTextField(hint: 'Model ID'),
        const SizedBox(height: AppSpace.s10),
        AppDropdown<int>(
          value: 0,
          items: const [AppDropdownItem(value: 0, label: 'OpenAI Compatible')],
          onChanged: (_) {},
        ),
      ],
    ),
  ),
);

@JoycaiBrightnessPreview(name: 'Card, Section & EmptyState', size: Size(460, 320))
Widget previewCardAndEmptyState() => Padding(
  padding: const EdgeInsets.all(AppSpace.s16),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppSectionLabel('Output Configuration', padding: EdgeInsets.only(bottom: AppSpace.s10)),
      AppEmptyState(
        icon: Icons.inbox_outlined,
        label: 'No models configured',
        description: 'Add a channel first to pull available models.',
        action: AppButton(
          label: 'Add Channel',
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.compact,
          onPressed: () {},
        ),
      ),
    ],
  ),
);

@JoycaiBrightnessPreview(name: 'AppDialog shell', size: Size(520, 260))
Widget previewAppDialog() => Builder(
  builder: (context) => Padding(
    padding: const EdgeInsets.all(AppSpace.s16),
    child: AppDialog(
      icon: Icons.warning_amber_rounded,
      iconColor: Theme.of(context).colorScheme.error,
      title: 'Overwrite original?',
      subtitle: 'This action cannot be undone.',
      onClose: () {},
      content: const Text('The source image will be replaced by the cropped result.'),
      actions: [
        AppButton(label: 'Cancel', variant: AppButtonVariant.text, onPressed: () {}),
        AppButton(label: 'Overwrite', variant: AppButtonVariant.destructive, onPressed: () {}),
      ],
    ),
  ),
);
