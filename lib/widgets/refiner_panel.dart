import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/llm_service.dart';

class AIPromptRefiner extends StatefulWidget {
  final String initialPrompt;
  final List<File> selectedImages;
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
  final DatabaseService _db = DatabaseService();
  late TextEditingController _currentPromptCtrl;
  final TextEditingController _refinedPromptCtrl = TextEditingController();
  
  List<Map<String, dynamic>> _models = [];
  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _sysPrompts = [];
  
  int? _selectedModelPk;
  String? _selectedSysPrompt;
  bool _isRefining = false;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _currentPromptCtrl = TextEditingController(text: widget.initialPrompt);
    _loadData();
  }

  @override
  void dispose() {
    _currentPromptCtrl.dispose();
    _refinedPromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final allModels = await _db.getModels();
      final channels = await _db.getChannels();
      final refinerModels = allModels.where((m) => 
        m['tag'] == 'chat' || m['tag'] == 'multimodal'
      ).toList();
      
      final allPrompts = await _db.getPrompts();
      final allTags = await _db.getPromptTags();
      final refinerTag = allTags.cast<Map<String, dynamic>?>().firstWhere((t) => t?['is_system'] == 1, orElse: () => null);
      
      final refinerPrompts = allPrompts.where((p) => 
        p['tag_id'] == refinerTag?['id']
      ).toList();

      if (mounted) {
        setState(() {
          _models = refinerModels;
          _channels = channels;
          _sysPrompts = refinerPrompts;
          if (_models.isNotEmpty) _selectedModelPk = _models.first['id'] as int;
          if (_sysPrompts.isNotEmpty) _selectedSysPrompt = _sysPrompts.first['content'];
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
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
        LLMAttachment.fromFile(f, 'image/jpeg')
      ).toList();

      final stream = LLMService().requestStream(
        modelIdentifier: _selectedModelPk!,
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

      String accumulatedText = "";
      await for (final chunk in stream) {
        if (chunk.textPart != null) {
          accumulatedText += chunk.textPart!;
          if (mounted) {
            setState(() {
              _refinedPromptCtrl.text = accumulatedText;
            });
          }
        }
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1000,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: _isLoadingData 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_fix_high, color: Colors.blue),
                    const SizedBox(width: 12),
                    Text(l10n.aiPromptRefiner, style: Theme.of(context).textTheme.headlineSmall),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Config Section
                Row(
                  children: [
                    Expanded(
                      child: _buildModelSelector(l10n),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildSysPromptSelector(l10n),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Prompts Section
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Source
                      Expanded(
                        child: _buildPromptInput(
                          title: l10n.currentPrompt,
                          controller: _currentPromptCtrl,
                          readOnly: false,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Arrow
                      const Center(
                        child: Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 32),
                      ),
                      const SizedBox(width: 16),
                      // Refined
                      Expanded(
                        child: _buildPromptInput(
                          title: l10n.refinedPrompt,
                          controller: _refinedPromptCtrl,
                          readOnly: true,
                          isRefined: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isRefining ? null : _refine,
                      icon: _isRefining 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_fix_high),
                      label: Text(l10n.refine),
                    ),
                    const SizedBox(width: 12),
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
    );
  }

  Widget _buildModelSelector(AppLocalizations l10n) {
    return DropdownButtonFormField<int>(
      initialValue: _selectedModelPk,
      decoration: InputDecoration(
        labelText: l10n.refinerModel,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: _models.map((m) {
        final channel = _channels.firstWhere((c) => c['id'] == m['channel_id'], orElse: () => {});
        return DropdownMenuItem(
          value: m['id'] as int,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (channel.isNotEmpty && channel['tag'] != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Color(channel['tag_color'] ?? 0xFF607D8B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    channel['tag'],
                    style: TextStyle(
                      fontSize: 9, 
                      color: Color(channel['tag_color'] ?? 0xFF607D8B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Text(m['model_name'], overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }).toList(),
      onChanged: (v) => setState(() => _selectedModelPk = v),
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
      items: _sysPrompts.map((p) => DropdownMenuItem(
        value: p['content'] as String, 
        child: Text(p['title'], overflow: TextOverflow.ellipsis)
      )).toList(),
      onChanged: (v) => setState(() => _selectedSysPrompt = v),
    );
  }

  Widget _buildPromptInput({
    required String title,
    required TextEditingController controller,
    required bool readOnly,
    bool isRefined = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            readOnly: readOnly,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              fillColor: isRefined ? Colors.grey.withValues(alpha: 0.05) : null,
              filled: isRefined,
            ),
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
      ],
    );
  }
}
