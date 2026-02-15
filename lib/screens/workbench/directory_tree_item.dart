import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/gallery_state.dart';

class DirectoryTreeItem extends StatefulWidget {
  final String path;
  final bool isRoot;
  final bool useBrowserState;
  final Function(String, String)? onRemove; // Only needed for roots

  const DirectoryTreeItem({
    super.key,
    required this.path,
    this.isRoot = false,
    this.useBrowserState = false,
    this.onRemove,
  });

  @override
  State<DirectoryTreeItem> createState() => _DirectoryTreeItemState();
}

class _DirectoryTreeItemState extends State<DirectoryTreeItem> {
  bool _isExpanded = false;
  List<Directory>? _subDirectories;
  bool _isLoading = false;

  Future<void> _loadSubDirectories() async {
    if (_subDirectories != null) return;

    setState(() => _isLoading = true);
    try {
      final dir = Directory(widget.path);
      final List<Directory> subDirs = [];
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory) {
          // Filter out hidden directories
          if (!p.basename(entity.path).startsWith('.')) {
            subDirs.add(entity);
          }
        }
      }
      
      // Sort alphabetically
      subDirs.sort((a, b) => 
        p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase())
      );

      if (mounted) {
        setState(() {
          _subDirectories = subDirs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _subDirectories = []; // Treat error/access denied as empty
          _isLoading = false;
        });
      }
    }
  }

  void _handleExpansionChanged(bool expanded) {
    setState(() => _isExpanded = expanded);
    if (expanded) {
      _loadSubDirectories();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to selection changes efficiently based on the target state
    final isSelected = context.select<AppState, bool>((state) {
      if (widget.useBrowserState) {
        return state.browserState.activeDirectories.contains(widget.path);
      } else {
        return state.activeSourceDirectories.contains(widget.path);
      }
    });

    final isViewing = context.select<AppState, bool>((state) {
      if (widget.useBrowserState) return false;
      return state.galleryState.viewMode == GalleryViewMode.folder && state.galleryState.viewSourcePath == widget.path;
    });
    
    final appState = Provider.of<AppState>(context, listen: false);
    final folderName = p.basename(widget.path);
    final theme = Theme.of(context);

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
              Checkbox(
                value: isSelected,
                onChanged: (_) {
                  if (widget.useBrowserState) {
                    appState.browserState.toggleDirectory(widget.path);
                  } else {
                    appState.toggleDirectory(widget.path);
                  }
                },
                visualDensity: VisualDensity.compact,
              ),
              Icon(
                _isExpanded ? Icons.folder_open : Icons.folder,
                size: 20,
                color: isViewing ? theme.colorScheme.primary : (isSelected ? theme.colorScheme.primary.withAlpha(150) : theme.colorScheme.outline),
              ),
              const SizedBox(width: 8),
            ],
          ),
          title: InkWell(
            onTap: () {
              if (!widget.useBrowserState) {
                appState.galleryState.setViewFolder(widget.path);
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    folderName,
                    style: TextStyle(
                      fontSize: 13, 
                      fontWeight: isViewing ? FontWeight.bold : FontWeight.w500,
                      color: isViewing ? theme.colorScheme.primary : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_subDirectories == null || _subDirectories!.isNotEmpty)
                IconButton(
                  icon: _isLoading 
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                  onPressed: () => _handleExpansionChanged(!_isExpanded),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
              
              if (widget.isRoot && widget.onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => widget.onRemove!(widget.path, folderName),
                  padding: const EdgeInsets.only(left: 8),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          onTap: () => _handleExpansionChanged(!_isExpanded),
        ),
        
        if (_isExpanded && _subDirectories != null)
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: Column(
              children: _subDirectories!.map((dir) {
                return DirectoryTreeItem(
                  path: dir.path,
                  isRoot: false,
                  useBrowserState: widget.useBrowserState,
                  // onRemove not needed for children
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}