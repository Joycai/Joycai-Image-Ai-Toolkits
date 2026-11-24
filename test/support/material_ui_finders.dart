import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Finds a `package:material_ui` [Tooltip] (including those with
/// `excludeFromSemantics: true`) or a [RawTooltip] whose message matches
/// [message].
///
/// Flutter 3.50's `flutter_test` `find.byTooltip` still checks the deprecated
/// `package:flutter/material.dart` `Tooltip` when `excludeFromSemantics` is
/// true, so it misses `material_ui.Tooltip` widgets that opt out of duplicate
/// tooltip semantics.
Finder findTooltip(Pattern message, {bool skipOffstage = true}) {
  return find.byWidgetPredicate((Widget widget) {
    if (widget is Tooltip) {
      final String tooltipMessage = widget.message ?? widget.richMessage?.toPlainText() ?? '';
      if ((widget.excludeFromSemantics ?? false) || tooltipMessage.isEmpty) {
        return message is RegExp ? message.hasMatch(tooltipMessage) : tooltipMessage == message;
      }
    }
    return widget is RawTooltip &&
        (message is RegExp
            ? message.hasMatch(widget.semanticsTooltip ?? '')
            : widget.semanticsTooltip == message);
  }, skipOffstage: skipOffstage);
}
