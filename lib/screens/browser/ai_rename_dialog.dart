import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../services/database_service.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/llm_service.dart';
import '../../state/app_state.dart';

class AiRenameDialog extends StatefulWidget {
  const AiRenameDialog({super.key});

  @override
  State<AiRenameDialog> createState() => _AiRenameDialogState();
}

class _AiRenameDialogState extends State<AiRenameDialog> {
  final TextEditingController _instructionController = TextEditingController();
  final DatabaseService _db = DatabaseService();
  bool _isProcessing = false;
  int? _selectedModelPk;
  List<Map<String, String>> _proposedRenames = [];
  Map<String, String> _conflicts = {};

  @override
  void initState() {
    super.initState();
    _loadLastSettings();
  }

  Future<void> _loadLastSettings() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final lastModelId = await appState.getSetting('last_ai_rename_model_id');
    final lastInstructions = await appState.getSetting('last_ai_rename_instructions');
    
    if (mounted) {
      setState(() {
        _selectedModelPk = int.tryParse(lastModelId ?? '') ?? int.tryParse(appState.lastSelectedModelId ?? '');
        if (lastInstructions != null) {
          _instructionController.text = lastInstructions;
        }
      });
    }
  }

  Future<void> _showTemplatePicker() async {
    final l10n = AppLocalizations.of(context)!;
    
    final List<SystemPrompt> templates = await _db.getSystemPrompts(type: 'rename');
    
    if (!mounted) return;

    final SystemPrompt? selected = await showDialog<SystemPrompt>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.selectRenameTemplate),
        content: SizedBox(
          width: 400,
          child: templates.isEmpty 
            ? Center(child: Text(l10n.noPromptsSaved))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final t = templates[index];
                  return ListTile(
                    title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(t.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    onTap: () => Navigator.pop(context, t),
                  );
                },
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        ],
      ),
    );

    if (selected != null) {
      setState(() {
        _instructionController.text = selected.content;
      });
    }
  }

  Future<void> _generateSuggestions() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final browserState = appState.browserState;
    final selectedFiles = browserState.selectedFiles.toList();

    if (_selectedModelPk == null || _instructionController.text.isEmpty) return;

    // Save current settings as last used
    final db = DatabaseService();
    db.saveSetting('last_ai_rename_model_id', _selectedModelPk.toString());
    db.saveSetting('last_ai_rename_instructions', _instructionController.text);

    setState(() {
      _isProcessing = true;
      _proposedRenames = [];
      _conflicts = {};
    });

    try {
      // Prepare the files list for the LLM
      final List<Map<String, String>> filesData = selectedFiles.map((f) => {
        'original_name': f.name,
        'path': f.path,
        'category': f.category.name,
      }).toList();

      final prompt = """
You are a professional file renaming assistant. 
Instructions: ${_instructionController.text}

Files to rename:
${jsonEncode(filesData)}

Output ONLY a valid JSON array of objects, where each object has 'path' and 'new_name' keys.
Example: [{"path": "...", "new_name": "..."}]
Do not include any other text or markdown formatting.
""";

      final response = await LLMService().request(
        modelIdentifier: _selectedModelPk,
        messages: [LLMMessage(role: LLMRole.user, content: prompt)],
        useStream: false,
      );

      // Parse JSON from response
      String jsonText = response.text.trim();
      if (jsonText.startsWith('```json')) {
        jsonText = jsonText.substring(7, jsonText.length - 3).trim();
      } else if (jsonText.startsWith('```')) {
        jsonText = jsonText.substring(3, jsonText.length - 3).trim();
      }

      final List<dynamic> suggestions = jsonDecode(jsonText);
      final List<Map<String, String>> proposed = [];

      for (var s in suggestions) {
        proposed.add({
          'path': s['path'] as String,
          'old_name': p.basename(s['path'] as String),
          'new_name': s['new_name'] as String,
        });
      }

      _detectConflicts(proposed);

      if (mounted) {
        setState(() {
          _proposedRenames = proposed;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _detectConflicts(List<Map<String, String>> proposed) {
    final Map<String, String> conflicts = {};
    final Set<String> targetNames = {};
    
    for (var item in proposed) {
      final newName = item['new_name']!;
      final oldPath = item['path']!;
      final dir = p.dirname(oldPath);
      final newPath = p.join(dir, newName);

      // Conflict 1: Multiple files target the same name
      if (targetNames.contains(newPath)) {
        conflicts[oldPath] = "Duplicate target name";
      }
      targetNames.add(newPath);

      // Conflict 2: Target name already exists on disk and is not one of our source files
      if (File(newPath).existsSync() && !proposed.any((p) => p['path'] == newPath)) {
        conflicts[oldPath] = "File already exists on disk";
      }
    }
    _conflicts = conflicts;
  }

  Future<void> _applyRenames() async {
    if (_conflicts.isNotEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    setState(() => _isProcessing = true);
    try {
      for (var item in _proposedRenames) {
        final oldFile = File(item['path']!);
        final newPath = p.join(p.dirname(item['path']!), item['new_name']!);
        if (oldFile.existsSync()) {
          await oldFile.rename(newPath);
        }
      }
      
      if (mounted) {
        Navigator.pop(context);
        Provider.of<AppState>(context, listen: false).browserState.refresh();
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.renameSuccess), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.renameFailed(e.toString())), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final chatModels = appState.chatModels;
    // Safety check: ensure the selected PK actually exists in the current list of chat models
    final effectiveModelPk = chatModels.any((m) => m.id == _selectedModelPk) ? _selectedModelPk : null;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_fix_high, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.aiBatchRename, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          minWidth: Responsive.isMobile(context) ? 0 : 600,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: effectiveModelPk,
                decoration: InputDecoration(labelText: l10n.model, border: const OutlineInputBorder()),
                items: chatModels.map((m) => DropdownMenuItem(
                  value: m.id,
                  child: Text(m.modelName),
                )).toList(),
                onChanged: (v) => setState(() => _selectedModelPk = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(l10n.rulesInstructions, style: const TextStyle(fontWeight: FontWeight.bold))),
                  TextButton.icon(
                    onPressed: _showTemplatePicker,
                    icon: const Icon(Icons.library_books, size: 16),
                    label: Text(l10n.library, style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _instructionController,
                decoration: const InputDecoration(
                  hintText: "e.g. Normalize to S01E01 format for Jellyfin",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _generateSuggestions,
                  icon: _isProcessing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.psychology),
                  label: Text(l10n.generateSuggestions),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              if (_proposedRenames.isEmpty)
                SizedBox(
                  height: 100,
                  child: Center(child: Text(l10n.noSuggestions, style: TextStyle(color: colorScheme.outline))),
                )
              else
                _buildPreviewList(colorScheme, l10n),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: (_proposedRenames.isEmpty || _conflicts.isNotEmpty || _isProcessing) ? null : _applyRenames,
          child: Text(l10n.applyRenames),
        ),
      ],
    );
  }

  Widget _buildPreviewList(ColorScheme colorScheme, AppLocalizations l10n) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _proposedRenames.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final item = _proposedRenames[index];
        final hasConflict = _conflicts.containsKey(item['path']);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item['old_name']!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.arrow_forward, size: 12, color: Colors.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item['new_name']!, 
                      style: TextStyle(
                        fontSize: 13, 
                        fontWeight: FontWeight.bold,
                        color: hasConflict ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                  if (hasConflict) 
                    Tooltip(message: _conflicts[item['path']], child: const Icon(Icons.error_outline, color: Colors.red, size: 16))
                  else
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
