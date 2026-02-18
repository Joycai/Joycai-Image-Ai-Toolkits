import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../services/database_service.dart';
import '../../services/llm/llm_service.dart';
import '../../services/llm/llm_types.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../widgets/chat_model_selector.dart';

class AiRenameDialog extends StatefulWidget {
  const AiRenameDialog({super.key});

  @override
  State<AiRenameDialog> createState() => _AiRenameDialogState();
}

class _AiRenameDialogState extends State<AiRenameDialog> {
  final TextEditingController _instructionController = TextEditingController();
  final DatabaseService _db = DatabaseService();
  bool _isProcessing = false;
  int? _selectedModelDbId;
  List<Map<String, String>> _proposedRenames = [];
  Map<String, String> _conflicts = {};
  StreamSubscription? _taskSubscription;
  String? _currentTaskId;

  @override
  void initState() {
    super.initState();
    _loadLastSettings();
    
    // Setup task subscription
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final taskService = Provider.of<TaskQueueService>(context, listen: false);
      _taskSubscription = taskService.eventStream.listen((event) {
        if (_currentTaskId == null || event.taskId != _currentTaskId) return;

        if (event.type == TaskEventType.textChunk) {
          _handleTaskJsonUpdate(event.data as String);
        } else if (event.type == TaskEventType.statusChanged) {
          if (event.data == TaskStatus.completed || event.data == TaskStatus.failed || event.data == TaskStatus.cancelled) {
            if (mounted) setState(() => _isProcessing = false);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    _instructionController.dispose();
    super.dispose();
  }

  void _handleTaskJsonUpdate(String jsonText) {
    try {
      String cleanJson = jsonText.trim();
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7, cleanJson.length - 3).trim();
      } else if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3, cleanJson.length - 3).trim();
      }

      final List<dynamic> suggestions = jsonDecode(cleanJson);
      final List<Map<String, String>> proposed = [];

      for (var s in suggestions) {
        proposed.add({
          'path': s['path'] as String,
          'old_name': p.basename(s['path'] as String),
          'new_name': s['new_name'] as String,
        });
      }

      _detectConflicts(proposed).then((_) {
        if (mounted) {
          setState(() {
            _proposedRenames = proposed;
          });
        }
      });
    } catch (_) {
      // JSON might be partial or invalid during streaming, ignore
    }
  }

  Future<void> _loadLastSettings() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final lastModelId = await appState.getSetting('last_ai_rename_model_id');
    final lastInstructions = await appState.getSetting('last_ai_rename_instructions');
    
    if (mounted) {
      setState(() {
        _selectedModelDbId = int.tryParse(lastModelId ?? '') ?? int.tryParse(appState.lastSelectedModelId ?? '');
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
    final fileBrowserState = appState.fileBrowserState;
    final selectedFiles = fileBrowserState.selectedFiles.toList();
    final l10n = AppLocalizations.of(context)!;

    if (_selectedModelDbId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.noModelsConfigured),
          action: SnackBarAction(
            label: l10n.settings,
            onPressed: () {
              Navigator.pop(context); // Close dialog
              appState.navigateToScreen(6); // Settings screen index
            },
          ),
        ),
      );
      return;
    }

    if (_instructionController.text.isEmpty) return;

    // Save current settings as last used
    final db = DatabaseService();
    db.saveSetting('last_ai_rename_model_id', _selectedModelDbId.toString());
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

      final String instructions = _instructionController.text.trim();
      String prompt;

      // Intelligent prompt wrapping: 
      // If the instruction already looks like a "Pro" prompt (contains # Role or # Task),
      // we inject context but avoid double wrapping the persona.
      if (instructions.contains('# Role') || instructions.contains('# Task')) {
        prompt = """
$instructions

Files to rename (Context):
${jsonEncode(filesData)}
""";
      } else {
        prompt = """
You are a professional file renaming assistant. 
Instructions: $instructions

Files to rename:
${jsonEncode(filesData)}

Output ONLY a valid JSON array of objects, where each object has 'path' and 'new_name' keys.
Example: [{"path": "...", "new_name": "..."}]
Do not include any other text or markdown formatting.
""";
      }

