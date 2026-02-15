import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../state/window_state.dart';

class MetadataInspector extends StatefulWidget {
  final ScrollController? scrollController;
  const MetadataInspector({super.key, this.scrollController});

  @override
  State<MetadataInspector> createState() => _MetadataInspectorState();
}

class _MetadataInspectorState extends State<MetadataInspector> {
  Map<String, String>? _rawMetadata;
  Map<String, String>? _afterMetadata;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    
    final windowState = Provider.of<WindowState>(context, listen: false);
    windowState.addListener(_onWindowStateChanged);
  }

  void _onWindowStateChanged() {
    _loadMetadata();
  }

  @override
  void dispose() {
    final windowState = Provider.of<WindowState>(context, listen: false);
    windowState.removeListener(_onWindowStateChanged);
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    final windowState = Provider.of<WindowState>(context, listen: false);
    
    if (windowState.comparatorRawPath == null && windowState.comparatorAfterPath == null) {
      if (mounted) setState(() { _rawMetadata = null; _afterMetadata = null; });
      return;
    }

    setState(() => _isLoading = true);

    Map<String, String>? rawMeta;
    Map<String, String>? afterMeta;

    if (windowState.comparatorRawPath != null) {
      final meta = await ImageMetadataService().getMetadata(windowState.comparatorRawPath!);
      rawMeta = meta?.params;
    }

    if (windowState.comparatorAfterPath != null) {
      final meta = await ImageMetadataService().getMetadata(windowState.comparatorAfterPath!);
      afterMeta = meta?.params;
    }

    if (mounted) {
      setState(() {
        _rawMetadata = rawMeta;
        _afterMetadata = afterMeta;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rawMetadata == null && _afterMetadata == null) {
      return Center(
        child: Text(
          "No image metadata selected",
          style: TextStyle(color: colorScheme.outline),
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_rawMetadata != null) ...[
          _buildSectionHeader("RAW", colorScheme),
          _buildMetadataListItems(_rawMetadata!, l10n),
          const SizedBox(height: 24),
        ],
        if (_afterMetadata != null) ...[
          _buildSectionHeader("AFTER", colorScheme),
          _buildMetadataListItems(_afterMetadata!, l10n),
        ],
      ],
    );

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      child: content,
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold, 
          fontSize: 11, 
          letterSpacing: 1.2,
          color: colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildMetadataListItems(Map<String, String> metadata, AppLocalizations l10n) {
    return Column(
      children: metadata.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(
                entry.value,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              ),
              const Divider(height: 16),
            ],
          ),
        );
      }).toList(),
    );
  }
}
