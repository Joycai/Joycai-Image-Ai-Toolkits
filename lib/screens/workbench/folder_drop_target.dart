part of 'directory_tree_item.dart';

/// A row's drop state and the wording at its end.
typedef _RowDrop = ({FolderDropTone tone, String note});

/// Builds with the copy key's state, following [AppCopyModifier] only while
/// [active] — a tree of rows is not listening to the keyboard for the whole of
/// its life, only the one row a drag is over.
///
/// A widget of its own rather than a [ValueListenableBuilder] swapped in and
/// out, so the row under it keeps its element while hover comes and goes.
class _CopyModifierListener extends StatefulWidget {
  const _CopyModifierListener({required this.active, required this.builder});

  final bool active;
  final Widget Function(BuildContext context, bool copying) builder;

  @override
  State<_CopyModifierListener> createState() => _CopyModifierListenerState();
}

class _CopyModifierListenerState extends State<_CopyModifierListener> {
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_CopyModifierListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_listening) AppCopyModifier.instance.removeListener(_changed);
    super.dispose();
  }

  void _sync() {
    if (widget.active == _listening) return;
    _listening = widget.active;
    if (_listening) {
      AppCopyModifier.instance.addListener(_changed);
    } else {
      AppCopyModifier.instance.removeListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _listening && AppCopyModifier.instance.value);
}

/// A folder row that takes a dragged selection or a dragged folder, when the
/// browser owns this tree — `00d · 1d` 投放到对象.
///
/// Split out so the tree item itself stays one widget whichever screen it is
/// on: the workbench's copy builds the row through the same builder with the
/// target simply absent.
///
/// What this folder will not take — a folder over itself or one of its own
/// subfolders, a payload already in this folder — is refused at
/// [DragTarget.onWillAcceptWithDetails], and the row says why: the error ring
/// and the reason at its end, with the follower carrying the same reason.
/// Never lit as a place to drop, never a haptic, never a toast.
class _MaybeDropTarget extends StatefulWidget {
  final bool enabled;
  final String path;

  /// Called after the pointer has rested on the row with a payload it takes,
  /// so a closed folder opens to receive a deeper drop.
  final VoidCallback onHoverExpand;

  final Widget Function(BuildContext context, _RowDrop? drop) builder;

  const _MaybeDropTarget({
    required this.enabled,
    required this.path,
    required this.onHoverExpand,
    required this.builder,
  });

  @override
  State<_MaybeDropTarget> createState() => _MaybeDropTargetState();
}

class _MaybeDropTargetState extends State<_MaybeDropTarget> {
  /// `00d`: a closed folder opens once an accepted drag has rested on it this
  /// long. Opening changes the view, not the target.
  static const Duration _expandDelay = Duration(milliseconds: 600);

  Timer? _expandTimer;

  /// The verdict on the payload over the row, reached once as it enters:
  /// deciding touches the disk, and [DragTarget.onMove] fires per pointer
  /// event.
  bool _hoverAccepted = false;
  FolderDropRejection? _hoverRejection;

  /// Replaced on every drop this row takes, to flash the confirmation ring.
  Object? _dropped;

  @override
  void dispose() {
    _expandTimer?.cancel();
    // A row torn down mid-hover is never told the pointer left. Withdrawn
    // after the frame: the follower cannot be asked to rebuild while this
    // tree is being taken apart.
    final Object owner = this;
    WidgetsBinding.instance.addPostFrameCallback((_) => FolderDropFeedback.withdraw(owner));
    super.dispose();
  }

  /// Why this folder refuses [data], or null when a release here lands.
  ///
  /// A move and a copy are judged alike: a copy into the folder the payload
  /// already sits in collides with itself, which is "already here" too.
  FolderDropRejection? _rejection(Object data) {
    if (data is List<BrowserFile>) {
      // Only when all of it is here. A mixed selection still has somewhere
      // to go, and the transfer plan skips the files already in place.
      if (data.every((file) => p.equals(p.dirname(file.path), widget.path))) {
        return FolderDropRejection.sameFolder;
      }
    } else if (data is FolderDragPayload) {
      final roots = Provider.of<FileBrowserState>(context, listen: false).sourceDirectories.toSet();
      final refused = FolderOperationsService.canTransfer(
        data.path,
        widget.path,
        roots: roots,
        mode: AppCopyModifier.isDown ? FolderTransferMode.copy : FolderTransferMode.move,
      );
      if (refused != null) {
        return switch (refused) {
          FolderMoveRejection.isRoot => FolderDropRejection.root,
          FolderMoveRejection.intoSelf ||
          FolderMoveRejection.intoDescendant => FolderDropRejection.intoItself,
          FolderMoveRejection.sameParent => FolderDropRejection.sameFolder,
          FolderMoveRejection.targetExists =>
            p.equals(p.dirname(data.path), widget.path)
                ? FolderDropRejection.sameFolder
                : FolderDropRejection.nameTaken,
        };
      }
    }
    return _isReadOnly(widget.path) ? FolderDropRejection.readOnly : null;
  }

