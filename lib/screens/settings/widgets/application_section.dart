import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_paths.dart';
import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_model.dart';
import '../../../services/database_service.dart';
import '../../../services/gpu_info_service.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/llm/llm_debug_logger.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_field_size.dart';
import '../../../widgets/app_setting_row.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/searchable_picker.dart';
import 'settings_layout.dart';

/// `E1 · 1c` left: three groups — notifications and logging, the directories
/// (with the rendering GPU, which is read the same way a path is), and the
/// prompt assistant.
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

  // Reported, not chosen: which adapter Windows put this process on. Fixed
  // for the life of the process, so it is read once here rather than kept in
  // AppState.
  final GpuInfoService _gpuInfo = GpuInfoService();
  String? _gpuName;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _outputDirController.dispose();
    super.dispose();
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
    _gpuName = await _gpuInfo.activeGpuName();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final bool phone = Responsive.isMobile(context);
    final bool desktopOs = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    // Present whether or not logging is on, so switching it does not move the
    // row; it opens what the switch writes, so it only works while it is on.
    final Widget openLogs = AppButton(
      label: l10n.openLogFolder,
      icon: Icons.folder_open_outlined,
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.compact,
      accentLabel: true,
      onPressed: appState.enableApiDebug ? () => LLMDebugLogger.openLogFolder() : null,
    );

    return SettingsSections(
      children: [
        SettingsBlock(
          caption: l10n.settingsGroupNotifications,
          child: SettingsGroup(
            children: [
              AppSettingRow(
                framed: false,
                title: l10n.enableNotifications,
                description: l10n.notificationsDesc,
                trailing: AppSwitch(
                  value: appState.notificationsEnabled,
                  onChanged: (v) => appState.setNotificationsEnabled(v),
                ),
              ),
              AppSettingRow(
                framed: false,
                title: l10n.enableApiDebug,
                description: l10n.apiDebugDesc,
                // The sentence warns that keys may be written to disk.
                descriptionColor: context.semantic.onWarningContainer,
                trailing: phone
                    ? AppSwitch(
                        value: appState.enableApiDebug,
                        onChanged: (v) => appState.setEnableApiDebug(v),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          openLogs,
                          const SizedBox(width: 12),
                          AppSwitch(
                            value: appState.enableApiDebug,
                            onChanged: (v) => appState.setEnableApiDebug(v),
                          ),
                        ],
                      ),
                footer: phone ? openLogs : null,
              ),
              if (desktopOs)
                AppSettingRow(
                  framed: false,
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
            ],
          ),
        ),
        if (!Platform.isIOS || _gpuInfo.isSupported)
          SettingsBlock(
            caption: l10n.settingsGroupDirectories,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!Platform.isIOS) _buildOutputDirectoryTile(appState, l10n),
                if (!Platform.isIOS) ...[
                  const SizedBox(height: 8),
                  _buildKnowledgeBaseTile(l10n),
                ],
                if (_gpuInfo.isSupported) ...[
                  const SizedBox(height: 8),
                  _buildGpuTile(l10n),
                ],
              ],
            ),
          ),
        SettingsBlock(
          caption: l10n.settingsGroupAssistant,
          child: SettingsGroup(
            children: [
              _buildContextRatio(l10n),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSettingRow(
                    framed: false,
                    title: l10n.kbSubAgent,
                    badge: _ExperimentalBadge(label: l10n.experimental),
                    description: l10n.kbSubAgentDesc,
                    trailing: AppSwitch(
                      value: _kbSubAgentEnabled,
                      onChanged: (v) async {
                        await _db.saveSetting(PromptOptimizerAgent.kbSubAgentSettingKey, v.toString());
                        setState(() => _kbSubAgentEnabled = v);
                      },
                    ),
                  ),
                  _buildKbSubAgentModelField(l10n),
                ],
              ),
              AppSettingRow(
                framed: false,
                title: l10n.assistantRetention,
                description: l10n.assistantRetentionDesc,
                trailing: SizedBox(
                  width: 88,
                  child: AppDropdown<int>(
                    size: AppFieldSize.regular,
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
            ],
          ),
        ),
      ],
    );
  }

  /// `1c` 「助手摘要阈值」: the threshold as a slider over the offered steps,
  /// the value in mono on the title's baseline, the explanation under it.
  Widget _buildContextRatio(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final double value = _contextRatios.contains(_assistantContextRatio)
        ? _assistantContextRatio
        : PromptOptimizerAgent.defaultContextRatio;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.assistantContextRatio,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: textTheme.bodySmall?.mono.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          Slider(
            value: value,
            min: _contextRatios.first,
            max: _contextRatios.last,
            divisions: _contextRatios.length - 1,
            label: '${(value * 100).round()}%',
            onChanged: (v) => setState(() => _assistantContextRatio = _nearestRatio(v)),
            onChangeEnd: (v) => _db.saveSetting(
              PromptOptimizerAgent.contextRatioSettingKey,
              '${_nearestRatio(v)}',
            ),
          ),
          Text(
            l10n.assistantContextRatioDesc,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: AppType.proseHeight,
            ),
          ),
        ],
      ),
    );
  }

  /// A slider value snapped onto the offered list, so what is stored is one
  /// of the exact values the dropdown this replaced offered.
  static double _nearestRatio(double v) => _contextRatios.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);

  /// Which adapter the app is drawing on. No control: the choice is Windows'
  /// own, so the row states the outcome in mono — the way a path is stated —
  /// and the button opens the page where it can be changed. When it cannot be
  /// determined the row is ruled in the warning colour (`1c`).
  Widget _buildGpuTile(AppLocalizations l10n) {
    final semantic = context.semantic;
    final name = _gpuName;
    return AppSettingRow(
      title: l10n.renderingGpu,
      description: name ?? l10n.renderingGpuUnavailable,
      monoDescription: true,
      descriptionColor: name == null ? semantic.onWarningContainer : null,
      borderColor: name == null ? semantic.warning : null,
      trailing: AppButton(
        label: l10n.openGraphicsSettings,
        icon: Icons.open_in_new,
        variant: AppButtonVariant.secondary,
        size: AppButtonSize.compact,
        accentLabel: true,
        // The per-app list on this page is what steers the adapter; a change
        // made there applies on the next launch. Handed to explorer.exe like
        // every other shell target in the app rather than to url_launcher,
        // whose canLaunchUrl gate turns an unrecognised scheme into a button
        // that does nothing at all.
        onPressed: () => Process.run('explorer.exe', ['ms-settings:display-graphics']),
      ),
    );
  }

  /// Model the sub-agent runs on. Null = follow the session's model. A
  /// binding whose model has been deleted shows a warning here (and disables
  /// delegation at run time) instead of silently falling back.
  ///
  /// Held in place while the sub-agent is off, greyed onto the track colour.
  Widget _buildKbSubAgentModelField(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final bound = _kbSubAgentModelId;
    final boundExists = bound == null || _kbSubAgentModels.any((m) => m.id == bound);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsField(
            label: l10n.kbSubAgentModel,
            enabled: _kbSubAgentEnabled,
            child: SearchablePickerField<int?>(
              size: AppFieldSize.regular,
              enabled: _kbSubAgentEnabled,
              // `null` is a real answer here — "follow the main model" — which
              // is why the picker returns a [PickerResult] rather than a bare
              // `T?`.
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
                await _db.saveSetting(PromptOptimizerAgent.kbSubAgentModelSettingKey, v?.toString() ?? '');
                if (mounted) setState(() => _kbSubAgentModelId = v);
              },
              hint: l10n.kbSubAgentModelFollow,
              searchHint: l10n.searchModels,
              dialogTitle: l10n.kbSubAgentModel,
              dialogIcon: Icons.memory_outlined,
            ),
          ),
          if (_kbSubAgentEnabled && !boundExists) ...[
            const SizedBox(height: 4),
            Text(
              l10n.kbSubAgentModelMissing,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickKnowledgeBase() async {
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
  }

  Future<void> _pickOutputDirectory(AppState appState) async {
    String? path = await FilePicker.getDirectoryPath();
    if (path != null) {
      setState(() => _outputDirController.text = path);
      await appState.updateOutputDirectory(path);
    }
  }

  Widget _buildKnowledgeBaseTile(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final String subtitle;
    final bool invalid;
    switch (_kbStatus) {
      case KbStatus.ok:
        subtitle = _kbPath!;
        invalid = false;
      case KbStatus.notSet:
        subtitle = l10n.notSet;
        invalid = false;
      case KbStatus.missingDir:
        subtitle = l10n.kbInvalidDir;
        invalid = true;
      case KbStatus.missingEntry:
        subtitle = l10n.kbMissingEntry;
        invalid = true;
    }
    return AppSettingRow(
      title: l10n.knowledgeBaseFolder,
      // Mono: a path is the one string here the user reads character by
      // character, and the two directory rows sit one above the other.
      description: subtitle,
      monoDescription: true,
      descriptionColor: invalid ? colorScheme.onErrorContainer : null,
      borderColor: invalid ? colorScheme.error : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_kbPath != null) ...[
            Tooltip(
              message: l10n.kbOpenFolder,
              child: AppButton(
                label: l10n.actionOpen,
                icon: Icons.open_in_new,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.compact,
                accentLabel: true,
                onPressed: () => FileUtils.openPath(_kbPath!),
              ),
            ),
            const SizedBox(width: AppSpace.s6),
          ],
          _ChangeButton(label: l10n.actionChange, onPressed: _pickKnowledgeBase),
        ],
      ),
      onTap: _pickKnowledgeBase,
    );
  }

  Widget _buildOutputDirectoryTile(AppState appState, AppLocalizations l10n) {
    return AppSettingRow(
      title: l10n.outputDirectory,
      description: _outputDirController.text.isEmpty ? l10n.notSet : _outputDirController.text,
      monoDescription: true,
      trailing: _ChangeButton(label: l10n.actionChange, onPressed: () => _pickOutputDirectory(appState)),
      onTap: () => _pickOutputDirectory(appState),
    );
  }

  void _showRestartDialog(AppLocalizations l10n) {
    AppDialog.show<void>(
      context,
      barrierDismissible: false,
      icon: Icons.restart_alt,
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

/// `1c`'s 「更改」 on a directory row: the compact button that opens the picker.
/// The whole row opens it too; this is the visible affordance.
class _ChangeButton extends StatelessWidget {
  const _ChangeButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      icon: Icons.folder_open_outlined,
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.compact,
      accentLabel: true,
      onPressed: onPressed,
    );
  }
}

/// `1c`'s 「实验性」 tag: warning wash, warning ink, r4.
class _ExperimentalBadge extends StatelessWidget {
  const _ExperimentalBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: semantic.onWarningContainer),
      ),
    );
  }
}
