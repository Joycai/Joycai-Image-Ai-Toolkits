import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_file.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/llm_service.dart';
import '../../state/app_state.dart';
import 'chat_model_selector.dart';
import 'collapsible_card.dart';
import 'markdown_editor.dart';

class AIPromptRefiner extends StatefulWidget {
  final String initialPrompt;
  final List<AppFile> selectedImages;
  final Function(String) onApply;

  const AIPromptRefiner({
    super.key,
    required this.initialPrompt,
    required this.selectedImages,
    required this.onApply,
  });

  @override
  State<AIPromptRefiner> createState() => _AIPromptRefinerState();
}

class _AIPromptRefinerState extends State<AIPromptRefiner> {
  late TextEditingController _currentPromptCtrl;
  final TextEditingController _refinedPromptCtrl = TextEditingController();
  
  List<SystemPrompt> _allSysPrompts = [];
  List<SystemPrompt> _filteredSysPrompts = [];
  List<PromptTag> _tags = [];
  
  int? _selectedModelPk;
  int? _selectedTagId;
  String? _selectedSysPrompt;
  bool _isRefining = false;
  bool _isLoadingData = true;
  bool _isSettingsExpanded = true;

  @override
  void initState() {
    super.initState();
    _currentPromptCtrl = TextEditingController(text: widget.initialPrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _currentPromptCtrl.dispose();
    _refinedPromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final refinerPrompts = await appState.getSystemPrompts(type: 'refiner');
      final tags = await appState.getPromptTags();

      if (mounted) {
        setState(() {
          _allSysPrompts = refinerPrompts;
          _tags = tags;
          _applyFilter();
          
          if (appState.chatModels.isNotEmpty) {
            _selectedModelPk = appState.chatModels.first.id;
          }
          if (_filteredSysPrompts.isNotEmpty) _selectedSysPrompt = _filteredSysPrompts.first.content;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
  }

  void _applyFilter() {
    if (_selectedTagId == null) {
      _filteredSysPrompts = _allSysPrompts;
    } else {
      _filteredSysPrompts = _allSysPrompts.where((p) => p.tags.any((t) => t.id == _selectedTagId)).toList();
    }
    
    // Ensure selected prompt is still in the filtered list
    if (_selectedSysPrompt != null && !_filteredSysPrompts.any((p) => p.content == _selectedSysPrompt)) {
      _selectedSysPrompt = _filteredSysPrompts.isNotEmpty ? _filteredSysPrompts.first.content : null;
    }
  }

  Future<void> _refine() async {
    final l10n = AppLocalizations.of(context)!;
    if (_selectedModelPk == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.noModelsConfigured),
            action: SnackBarAction(
              label: l10n.settings,
              onPressed: () {
                final appState = Provider.of<AppState>(context, listen: false);
                appState.navigateToScreen(6); // Settings screen index
              },
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _isRefining = true;
      _refinedPromptCtrl.clear();
    });

    try {
      final attachments = widget.selectedImages.map((f) => 
        LLMAttachment.fromFile(File(f.path), 'image/jpeg')
      ).toList();

      final response = await LLMService().request(
        modelIdentifier: _selectedModelPk!,
        useStream: false,
        messages: [
          if (_selectedSysPrompt != null)
            LLMMessage(role: LLMRole.system, content: _selectedSysPrompt!),
          LLMMessage(
            role: LLMRole.user, 
            content: _currentPromptCtrl.text,
            attachments: attachments,
          ),
        ],
      );

      if (mounted) {
        setState(() {
          _refinedPromptCtrl.text = response.text;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.refineFailed(e.toString())))
        );
      }
    } finally {
      if (mounted) setState(() => _isRefining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 750;
        final colorScheme = Theme.of(context).colorScheme;

        return Consumer<AppState>(
          builder: (context, appState, child) => Container(
            color: colorScheme.surface,
            padding: EdgeInsets.all(isNarrow ? 12 : 24),
            child: _isLoadingData 
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNarrow) ...[
                       // Mobile: Scrollable content (Header + Settings + Input + Output)
                       Expanded(
                         child: SingleChildScrollView(
                           padding: const EdgeInsets.only(bottom: 16),
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               _buildHeader(l10n, colorScheme),
                               const SizedBox(height: 24),
                               _buildSettings(l10n, colorScheme, isNarrow, appState),
                               const SizedBox(height: 16),
                               _buildInputSection(l10n, appState, isNarrow),
                               const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(child: Icon(Icons.arrow_downward_rounded, color: Colors.grey)),
                                ),
                               _buildOutputSection(l10n, appState, isNarrow),
                             ],
                           ),
                         ),
                       ),
                       // Mobile: Fixed Action Bar
                       _buildActionBar(l10n, colorScheme),
                    ] else ...[
                       // Desktop: Fixed Header/Settings/Action, Expanded Content
                       _buildHeader(l10n, colorScheme),
                       const SizedBox(height: 24),
                       _buildSettings(l10n, colorScheme, isNarrow, appState),
                       const SizedBox(height: 16),
                       Expanded(
                         child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _buildInputSection(l10n, appState, isNarrow)),
                              const SizedBox(width: 24),
                              const Center(
                                child: Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 32),
                              ),
                              const SizedBox(width: 24),
                              Expanded(child: _buildOutputSection(l10n, appState, isNarrow)),
                            ],
                         ),
                       ),
                       const SizedBox(height: 16),
                       _buildActionBar(l10n, colorScheme),
                    ]
                  ],
                ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(AppLocalizations l10n, ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.auto_fix_high, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.promptOptimizer,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              l10n.refinerIntro,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettings(AppLocalizations l10n, ColorScheme colorScheme, bool isNarrow, AppState appState) {
    return CollapsibleCard(
      title: l10n.config,
      isExpanded: _isSettingsExpanded,
      onToggle: () => setState(() => _isSettingsExpanded = !_isSettingsExpanded),
      content: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: isNarrow
            ? Column(
                children: [
                  _buildModelSelector(l10n, appState),
                  const SizedBox(height: 12),
                  _buildTagSelector(l10n),
                  const SizedBox(height: 12),
                  _buildSysPromptSelector(l10n),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 2, child: _buildModelSelector(l10n, appState)),
                  const SizedBox(width: 16),
                  Expanded(flex: 1, child: _buildTagSelector(l10n)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildSysPromptSelector(l10n)),
                ],
              ),
      ),
    );
  }

  Widget _buildActionBar(AppLocalizations l10n, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_isRefining)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          FilledButton.icon(
            onPressed: _isRefining ? null : _refine,
            icon: const Icon(Icons.auto_fix_high),
            label: Text(l10n.refine),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _refinedPromptCtrl.text.isEmpty ? null : () {
              widget.onApply(_refinedPromptCtrl.text);
              // Ensure we notify user
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.taskSubmitted)),
              );
            },
            icon: const Icon(Icons.check),
            label: Text(l10n.applyToWorkbench),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.tertiary,
              foregroundColor: colorScheme.onTertiary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection(AppLocalizations l10n, AppState appState, bool isNarrow) {
    final editor = MarkdownEditor(
      controller: _currentPromptCtrl,
      label: l10n.roughPrompt,
      isMarkdown: appState.isMarkdownRefinerSource,
      onMarkdownChanged: (v) => appState.setIsMarkdownRefinerSource(v),
      maxLines: isNarrow ? 8 : 20, // Smaller fixed height for mobile
      initiallyPreview: false,
      expand: !isNarrow, // Only expand on desktop
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selectedImages.isNotEmpty) ...[
          Text(l10n.selectedCount(widget.selectedImages.length), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.selectedImages.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final image = widget.selectedImages[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image(
                    image: image.imageProvider,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (isNarrow) 
          editor 
        else 
          Expanded(child: editor),
      ],
    );
  }

  Widget _buildOutputSection(AppLocalizations l10n, AppState appState, bool isNarrow) {
    final editor = MarkdownEditor(
      controller: _refinedPromptCtrl,
      label: l10n.optimizedPrompt,
      isMarkdown: appState.isMarkdownRefinerTarget,
      onMarkdownChanged: (v) => appState.setIsMarkdownRefinerTarget(v),
      maxLines: isNarrow ? 12 : 20, // Smaller fixed height for mobile
      initiallyPreview: true,
      isRefined: true,
      expand: !isNarrow,
    );

    return Column(
      children: [
        if (isNarrow) editor else Expanded(child: editor),
      ],
    );
  }

  Widget _buildModelSelector(AppLocalizations l10n, AppState appState) {
    return ChatModelSelector(
      selectedModelId: _selectedModelPk,
      label: l10n.refinerModel,
      onChanged: (v) => setState(() => _selectedModelPk = v),
    );
  }

  Widget _buildTagSelector(AppLocalizations l10n) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: l10n.tag,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _selectedTagId,
          isDense: true,
          onChanged: (v) {
            setState(() {
              _selectedTagId = v;
              _applyFilter();
            });
          },
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(l10n.catAll)),
            ..._tags.map((t) => DropdownMenuItem<int?>(
              value: t.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(backgroundColor: Color(t.color), radius: 6),
                  const SizedBox(width: 8),
                  Text(t.name, overflow: TextOverflow.ellipsis),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSysPromptSelector(AppLocalizations l10n) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: l10n.systemPrompt,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSysPrompt,
          isDense: true,
          onChanged: (v) => setState(() => _selectedSysPrompt = v),
          items: _filteredSysPrompts.map((p) => DropdownMenuItem(
            value: p.content, 
            child: Text(p.title, overflow: TextOverflow.ellipsis)
          )).toList(),
        ),
      ),
    );
  }
}
