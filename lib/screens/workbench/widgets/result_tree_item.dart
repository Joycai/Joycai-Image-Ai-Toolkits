import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../state/gallery_state.dart';

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
    final counter = Provider.of<AppState>(context).galleryState.refreshCounter;
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

    final isViewing = context.select<AppState, bool>((state) =>
        state.galleryState.viewMode == GalleryViewMode.folder &&
        state.galleryState.folderViewIsResult &&
        state.galleryState.viewSourcePath == widget.path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          selected: isViewing,
          contentPadding: EdgeInsets.only(left: widget.isRoot ? 8 : 0, right: 4),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 8),
              Icon(
                _isExpanded ? Icons.folder_open : Icons.folder,
                size: 20,
                color: isViewing ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
            ],
          ),
          title: Text(
            folderName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isViewing ? FontWeight.bold : FontWeight.w500,
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
