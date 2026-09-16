import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../drag/app_drag_follower.dart';
import '../drag/app_drag_session.dart';

/// Why a folder row refuses what is dragged over it (`00d · 1d` 拒绝).
enum FolderDropRejection {
  /// A folder over itself, or over one of its own subfolders.
  intoItself,

  /// Everything dragged already sits in this folder — a release would do
  /// nothing.
  sameFolder,

  /// A registered root, which stays where it is.
  root,

  /// The folder grants no one write permission.
  readOnly,

  /// The folder already holds an entry with the dragged folder's name.
  nameTaken,
}

extension FolderDropRejectionLabel on FolderDropRejection {
  /// The reason, as the row's chip and the follower say it.
  String label(AppLocalizations l10n) => switch (this) {
        FolderDropRejection.intoItself => l10n.dropRejectIntoItself,
        FolderDropRejection.sameFolder => l10n.dropRejectSameFolder,
        FolderDropRejection.root => l10n.dropRejectRoot,
        FolderDropRejection.readOnly => l10n.dropRejectReadOnly,
        FolderDropRejection.nameTaken => l10n.dropRejectNameTaken,
      };
}

/// The refusal of the folder row under the pointer, told to the drag follower
/// (`00d · 1e` 拒绝态).
///
/// A [DragTarget] learns the payload but has no way to reach the feedback
/// widget, so the row under the pointer posts its verdict here and the
/// follower listens. Only that row writes it, and only it clears it.
class FolderDropFeedback {
  FolderDropFeedback._();

  static final ValueNotifier<FolderDropRejection?> _rejection = ValueNotifier(null);
  static Object? _owner;

  /// The reason the row under the pointer gives, or null when there is none —
  /// no row, or one that takes the drag.
  static ValueListenable<FolderDropRejection?> get rejection => _rejection;

  /// Posts [why] as the verdict of the row under the pointer, [owner].
  ///
  /// Only a folder row's drop target calls this, when it judges a payload —
  /// and [withdraw] only clears what the same owner posted, so a row the
  /// pointer has already left cannot wipe the verdict of the row it moved onto.
  static void post(Object owner, FolderDropRejection? why) {
    _owner = owner;
    _rejection.value = why;
  }

  /// Clears the verdict, if [owner] is the one that posted it.
  static void withdraw(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _rejection.value = null;
  }
}

/// A drag follower for payloads the file browser's folder rows take: [builder]
/// draws the move or copy chip, following the copy key live; over a row that
/// refuses the payload the follower becomes that refusal instead.
class FolderDropFollower extends StatelessWidget {
  const FolderDropFollower({super.key, required this.builder});

  final Widget Function(BuildContext context, bool copying) builder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<FolderDropRejection?>(
      valueListenable: FolderDropFeedback.rejection,
      builder: (context, why, _) {
        if (why != null) {
          return AppDragFollower(icon: Icons.block, label: why.label(l10n), tone: AppDragTone.reject);
        }
        return ValueListenableBuilder<bool>(
          valueListenable: AppCopyModifier.instance,
          builder: (context, copying, _) => builder(context, copying),
        );
      },
    );
  }
}
