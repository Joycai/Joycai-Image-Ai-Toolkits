import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../state/workbench_ui_state.dart';

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
  WorkbenchUIState? _workbenchUIState;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_workbenchUIState == null) {
      _workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
      _workbenchUIState!.addListener(_onWorkbenchUIStateChanged);
    }
  }

  void _onWorkbenchUIStateChanged() {
    _loadMetadata();
  }

  @override
  void dispose() {
    _workbenchUIState?.removeListener(_onWorkbenchUIStateChanged);
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    // Access state via stored reference if available, or provider (safely)
    final state = _workbenchUIState ?? Provider.of<WorkbenchUIState>(context, listen: false);
    
    if (state.comparatorRawPath == null && state.comparatorAfterPath == null) {
      if (mounted) setState(() { _rawMetadata = null; _afterMetadata = null; });
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    Map<String, String>? rawMeta;
    Map<String, String>? afterMeta;

    if (state.comparatorRawPath != null) {
      final meta = await ImageMetadataService().getMetadata(state.comparatorRawPath!);
      rawMeta = meta?.params;
    }

    if (state.comparatorAfterPath != null) {
      final meta = await ImageMetadataService().getMetadata(state.comparatorAfterPath!);
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
          l10n.metadataSelectedNone,
          style: TextStyle(color: colorScheme.outline),
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_rawMetadata != null) ...[
          _buildSectionHeader(l10n.labelRaw, colorScheme),
          _buildMetadataListItems(_rawMetadata!, l10n),
          const SizedBox(height: 24),
        ],
        if (_afterMetadata != null) ...[
          _buildSectionHeader(l10n.labelAfter, colorScheme),
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
