import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_paths.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/llm/llm_debug_logger.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_section.dart';

class ApplicationSection extends StatefulWidget {
  const ApplicationSection({super.key});

  @override
  State<ApplicationSection> createState() => _ApplicationSectionState();
}

class _ApplicationSectionState extends State<ApplicationSection> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _outputDirController = TextEditingController();
  bool _isPortable = false;
  String? _kbPath;
  KbStatus _kbStatus = KbStatus.notSet;
  int _assistantRetention = PromptOptimizerAgent.defaultRetention;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _outputDirController.text = await _db.getSetting('output_directory') ?? '';
    _isPortable = await AppPaths.isPortableMode();
    _kbPath = await KnowledgeBaseService().getRoot();
    _kbStatus = await KnowledgeBaseService().validate(_kbPath);
    _assistantRetention = int.tryParse(
            await _db.getSetting(PromptOptimizerAgent.retentionSettingKey) ?? '') ??
        PromptOptimizerAgent.defaultRetention;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);

    return AppSection(
      title: l10n.application,
      children: [
        SwitchListTile(
          title: Text(l10n.enableNotifications),
          value: appState.notificationsEnabled,
          onChanged: (v) => appState.setNotificationsEnabled(v),
        ),
        const SizedBox(height: 8),
        Column(
          children: [
            SwitchListTile(
              title: Text(l10n.enableApiDebug),
              subtitle: Text(l10n.apiDebugDesc),
              value: appState.enableApiDebug,
              onChanged: (v) => appState.setEnableApiDebug(v),
            ),
            if (appState.enableApiDebug)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => LLMDebugLogger.openLogFolder(),
                    icon: const Icon(Icons.folder_zip_outlined, size: 18),
                    label: Text(l10n.openLogFolder),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          SwitchListTile(
            title: Text(l10n.portableMode),
            subtitle: Text(l10n.portableModeDesc),
            value: _isPortable,
            onChanged: (v) async {
              await AppPaths.setPortableMode(v);
              setState(() => _isPortable = v);
              if (mounted) {
                _showRestartDialog(l10n);
              }
            },
          ),
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          const SizedBox(height: 8),
        if (!Platform.isIOS)
          _buildOutputDirectoryTile(appState, l10n),
        if (!Platform.isIOS) const SizedBox(height: 8),
        if (!Platform.isIOS)
          _buildKnowledgeBaseTile(l10n),
        const SizedBox(height: 8),
        ListTile(
          title: Text(l10n.assistantRetention),
          subtitle: Text(l10n.assistantRetentionDesc),
          shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          trailing: DropdownButton<int>(
            value: const [10, 20, 50, 100].contains(_assistantRetention) ? _assistantRetention : 20,
            underline: const SizedBox.shrink(),
            items: const [10, 20, 50, 100]
                .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                .toList(),
            onChanged: (v) async {
              if (v == null) return;
              await _db.saveSetting(PromptOptimizerAgent.retentionSettingKey, '$v');
              setState(() => _assistantRetention = v);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKnowledgeBaseTile(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final String subtitle;
    final bool warn;
    switch (_kbStatus) {
      case KbStatus.ok:
        subtitle = _kbPath!;
        warn = false;
      case KbStatus.notSet:
        subtitle = l10n.notSet;
        warn = false;
      case KbStatus.missingDir:
        subtitle = l10n.kbInvalidDir;
        warn = true;
      case KbStatus.missingEntry:
        subtitle = l10n.kbMissingEntry;
        warn = true;
    }
    return ListTile(
      title: Text(l10n.knowledgeBaseFolder),
      subtitle: Text(
        subtitle,
        style: warn ? TextStyle(color: colorScheme.error) : null,
      ),
      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_kbPath != null)
            IconButton(
              tooltip: l10n.kbOpenFolder,
              icon: const Icon(Icons.open_in_new),
              onPressed: () => FileUtils.openPath(_kbPath!),
            ),
          const Icon(Icons.folder_open),
        ],
      ),
      onTap: () async {
        String? path = await FilePicker.getDirectoryPath();
        if (path != null) {
          await KnowledgeBaseService().setRoot(path);
          final status = await KnowledgeBaseService().validate(path);
          if (mounted) {
            setState(() {
              _kbPath = path;
              _kbStatus = status;
            });
          }
        }
      },
    );
  }

  Widget _buildOutputDirectoryTile(AppState appState, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(l10n.outputDirectory),
          subtitle: Text(_outputDirController.text.isEmpty ? l10n.notSet : _outputDirController.text),
          trailing: const Icon(Icons.folder_open),
          shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          onTap: () async {
            String? path = await FilePicker.getDirectoryPath();
            if (path != null) {
              setState(() => _outputDirController.text = path);
              await appState.updateOutputDirectory(path);
            }
          },
        ),
      ],
    );
  }

  void _showRestartDialog(AppLocalizations l10n) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.restartRequired),
        content: Text(l10n.restartMessage),
        actions: [
          FilledButton(
            onPressed: () => exit(0),
            child: Text(l10n.exit),
          ),
        ],
      ),
    );
  }
}
