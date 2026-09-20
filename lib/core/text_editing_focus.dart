import 'package:flutter/widgets.dart';

/// Whether the keyboard currently belongs to a text field.
///
/// A key event that a text field does not consume — Backspace and Delete
/// among them — still travels up to every ancestor [Focus] handler, so a
/// screen-level shortcut fires while the user is typing unless it asks. The
/// browser's inline folder-name editor is the case that made this necessary:
/// the tree row deliberately ignores keys while it is editing so the field
/// gets them, and the screen above it was the next handler in line.
bool isTextEditingFocused() {
  final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  if (focused.widget is EditableText) return true;
  return focused.findAncestorWidgetOfExactType<EditableText>() != null;
}
