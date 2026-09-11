import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// The in-row name field for creating or renaming a folder — `B1b 1d`
/// 「内联改名校验五态」.
///
/// Lives inside the directory tree row in place of the folder's name, so the
/// user names the thing where it is going to be rather than in a dialog
/// somewhere else. The rules are the ones every file manager trained them on:
/// Enter commits, Escape cancels, clicking away commits, and a name that has
/// not changed is a cancel that costs nothing.
///
/// Validation runs on every keystroke and shows **under the field**, never as
/// a snackbar: an error in the error colour, "already in the list" as a
/// warning. Enter on an invalid name — an empty one included — shakes the
/// field once instead of committing, and clicking away from an invalid name
/// abandons it.
class FolderNameEditor extends StatefulWidget {
  final String initialName;

  /// The message to show for [name], or null when it can be committed.
  final String? Function(String name) validate;

  /// Commits [name]. Resolves to a message to show in place (the field stays
  /// open, the user can try again) or to null when done — after which the
  /// caller is expected to take this widget out of the tree.
  final Future<String?> Function(String name) onSubmit;

  final VoidCallback onCancel;

  const FolderNameEditor({
    super.key,
    required this.initialName,
    required this.validate,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<FolderNameEditor> createState() => _FolderNameEditorState();
}

class _FolderNameEditorState extends State<FolderNameEditor> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode(debugLabel: 'folder-name-editor');

  String? _error;
  bool _submitting = false;

  /// Set once the editor has decided its fate, so the focus loss its own
  /// removal causes is not read as a second commit.
  bool _closed = false;

  /// Bumped to replay the shake; 0 means it has never played.
  int _shake = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName)
      ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialName.length);
    _focusNode
      ..onKeyEvent = _onKey
      ..addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && !_submitting && !_closed) {
      _submit(fromBlur: true);
    }
  }

  void _cancel() {
    if (_closed) return;
    _closed = true;
    widget.onCancel();
  }

  Future<void> _submit({bool fromBlur = false}) async {
    if (_closed || _submitting) return;
    final name = _controller.text;
    if (name.trim() == widget.initialName.trim()) {
      _cancel();
      return;
    }

    // An empty name goes through the validator like any other bad name —
    // the spec lists "cannot be empty" first among the messages, so Enter on
    // it shakes rather than silently closing the row.
    final error = widget.validate(name);
    if (error != null) {
      // Clicking away from a bad name abandons it; pressing Enter on one
      // asks the user to look again.
      if (fromBlur) {
        _cancel();
      } else {
        setState(() {
          _error = error;
          _shake++;
        });
      }
      return;
    }
    if (name.trim().isEmpty) {
      // A validator that let an empty name through: still nothing to create.
      _cancel();
      return;
    }

    setState(() => _submitting = true);
    final failure = await widget.onSubmit(name);
    if (!mounted) return;
    if (failure == null) {
      _closed = true;
      return;
    }
    setState(() {
      _submitting = false;
      _error = failure;
    });
    _focusNode.requestFocus();
  }

  void _onChanged(String value) {
    final error = widget.validate(value);
    if (error != _error) setState(() => _error = error);
  }

  /// "This path is already in the list" is the one message that is a warning
  /// rather than an error: nothing about the name is wrong, the folder is
  /// simply registered already.
  bool _isWarning(BuildContext context, String message) =>
      message == AppLocalizations.of(context)?.folderPathRegistered;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;

    final error = _error;
    final warning = error != null && _isWarning(context, error);

    final Color edge;
    final Color halo;
    if (error == null) {
      edge = colorScheme.primary;
      halo = colorScheme.accentRing;
    } else if (warning) {
      edge = semantic.warning;
      halo = semantic.warning.withValues(alpha: AppAlpha.tint);
    } else {
      edge = colorScheme.error;
      halo = colorScheme.error.withValues(alpha: AppAlpha.tint);
    }

    final field = AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      height: AppSize.control,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: edge),
        boxShadow: [BoxShadow(color: halo, spreadRadius: 3)],
      ),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: !_submitting,
        style: textTheme.bodySmall!.mono.copyWith(color: colorScheme.onSurface),
        decoration: const InputDecoration.collapsed(hintText: null),
        maxLines: 1,
        onChanged: _onChanged,
        // A no-op on purpose: the default drops focus on Enter, and losing
        // focus is this field's "click away" — which would turn Enter on a
        // bad name into a silent cancel instead of the shake.
        onEditingComplete: () {},
        onSubmitted: (_) => _submit(),
      ),
    );

    final Color messageInk = warning ? semantic.onWarningContainer : colorScheme.onErrorContainer;
    final Color messageGlyph = warning ? semantic.warning : colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _shaken(field),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s6, left: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    warning ? Icons.warning_amber_rounded : Icons.error_outline,
                    size: 12,
                    color: messageGlyph,
                  ),
                ),
                const SizedBox(width: AppSpace.s4),
                Expanded(
                  child: Text(
                    error,
                    style: textTheme.labelSmall!.copyWith(color: messageInk),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// One short horizontal shake, replayed each time [_shake] changes.
  Widget _shaken(Widget child) {
    if (_shake == 0) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(_shake),
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.durationOf(context, AppMotion.panel),
      builder: (context, t, child) => Transform.translate(
        offset: Offset(math.sin(t * math.pi * 4) * 4 * (1 - t), 0),
        child: child,
      ),
      child: child,
    );
  }
}
