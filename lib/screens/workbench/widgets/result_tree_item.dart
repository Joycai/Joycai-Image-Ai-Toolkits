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
///
/// Drawn through the same [FolderTreeRow] as the source tree: `A1 1a` shows
/// the two as one family, a result folder being a folder.
class ResultTreeItem extends StatefulWidget {
  final String path;
  final bool isRoot;

  /// Nesting level — 0 for a root. See [DirectoryTreeItem.depth].
  final int depth;

  const ResultTreeItem({
    super.key,
    required this.path,
    this.isRoot = false,
    this.depth = 0,
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
    final appState = Provider.of<AppState>(context, listen: false);
    final folderName = p.basename(widget.path);
    final metrics = FolderTreeMetrics.of(context);

    // Off GalleryState directly — AppState no longer forwards its changes.
    final isViewing = context.select<GalleryState, bool>((state) =>
        state.viewMode == GalleryViewMode.folder &&
        state.folderViewIsResult &&
        state.viewSourcePath == widget.path);

    final TreeDisclosure disclosure = _subDirectories != null && _subDirectories!.isEmpty
        ? TreeDisclosure.none
        : _isLoading
            ? TreeDisclosure.loading
            : (_isExpanded ? TreeDisclosure.expanded : TreeDisclosure.collapsed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.margin),
          child: FolderTreeRow(
            depth: widget.depth,
            disclosure: disclosure,
            onToggle: () => _handleExpansionChanged(!_isExpanded),
            icon: Icons.folder_outlined,
            label: folderName,
            selected: isViewing,
            onTap: () => appState.galleryState.setViewFolder(widget.path, isResult: true),
          ),
        ),
        if (_isExpanded && _subDirectories != null)
          ..._subDirectories!.map((dir) => ResultTreeItem(
                // Keyed by path so a child's expansion follows its directory
                // when siblings come and go across refreshes.
                key: ValueKey(dir.path),
                path: dir.path,
                depth: widget.depth + 1,
              )),
      ],
    );
  }
}