      final response = await LLMService().request(
        modelIdentifier: _selectedModelDbId,
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

      await _detectConflicts(proposed);

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _proposedRenames = proposed;
              _isProcessing = false;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isProcessing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
            );
          }
        });
      }
    }
  }

  Future<void> _detectConflicts(List<Map<String, String>> proposed) async {
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
      if (await File(newPath).exists() && !proposed.any((p) => p['path'] == newPath)) {
        conflicts[oldPath] = "File already exists on disk";
      }
    }
    _conflicts = conflicts;
  }

  Future<void> _applyRenames() async {
    if (_conflicts.isNotEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final appState = Provider.of<AppState>(context, listen: false);
    
    setState(() => _isProcessing = true);
    try {
      final List<Map<String, String>> filesData = appState.fileBrowserState.selectedFiles.map((f) => {
        'original_name': f.name,
        'path': f.path,
        'category': f.category.name,
      }).toList();

      final taskService = Provider.of<TaskQueueService>(context, listen: false);
      final taskId = const Uuid().v4();
      
      setState(() {
        _currentTaskId = taskId;
        _isProcessing = true; // Ensure UI reflects processing immediately
      });

      // Submit to queue
      await taskService.addTask(
        appState.fileBrowserState.selectedFiles.map((f) => f.path).toList(),
        _selectedModelDbId,
        {
          'instructions': _instructionController.text,
          'filesData': filesData,
        },
        type: TaskType.aiRename,
        useStream: false, 
        id: taskId,
      );
      
      if (mounted) {
        Navigator.pop(context);
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.taskSubmitted), backgroundColor: Colors.blue),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text("Failed to start task: $e"), backgroundColor: Colors.red),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final chatModels = appState.chatModels;
    // Safety check: ensure the selected PK actually exists in the current list of chat models
    final effectiveModelDbId = chatModels.any((m) => m.id == _selectedModelDbId) ? _selectedModelDbId : null;

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
              ChatModelSelector(
                selectedModelId: effectiveModelDbId,
                label: l10n.model,
                onChanged: (v) => setState(() => _selectedModelDbId = v),
              ),
              const SizedBox(height: 16),
              // Quick Templates Row
              Text(l10n.rulesInstructions, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickTemplateButton(
                      label: "General Smart", 
                      icon: Icons.auto_awesome, 
                      onTap: () async {
                        final templates = await _db.getSystemPrompts(type: 'rename');
                        final t = templates.firstWhere((e) => e.title.contains('General'), orElse: () => templates.first);
                        setState(() => _instructionController.text = t.content);
                      }
                    ),
                    const SizedBox(width: 8),
                    _buildQuickTemplateButton(
                      label: "Jellyfin TV Pro", 
                      icon: Icons.tv,
                      onTap: () async {
                        final templates = await _db.getSystemPrompts(type: 'rename');
                        final t = templates.firstWhere((e) => e.title.contains('Jellyfin TV Show Pro'), orElse: () => templates.first);
                        setState(() => _instructionController.text = t.content);
                      }
                    ),
                    const SizedBox(width: 8),
                    _buildQuickTemplateButton(
                      label: l10n.library, 
                      icon: Icons.library_books,
                      isLibrary: true,
                      onTap: _showTemplatePicker,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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

  Widget _buildQuickTemplateButton({
    required String label, 
    required IconData icon, 
    required VoidCallback onTap,
    bool isLibrary = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: isLibrary ? colorScheme.secondary : colorScheme.primary),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildPreviewList(ColorScheme colorScheme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_proposedRenames.length, (index) {
        final item = _proposedRenames[index];
        final hasConflict = _conflicts.containsKey(item['path']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) const Divider(),
            Padding(
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
            ),
          ],
        );
      }),
    );
  }
}
