import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_paths.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../services/llm/llm_debug_logger.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _outputDirController.text = await _db.getSetting('output_directory') ?? '';
    _isPortable = await AppPaths.isPortableMode();
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
        const SizedBox(height: 8),
        if (!Platform.isIOS)
          _buildOutputDirectoryTile(appState, l10n),
      ],
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
            String? path = await FilePicker.platform.getDirectoryPath();
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
