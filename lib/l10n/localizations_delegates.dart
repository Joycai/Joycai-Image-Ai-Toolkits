import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import 'app_localizations.dart';

/// Localization delegates for `package:material_ui`'s [MaterialApp].
///
/// Flutter 3.50's `gen-l10n` still emits [AppLocalizations.localizationsDelegates]
/// referencing the deprecated `flutter_localizations` Material/Cupertino
/// delegates, which [MaterialApp] from `package:material_ui` does not recognize
/// for non-English locales. Use this list until `gen-l10n` emits `material_ui`
/// and `cupertino_ui` delegates directly.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
