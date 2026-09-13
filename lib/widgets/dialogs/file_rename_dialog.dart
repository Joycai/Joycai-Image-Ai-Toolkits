import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/folder_operations_service.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import '../app_snackbar.dart';
import '../glass/app_glass.dart';

/// The longest file name the disks this app writes to accept, in characters.
const int kFileRenameMaxLength = 255;

/// Renames one file behind the 「文件 ▸ 重命名」 dialog (`A1 · 2b`), shared by
/// the gallery card's menu and the file browser's.
///
/// Unlike `01 · 1h`'s opaque dialogs — which are for destructive, one-way
/// decisions — a rename is light and reversible, so its shell is float-grade
/// glass at r22, 360 wide, over a lighter scrim. The field opens with the
/// stem selected and the extension shown locked beside it; a name that
/// cannot be used (empty, illegal characters, reserved, already in the
/// folder) turns the focus ring and caret to the error ink, swaps the
/// shortcut hint for the reason, and disables Rename. Nothing is written
/// until the name is usable, so the conflict snackbar the old dialog raised
/// after the fact no longer exists.
///
/// [onSuccess] runs after the file has moved, before the confirming
/// snackbar; the callers use it to rescan.
Future<void> showFileRenameDialog({
  required BuildContext context,
  required String filePath,
  required VoidCallback onSuccess,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final scheme = Theme.of(context).colorScheme;

  final String? newStem = await showDialog<String>(
    context: context,
    animationStyle: appDialogAnimation(context),
    // `2b`: the scrim at 60% — a rename is not the kind of decision the full
    // scrim is for.
    barrierColor: scheme.scrim.withValues(alpha: scheme.scrim.a * 0.6),
    builder: (_) => FileRenameDialog(filePath: filePath),
  );
  if (newStem == null) return;

  final file = File(filePath);
  final newPath = p.join(
    p.dirname(filePath),
    '$newStem${p.extension(filePath)}',
  );
  try {
    await file.rename(newPath);
    onSuccess();
    if (context.mounted) AppSnackBar.success(context, l10n.renameSuccess);
  } catch (e) {
    if (context.mounted) {
      AppSnackBar.error(context, l10n.renameFailed(e.toString()));
    }
  }
}

/// The dialog itself; pops with the new stem, or null. Public so tests can
/// find it — open it with [showFileRenameDialog].
class FileRenameDialog extends StatefulWidget {
  const FileRenameDialog({super.key, required this.filePath});

  final String filePath;

  /// `2b`: 「360 宽」.
  static const double width = 360;

  @override
  State<FileRenameDialog> createState() => _FileRenameDialogState();
}

class _FileRenameDialogState extends State<FileRenameDialog> {
  late final String _dir = p.dirname(widget.filePath);
  late final String _extension = p.extension(widget.filePath);
  late final String _stem = p.basenameWithoutExtension(widget.filePath);
  late final TextEditingController
  _controller = TextEditingController(text: _stem)
    // Opened with the stem selected: the common rename replaces the name
    // outright, and a caret at the end would make that two extra keystrokes.
    ..selection = TextSelection(baseOffset: 0, extentOffset: _stem.length);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String get _clean => FolderOperationsService.sanitize(_controller.text);

  /// The full name the stem would produce, what the disk will be asked for.
  String get _candidate => '$_clean$_extension';

  bool get _unchanged => _clean == _stem;

  bool get _tooLong => _candidate.length > kFileRenameMaxLength;

  /// Why the name cannot be used, or null. Reuses the folder rules — a file
  /// name lives by the same ones — with the file itself as [currentPath] so
  /// keeping the name is not "already exists".
  FolderNameError? get _error {
    // The rules see the whole name, and `.png` alone is not empty to them.
    if (_clean.isEmpty) return FolderNameError.empty;
    return FolderOperationsService.validateName(
      parent: _dir,
      name: _candidate,
      currentPath: widget.filePath,
    );
  }

  bool get _canRename => !_unchanged && !_tooLong && _error == null;

  String? _errorText(AppLocalizations l10n) {
    if (_tooLong) return l10n.renameTooLong(kFileRenameMaxLength);
    return switch (_error) {
      null => null,
      FolderNameError.empty => l10n.folderNameEmpty,
      FolderNameError.illegalChars => l10n.folderNameIllegalChars(
        FolderOperationsService.illegalChars(),
      ),
      FolderNameError.reservedName => l10n.folderNameReserved,
      FolderNameError.exists => l10n.renameConflict(_candidate),
      FolderNameError.registered => l10n.renameConflict(_candidate),
    };
  }

  void _submit() {
    if (_canRename) Navigator.of(context).pop<String>(_clean);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final radius = BorderRadius.circular(appDialogRadius);
    final String? problem = _errorText(l10n);

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: FileRenameDialog.width),
        // The glass's own shadow, not `2b`'s larger 「0 24px 64px」: a shadow
        // painted under a translucent panel shows through it, and that one
        // read as a grey slab behind the dialog on the light theme.
        child: AppGlass(
          grade: GlassGrade.float,
          borderRadius: radius,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Heading(
                  dir: _dir,
                  fileName: p.basename(widget.filePath),
                  l10n: l10n,
                ),
                const SizedBox(height: 12),
                _NameField(
                  controller: _controller,
                  focusNode: _focus,
                  extension: _extension,
                  error: problem != null,
                  onSubmitted: _submit,
                  lockLabel: l10n.renameExtensionLocked,
                ),
                const SizedBox(height: 12),
                _HintRow(
                  problem: problem,
                  hint: l10n.renameHintKeys,
                  count: _candidate.length,
                  tooLong: _tooLong,
                ),
                const SizedBox(height: 12),
                const _Rule(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      label: l10n.cancel,
                      variant: AppButtonVariant.text,
                      onPressed: () => Navigator.of(context).pop<String>(null),
                    ),
                    const SizedBox(width: AppSpace.s4),
                    AppButton(
                      label: l10n.rename,
                      onPressed: _canRename ? _submit : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `2b`: a lens-grade 40px plate carrying the rename glyph in the accent,
/// the title, and under it the folder and the current name in mono.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.dir,
    required this.fileName,
    required this.l10n,
  });

  final String dir;
  final String fileName;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;

    return Row(
      children: [
        AppGlass(
          grade: GlassGrade.lens,
          borderRadius: BorderRadius.circular(AppRadius.control),
          shadow: false,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              Icons.drive_file_rename_outline,
              size: 22,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.rename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium!.metricsOnly.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: 1),
              Text.rich(
                TextSpan(
                  text: '${p.basename(dir)} / ',
                  children: [
                    TextSpan(
                      text: fileName,
                      style: textTheme.bodySmall!.mono.metricsOnly,
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall!.metricsOnly.copyWith(color: ink2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `2b`: 36 tall at r10, the glass ink at 8% for a fill, a 2px ring in the
/// accent while focused — the error ink instead when the name is unusable —
/// the stem editable in mono, the extension dimmed beside it and a lock at
/// the end saying it stays.
class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.focusNode,
    required this.extension,
    required this.error,
    required this.onSubmitted,
    required this.lockLabel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String extension;
  final bool error;
  final VoidCallback onSubmitted;
  final String lockLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final Color accent = error ? scheme.error : scheme.primary;
    final mono = textTheme.bodyMedium!.mono.metricsOnly;

    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final bool ringed = focusNode.hasFocus || error;
        return AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.hover),
          height: 36,
          decoration: BoxDecoration(
            color: ink.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              width: 2,
              color: ringed ? accent : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // As wide as its text, so the extension sits right after the
              // stem the way the name reads; shrinks before the lock does.
              Flexible(
                child: IntrinsicWidth(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    maxLines: 1,
                    cursorColor: accent,
                    cursorWidth: 1.5,
                    style: mono.copyWith(color: ink),
                    textAlignVertical: TextAlignVertical.center,
                    // No decorator at all: the box, fill and ring are this
                    // container's, and even a collapsed decoration still drew
                    // the theme's outline inside them.
                    decoration: null,
                    inputFormatters: [
                      // Newlines never belong in a name; Enter is the confirm.
                      FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                    ],
                    onSubmitted: (_) => onSubmitted(),
                  ),
                ),
              ),
              Text(extension, style: mono.copyWith(color: ink2)),
              const Spacer(),
              const SizedBox(width: AppSpace.s10),
              Icon(Icons.lock_outline, size: AppSize.iconSm, color: ink2),
              const SizedBox(width: AppSpace.s4),
              Text(
                lockLabel,
                style: textTheme.labelSmall!.mono.metricsOnly.copyWith(
                  fontWeight: FontWeight.w400,
                  color: ink2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// `2b`: the keyboard hint on the left and the length on the right; when the
/// name is unusable the hint gives way to the reason, in the error ink.
class _HintRow extends StatelessWidget {
  const _HintRow({
    required this.problem,
    required this.hint,
    required this.count,
    required this.tooLong,
  });

  final String? problem;
  final String hint;
  final int count;
  final bool tooLong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final small = textTheme.labelSmall!.metricsOnly.copyWith(
      fontWeight: FontWeight.w400,
      color: ink2,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: problem == null
                ? Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  )
                : Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: AppSize.iconSm,
                        color: scheme.error,
                      ),
                      const SizedBox(width: AppSpace.s4),
                      Expanded(
                        child: Text(
                          problem!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small.copyWith(color: scheme.error),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: AppSpace.s10),
          Text(
            '$count / $kFileRenameMaxLength',
            style: small.mono.copyWith(color: tooLong ? scheme.error : ink2),
          ),
        ],
      ),
    );
  }
}

/// `2b`: the footer is ruled off by a hairline alone — no column-coloured
/// band as under `1h`. The glass's secondary ink at a hairline's weight, as
/// the menu rule is: the refraction edge disappears on light glass.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    final glass = GlassInk.maybeOf(context);
    final Color color = glass == null || glass.reduced
        ? (glass?.edge ?? Theme.of(context).colorScheme.outlineVariant)
        : glass.ink2.withValues(alpha: 0.2);
    return SizedBox(height: 1, child: ColoredBox(color: color));
  }
}