  /// A folder that grants no one write permission. Only the POSIX mode bits
  /// are read: Windows keeps a folder's read-only attribute for the shell and
  /// ignores it for writes, and ownership, ACLs and sandboxes are left to the
  /// transfer, which reports what it could not do.
  static bool _isReadOnly(String path) {
    if (Platform.isWindows) return false;
    final stat = FileStat.statSync(path);
    // 0x92 is 0o222: the write bit for owner, group and others.
    return stat.type == FileSystemEntityType.directory && (stat.mode & 0x92) == 0;
  }

  bool _willAccept(Object data) {
    if (data is! List<BrowserFile> && data is! FolderDragPayload) {
      _hoverAccepted = false;
      _hoverRejection = null;
      return false;
    }
    final why = _rejection(data);
    _hoverAccepted = why == null;
    _hoverRejection = why;
    FolderDropFeedback.post(this, why);
    return why == null;
  }

  void _armExpand() {
    _expandTimer ??= Timer(_expandDelay, () {
      _expandTimer = null;
      if (mounted) widget.onHoverExpand();
    });
  }

  void _endHover() {
    _expandTimer?.cancel();
    _expandTimer = null;
    _hoverAccepted = false;
    _hoverRejection = null;
    FolderDropFeedback.withdraw(this);
  }

  void _drop(Object data) {
    _endHover();
    // Read at drop time, not at drag start: the user can reach for the copy
    // key (Ctrl, ⌥ on macOS) after picking the files up, which is when they
    // decide it is a copy.
    final copying = AppCopyModifier.isDown;
    setState(() => _dropped = Object());
    if (data is List<BrowserFile>) {
      runStagingPaste(
        context,
        mode: copying ? FileTransferMode.copy : FileTransferMode.move,
        destination: widget.path,
        files: data,
      );
    } else if (data is FolderDragPayload) {
      runFolderTransfer(
        context,
        source: data.path,
        destination: widget.path,
        mode: copying ? FolderTransferMode.copy : FolderTransferMode.move,
      );
    }
  }

  /// What a release of an accepted [data] does, in the row's words.
  String _note(AppLocalizations l10n, Object? data, bool copying) {
    final name = p.basename(widget.path);
    if (!copying) return l10n.dropMoveTo(name);
    return data is List<BrowserFile>
        ? l10n.dropCopyItemsTo(data.length, name)
        : l10n.dropCopyTo(name);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder(context, null);
    final l10n = AppLocalizations.of(context)!;

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => _willAccept(details.data),
      onMove: (_) {
        if (_hoverAccepted) _armExpand();
      },
      onLeave: (_) => _endHover(),
      onAcceptWithDetails: (details) => _drop(details.data),
      builder: (context, candidate, rejected) {
        final bool accepted = candidate.isNotEmpty;
        // A payload from elsewhere in the app lands in `rejected` too; only
        // one this row judged has a reason to show.
        final FolderDropRejection? why = rejected.isNotEmpty ? _hoverRejection : null;
        return AppDropConfirmRing(
          trigger: _dropped,
          radius: AppRadius.sm,
          child: _CopyModifierListener(
            active: accepted,
            builder: (context, copying) {
              final _RowDrop? drop = why != null
                  ? (tone: FolderDropTone.reject, note: why.label(l10n))
                  : accepted
                  ? (
                      tone: copying ? FolderDropTone.copy : FolderDropTone.move,
                      note: _note(l10n, candidate.first, copying),
                    )
                  : null;
              return widget.builder(context, drop);
            },
          ),
        );
      },
    );
  }
}
