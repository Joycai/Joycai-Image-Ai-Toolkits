import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../state/gallery_state.dart';
import '../directory_tree_item.dart';

/// Read-only folder tree for the RESULTS section. Unlike [DirectoryTreeItem],
/// there is no selection/aggregate concept — tapping a row browses just that
/// folder via [GalleryState.setViewFolder].
class ResultTreeItem extends StatefulWidget {
  final String path;
  final bool isRoot;

  const ResultTreeItem({
    super.key,
    required this.path,
    this.isRoot = false,
  });

  @override
  State<ResultTreeItem> createState() => _ResultTreeItemState();
}

class _ResultTreeItemState extends State<ResultTreeItem> {
  bool _isExpanded = false;
  List<Directory>? _subDirectories;
  bool _isLoading = false;
  int _lastRefreshCounter = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final counter = Provider.of<GalleryState>(context).refreshCounter;
    if (counter != _lastRefreshCounter) {
      _lastRefreshCounter = counter;
      _subDirectories = null;
      if (_isExpanded) _loadSubDirectories();
    }
  }

  Future<void> _loadSubDirectories() async {
    if (_subDirectories != null) return;
    setState(() => _isLoading = true);
    try {
      final dir = Directory(widget.path);
      final List<Directory> subDirs = [];
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory && !p.basename(entity.path).startsWith('.')) {
          subDirs.add(entity);
        }
      }
      subDirs.sort((a, b) =>
          p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      if (mounted) {
        setState(() {
          _subDirectories = subDirs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _subDirectories = [];
          _isLoading = false;
        });
      }
    }
  }

  void _handleExpansionChanged(bool expanded) {
    setState(() => _isExpanded = expanded);
    if (expanded) _loadSubDirectories();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = Provider.of<AppState>(context, listen: false);
    final folderName = p.basename(widget.path);

    // Off GalleryState directly — AppState no longer forwards its changes.
    final isViewing = context.select<GalleryState, bool>((state) =>
        state.viewMode == GalleryViewMode.folder &&
        state.folderViewIsResult &&
        state.viewSourcePath == widget.path);

    // Boxed and tinted exactly like a source root. `16a` draws the two trees
    // as one family — a result folder is a folder — and the outline is what
    // says where one root's subtree ends. It read as a different kind of row
    // entirely while this was a bare tile beside the boxed sources.
    final colorScheme = theme.colorScheme;
    final Color? boxColor =
        isViewing ? colorScheme.primary.withValues(alpha: 0.14) : null;
    final Color borderColor = isViewing
        ? colorScheme.primary.withValues(alpha: 0.6)
        : (widget.isRoot ? colorScheme.outlineVariant.withAlpha(120) : Colors.transparent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(6, 2, 6, 2),
          child: Material(
            color: boxColor ?? Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
          dense: true,
          selected: isViewing,
          contentPadding: EdgeInsets.only(left: widget.isRoot ? 8 : 0, right: 4),
          minLeadingWidth: 0,
          horizontalTitleGap: 6,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isExpanded ? Icons.folder_open : Icons.folder,
                size: 20,
                // Amber, like every other folder in the app — grey here was
                // the one place the tree's own colour was dropped.
                color: kFolderAmber,
              ),
            ],
          ),
          title: Text(
            folderName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: isViewing ? FontWeight.w600 : FontWeight.w500,
              color: isViewing ? theme.colorScheme.primary : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: (_subDirectories == null || _subDirectories!.isNotEmpty)
              ? IconButton(
                  icon: _isLoading
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                  onPressed: () => _handleExpansionChanged(!_isExpanded),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                )
              : null,
          onTap: () => appState.galleryState.setViewFolder(widget.path, isResult: true),
            ),
          ),
        ),
        if (_isExpanded && _subDirectories != null)
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: Column(
              children: _subDirectories!
                  .map((dir) => ResultTreeItem(path: dir.path, isRoot: false))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
