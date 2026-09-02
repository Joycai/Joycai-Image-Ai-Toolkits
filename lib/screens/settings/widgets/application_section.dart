import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_paths.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_model.dart';
import '../../../services/database_service.dart';
import '../../../services/gpu_preference_service.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/llm/llm_debug_logger.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_section.dart';
import '../../../widgets/app_setting_row.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/searchable_picker.dart';

/// Wide enough for the longest value either of the assistant rows offers
/// ("100", "100%") beside the chevron; the row's trailing slot is unbounded,
/// and an expanded dropdown needs a width from somewhere.
const double _settingDropdownWidth = 112;

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

  /// Offered summary thresholds. Nothing above 80%: the headroom above the
  /// threshold is what lets the assistant read a knowledge file in one piece
  /// mid-turn, and compaction only reclaims it at the next turn boundary.
  static const List<double> _contextRatios = [0.4, 0.5, 0.6, 0.7, 0.8];
  double _assistantContextRatio = PromptOptimizerAgent.defaultContextRatio;
  bool _kbSubAgentEnabled = false;
  int? _kbSubAgentModelId;
  List<LLMModel> _kbSubAgentModels = const [];

  // The registry is the source of truth (shared with the Windows Settings
  // page), so this is section-local state rather than an AppState field.
  final GpuPreferenceService _gpuPreference = GpuPreferenceService();
  bool _gpuHighPerformance = false;

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
    _assistantContextRatio = double.tryParse(
            await _db.getSetting(PromptOptimizerAgent.contextRatioSettingKey) ?? '') ??
        PromptOptimizerAgent.defaultContextRatio;
    _kbSubAgentEnabled =
        (await _db.getSetting(PromptOptimizerAgent.kbSubAgentSettingKey) ??
                'false') ==
            'true';
    _kbSubAgentModelId = int.tryParse(
        await _db.getSetting(PromptOptimizerAgent.kbSubAgentModelSettingKey) ??
            '');
    // Chat-capable models only: image/video generators cannot run the
    // research tool loop.
    _kbSubAgentModels = [
      for (final m in await _db.getModels())
        if (m.tag != 'image' && m.tag != 'video') m,
    ];
    _gpuHighPerformance = await _gpuPreference.isHighPerformanceSet();
    if (mounted) setState(() {});
  }

  Future<void> _setGpuHighPerformance(bool value) async {
    setState(() => _gpuHighPerformance = value);
    final ok = await _gpuPreference.setHighPerformance(value);
    if (!ok && mounted) {
      // The registry write failed — reflect reality rather than the wish.
      setState(() => _gpuHighPerformance = !value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);

    // No title — the pane header already says 「应用」. `gap: 10` is `D1`'s
    // spacing between rows, and replaces the SizedBoxes each row used to carry
    // (which had to be repeated inside every platform conditional, and were
    // duly forgotten in two of them).
    return AppSection(
      gap: 10,
      children: [
        AppSettingRow(
          title: l10n.enableNotifications,
          trailing: AppSwitch(
            value: appState.notificationsEnabled,
            onChanged: (v) => appState.setNotificationsEnabled(v),
          ),
        ),
        if (_gpuPreference.isSupported)
          AppSettingRow(
            title: l10n.preferHighPerformanceGpu,
            description: l10n.preferHighPerformanceGpuDesc,
            trailing: AppSwitch(
              value: _gpuHighPerformance,
              onChanged: (v) => _setGpuHighPerformance(v),
            ),
          ),
        AppSettingRow(
          title: l10n.enableApiDebug,
          description: l10n.apiDebugDesc,
          trailing: AppSwitch(
            value: appState.enableApiDebug,
            onChanged: (v) => appState.setEnableApiDebug(v),
          ),
          // Inside the row's own box, per `D1`: it opens what this toggle
          // writes, and exists only while it is on.
          footer: appState.enableApiDebug
              ? AppButton(
                  label: l10n.openLogFolder,
                  icon: Icons.folder_zip_outlined,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.compact,
                  onPressed: () => LLMDebugLogger.openLogFolder(),
                )
              : null,
        ),
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          AppSettingRow(
            title: l10n.portableMode,
            description: l10n.portableModeDesc,
            trailing: AppSwitch(
              value: _isPortable,
              onChanged: (v) async {
                await AppPaths.setPortableMode(v);
                setState(() => _isPortable = v);
                if (mounted) {
                  _showRestartDialog(l10n);
                }
              },
            ),
          ),
        if (!Platform.isIOS) _buildOutputDirectoryTile(appState, l10n),
        if (!Platform.isIOS) _buildKnowledgeBaseTile(l10n),
        AppSettingRow(
          title: l10n.assistantRetention,
          description: l10n.assistantRetentionDesc,
          // Boxed like every other select in the app; as bare
          // `DropdownButton`s these two were a number and a triangle floating
          // in the row.
          trailing: SizedBox(
            width: _settingDropdownWidth,
            child: AppDropdown<int>(
              value: const [10, 20, 50, 100].contains(_assistantRetention) ? _assistantRetention : 20,
              items: [
                for (final n in const [10, 20, 50, 100]) AppDropdownItem(value: n, label: '$n'),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await _db.saveSetting(PromptOptimizerAgent.retentionSettingKey, '$v');
                setState(() => _assistantRetention = v);
              },
            ),
          ),
        ),
        AppSettingRow(
          title: l10n.assistantContextRatio,
          description: l10n.assistantContextRatioDesc,
          trailing: SizedBox(
            width: _settingDropdownWidth,
            child: AppDropdown<double>(
              value: _contextRatios.contains(_assistantContextRatio)
                  ? _assistantContextRatio
                  : PromptOptimizerAgent.defaultContextRatio,
              items: [
                for (final r in _contextRatios) AppDropdownItem(value: r, label: '${(r * 100).round()}%'),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await _db.saveSetting(PromptOptimizerAgent.contextRatioSettingKey, '$v');
                setState(() => _assistantContextRatio = v);
              },
            ),
          ),
        ),
        AppSettingRow(
          title: l10n.kbSubAgent,
          description: l10n.kbSubAgentDesc,
          trailing: AppSwitch(
            value: _kbSubAgentEnabled,
            onChanged: (v) async {
              await _db.saveSetting(
                  PromptOptimizerAgent.kbSubAgentSettingKey, v.toString());
              setState(() => _kbSubAgentEnabled = v);
            },
          ),
        ),
        if (_kbSubAgentEnabled) _buildKbSubAgentModelTile(l10n),
      ],
    );
  }

  /// Model the sub-agent runs on. Null = follow the session's model. A
  /// binding whose model has been deleted shows a warning here (and disables
  /// delegation at run time) instead of silently falling back.
  Widget _buildKbSubAgentModelTile(AppLocalizations l10n) {
    final bound = _kbSubAgentModelId;
    final boundExists =
        bound == null || _kbSubAgentModels.any((m) => m.id == bound);
    return AppSettingRow(
      title: l10n.kbSubAgentModel,
      description: boundExists ? null : l10n.kbSubAgentModelMissing,
      descriptionColor: Theme.of(context).colorScheme.error,
      trailing: SizedBox(
        width: 220,
        child: SearchablePickerField<int?>(
          // `null` is a real answer here — "follow the main model" — which is
          // why the picker returns a [PickerResult] rather than a bare `T?`.
          selected: PickerOption<int?>(
            value: boundExists ? bound : null,
            label: boundExists && bound != null
                ? _kbSubAgentModels.firstWhere((m) => m.id == bound).modelName
                : l10n.kbSubAgentModelFollow,
          ),
          optionsBuilder: () => [
            PickerOption<int?>(value: null, label: l10n.kbSubAgentModelFollow),
            for (final m in _kbSubAgentModels)
              PickerOption<int?>(
                value: m.id,
                label: m.modelName,
                secondary: m.modelId == m.modelName ? null : m.modelId,
              ),
          ],
          onChanged: (v) async {
            await _db.saveSetting(
                PromptOptimizerAgent.kbSubAgentModelSettingKey,
                v?.toString() ?? '');
            if (mounted) setState(() => _kbSubAgentModelId = v);
          },
          hint: l10n.kbSubAgentModelFollow,
          searchHint: l10n.searchModels,
          dialogTitle: l10n.kbSubAgentModel,
          dialogIcon: Icons.memory_outlined,
        ),
      ),
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
    return AppSettingRow(
      title: l10n.knowledgeBaseFolder,
      // Mono, as `D1` sets both of this screen's paths. A path is the one
      // string here the user reads character by character to check, and the
      // two rows sit one above the other — different glyph widths make two
      // paths that share a prefix look like they do not.
      description: subtitle,
      monoDescription: true,
      descriptionColor: warn ? colorScheme.error : null,
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
    return AppSettingRow(
      title: l10n.outputDirectory,
      description:
          _outputDirController.text.isEmpty ? l10n.notSet : _outputDirController.text,
      monoDescription: true,
      trailing: Icon(Icons.folder_open,
          size: AppSize.iconSm, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onTap: () async {
        String? path = await FilePicker.getDirectoryPath();
        if (path != null) {
          setState(() => _outputDirController.text = path);
          await appState.updateOutputDirectory(path);
        }
      },
    );
  }

  void _showRestartDialog(AppLocalizations l10n) {
    AppDialog.show<void>(
      context,
      barrierDismissible: false,
      title: l10n.restartRequired,
      content: Text(l10n.restartMessage),
      actions: [
        AppButton(
          label: l10n.exit,
          onPressed: () => exit(0),
        ),
      ],
    );
  }
}
