import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_file.dart';
import '../../models/llm_channel.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/llm_service.dart';
import '../../state/app_state.dart';
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
    if (_selectedModelPk == null) return;
    final l10n = AppLocalizations.of(context)!;

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
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 900;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Consumer<AppState>(
        builder: (context, appState, child) => Container(
          width: isNarrow ? size.width * 0.95 : 1000,
          height: isNarrow ? size.height * 0.9 : 700,
          padding: EdgeInsets.all(isNarrow ? 12 : 24),
          child: _isLoadingData 
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_fix_high, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.aiPromptRefiner, 
                          style: isNarrow ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.headlineSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (isNarrow) ...[
                    _buildModelSelector(l10n, appState),
                    const SizedBox(height: 8),
                    _buildTagSelector(l10n),
                    const SizedBox(height: 8),
                    _buildSysPromptSelector(l10n),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildModelSelector(l10n, appState),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: _buildTagSelector(l10n),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildSysPromptSelector(l10n),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  
                  // Prompts Section
                  Expanded(
                    child: isNarrow 
                      ? SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              MarkdownEditor(
                                controller: _currentPromptCtrl,
                                label: l10n.currentPrompt,
                                isMarkdown: appState.isMarkdownRefinerSource,
                                onMarkdownChanged: (v) => appState.setIsMarkdownRefinerSource(v),
                                maxLines: 8,
                                initiallyPreview: false,
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0),
                                child: Center(child: Icon(Icons.arrow_downward_rounded, color: Colors.grey)),
                              ),
                              MarkdownEditor(
                                controller: _refinedPromptCtrl,
                                label: l10n.refinedPrompt,
                                isMarkdown: appState.isMarkdownRefinerTarget,
                                onMarkdownChanged: (v) => appState.setIsMarkdownRefinerTarget(v),
                                maxLines: 12,
                                initiallyPreview: true,
                                isRefined: true,
                              ),
                            ],
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: MarkdownEditor(
                                controller: _currentPromptCtrl,
                                label: l10n.currentPrompt,
                                isMarkdown: appState.isMarkdownRefinerSource,
                                onMarkdownChanged: (v) => appState.setIsMarkdownRefinerSource(v),
                                maxLines: 20,
                                initiallyPreview: false,
                                expand: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Center(
                              child: Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 32),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: MarkdownEditor(
                                controller: _refinedPromptCtrl,
                                label: l10n.refinedPrompt,
                                isMarkdown: appState.isMarkdownRefinerTarget,
                                onMarkdownChanged: (v) => appState.setIsMarkdownRefinerTarget(v),
                                maxLines: 20,
                                initiallyPreview: true,
                                isRefined: true,
                                expand: true,
                              ),
                            ),
                          ],
                        ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Actions
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.cancel),
                      ),
                      FilledButton.icon(
                        onPressed: _isRefining ? null : _refine,
                        icon: _isRefining 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_fix_high),
                        label: Text(l10n.refine),
                      ),
                      FilledButton(
                        onPressed: _refinedPromptCtrl.text.isEmpty ? null : () {
                          widget.onApply(_refinedPromptCtrl.text);
                          Navigator.pop(context);
                        },
                        child: Text(l10n.apply),
                      ),
                    ],
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildModelSelector(AppLocalizations l10n, AppState appState) {
    return DropdownButtonFormField<int>(
      initialValue: _selectedModelPk,
      decoration: InputDecoration(
        labelText: l10n.refinerModel,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: appState.chatModels.map((m) {
        final channel = appState.allChannels.cast<LLMChannel?>().firstWhere((c) => c?.id == m.channelId, orElse: () => null);
        return DropdownMenuItem(
          value: m.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (channel != null && channel.tag != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Color(channel.tagColor ?? 0xFF607D8B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    channel.tag!,
                    style: TextStyle(
                      fontSize: 9, 
                      color: Color(channel.tagColor ?? 0xFF607D8B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Text(m.modelName, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }).toList(),
      onChanged: (v) => setState(() => _selectedModelPk = v),
    );
  }

  Widget _buildTagSelector(AppLocalizations l10n) {
    return DropdownButtonFormField<int?>(
      initialValue: _selectedTagId,
      decoration: InputDecoration(
        labelText: l10n.tag,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
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
      onChanged: (v) {
        setState(() {
          _selectedTagId = v;
          _applyFilter();
        });
      },
    );
  }

  Widget _buildSysPromptSelector(AppLocalizations l10n) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSysPrompt,
      decoration: InputDecoration(
        labelText: l10n.systemPrompt,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: _filteredSysPrompts.map((p) => DropdownMenuItem(
        value: p.content, 
        child: Text(p.title, overflow: TextOverflow.ellipsis)
      )).toList(),
      onChanged: (v) => setState(() => _selectedSysPrompt = v),
    );
  }
}
