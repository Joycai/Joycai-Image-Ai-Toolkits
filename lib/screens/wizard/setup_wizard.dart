import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/app_paths.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/model_discovery_service.dart';
import '../../services/llm/model_family.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../state/app_state.dart';
import '../../widgets/api_key_field.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_setting_row.dart';
import '../../widgets/app_switch.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/models/channel_provider_presets.dart';
import '../../widgets/settings_widgets.dart';
import 'wizard_import.dart';

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  final PageController _pageController = PageController();
  final DatabaseService _db = DatabaseService();
  int _currentStep = 0;
  final int _totalSteps = 5;

  // Controllers
  final TextEditingController _outputDirController = TextEditingController();
  final TextEditingController _prefixController = TextEditingController();

  // Channel Step Controllers
  final TextEditingController _channelNameController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  String _channelType = Vendors.googleRest;
  int? _createdChannelId;

  // Model Step Controllers
  final TextEditingController _modelIdController = TextEditingController();
  final TextEditingController _modelNameController = TextEditingController();
  String _modelTag = 'multimodal';
  bool _isFetchingModels = false;
  bool _isPortable = false;

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  Future<void> _loadInitialValues() async {
    final appState = Provider.of<AppState>(context, listen: false);
    _outputDirController.text = appState.outputDirectory ?? '';
    _prefixController.text = appState.imagePrefix;
    _channelNameController.text = 'My First Channel';
    _isPortable = await AppPaths.isPortableMode();
    _updateDefaultEndpoint();
    setState(() {});
  }

  void _updateDefaultEndpoint() {
    switch (_channelType) {
      case Vendors.openAIRest:
        _endpointController.text = 'https://api.openai.com/v1';
        break;
      case Vendors.newApiOpenAI:
        // New API is a self-hosted relay; only the path suffix is known.
        _endpointController.text = 'https://your-newapi-host.com/v1';
        break;
      case Vendors.newApiGemini:
        _endpointController.text = 'https://your-newapi-host.com/v1beta';
        break;
      case Vendors.xaiApi:
        _endpointController.text = 'https://api.x.ai/v1';
        break;
      case Vendors.deepseek:
        _endpointController.text = 'https://api.deepseek.com';
        break;
      case Vendors.minimax:
        _endpointController.text = 'https://api.minimaxi.com/v1';
        break;
      case Vendors.anthropicRest:
        _endpointController.text = 'https://api.anthropic.com/v1';
        break;
      case Vendors.newApiAnthropic:
        _endpointController.text = 'https://your-newapi-host.com/v1';
        break;
      case Vendors.minimaxAnthropic:
        // Not `/v1`: MiniMax puts its ④-format endpoint beside the ① one.
        _endpointController.text = 'https://api.minimaxi.com/anthropic/v1';
        break;
      case Vendors.dashscope:
        // Mainland host. The international one (dashscope-intl.aliyuncs.com)
        // is reached by typing over this, exactly as in the add-channel
        // wizard's preset.
        _endpointController.text =
            'https://dashscope.aliyuncs.com/compatible-mode/v1';
        break;
      case Vendors.midjourneyProxy:
        // A self-hosted proxy; only the shape of the host is knowable.
        _endpointController.text = 'https://your-midjourney-proxy.com';
        break;
      default:
        _endpointController.text = 'https://generativelanguage.googleapis.com/v1beta';
    }
  }

  void _nextStep() {
    if (_currentStep == 2) {
      _saveChannelAndContinue();
      return;
    }
    
    if (_currentStep == 3) {
      _saveModelAndContinue();
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(duration: AppMotion.durationOf(context, AppMotion.panel), curve: AppMotion.move);
      setState(() => _currentStep++);
    } else {
      _finishSetup();
    }
  }

  Future<void> _saveChannelAndContinue() async {
    // Read before the await, not after: `context` is not this method's to
    // consult once it has yielded, and the page turn is always the last thing
    // it does.
    final pageTurn = AppMotion.durationOf(context, AppMotion.panel);
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isNotEmpty) {
      final id = await _db.addChannel({
        'display_name': _channelNameController.text.trim(),
        'endpoint': _endpointController.text.trim(),
        'api_key': apiKey,
        'type': _channelType,
        'enable_discovery': 1,
        'tag': _channelNameController.text.trim().split(' ').first,
        'tag_color': Colors.blue.toARGB32(),
      });
      setState(() {
        _createdChannelId = id;
        _currentStep++;
      });
      _pageController.nextPage(duration: pageTurn, curve: AppMotion.move);
    } else {
      // Skip model step if no channel added
      setState(() {
        _currentStep = 4; // Jump to finish
      });
      _pageController.animateToPage(4, duration: pageTurn, curve: AppMotion.move);
    }
  }

  Future<void> _saveModelAndContinue() async {
    final pageTurn = AppMotion.durationOf(context, AppMotion.panel);
    if (_modelIdController.text.isNotEmpty && _createdChannelId != null) {
      await _db.addModel({
        'model_id': _modelIdController.text,
        'model_name': _modelNameController.text.isEmpty ? _modelIdController.text : _modelNameController.text,
        'tag': _modelTag,
        'is_paid': 1,
        'sort_order': 0,
        'channel_id': _createdChannelId,
      });
    }
    
    setState(() => _currentStep++);
    _pageController.nextPage(duration: pageTurn, curve: AppMotion.move);
  }

  Future<void> _finishSetup() async {
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.completeSetup();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // `D3 12c` draws the wizard's chrome as a 52px strip with the
            // title at one end and 「跳过」 at the other, then the progress bar
            // flush under it. An [AppBar] is 56, carries its own elevation and
            // surface-tint rules, and puts the skip action in a slot sized for
            // icon buttons — three decisions this screen does not need made
            // for it.
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Text(l10n.setupWizardTitle, style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  AppButton(
                    label: l10n.skip,
                    variant: AppButtonVariant.text,
                    size: AppButtonSize.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(value: (_currentStep + 1) / _totalSteps),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomeStep(context, l10n),
                  // 560, per `D3 12d`. A form of single-line fields stretched
                  // to a desktop window puts an API key on a line a thousand
                  // pixels wide. Welcome and finish centre their own, narrower
                  // column and are left alone.
                  _stepColumn(_buildStorageStep(context, l10n)),
                  _stepColumn(_buildChannelStep(context, l10n)),
                  _stepColumn(_buildModelStep(context, l10n)),
                  _buildFinishStep(context, l10n),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_currentStep > 0 && _currentStep != 4)
                    AppButton(
                      label: l10n.back,
                      variant: AppButtonVariant.text,
                      onPressed: () {
                        int prev = _currentStep - 1;
                        if (_currentStep == 4 && _createdChannelId == null) {
                          prev = 2; // Go back to channel if model was skipped
                        }
                        _pageController.animateToPage(prev, duration: AppMotion.durationOf(context, AppMotion.panel), curve: AppMotion.move);
                        setState(() => _currentStep = prev);
                      },
                    ),
                  const SizedBox(width: 14),
                  AppButton(
                    label: _currentStep == _totalSteps - 1 ? l10n.getStarted : (_currentStep == 2 && _apiKeyController.text.isEmpty ? l10n.skip : l10n.next),
                    onPressed: _currentStep == 1 && _outputDirController.text.isEmpty
                        ? null
                        : _nextStep,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Holds a form step to the width `D3` draws it at.
  static Widget _stepColumn(Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        ),
      );

  Widget _buildWelcomeStep(BuildContext context, AppLocalizations l10n) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // A plate, not a bare glyph. `12c` gives the first thing a new user
          // sees the app's own mark — the same gradient square the title bar
          // and the mobile drawer already wear — where this drew a sparkle in
          // `Colors.blue`, a hue from no palette this app uses.
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colorScheme.primary, colorScheme.onAccentTint],
              ),
              boxShadow: colorScheme.shadowRaised,
            ),
            child: Icon(Icons.auto_awesome, size: 30, color: colorScheme.onPrimary),
          ),
          const SizedBox(height: 22),
          Text(
            l10n.welcomeMessage,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 34),
          // 420, per `12c`. Unbounded, the theme and language selectors
          // stretched to whatever the window was, which on a desktop put a
          // three-option segmented control a thousand pixels wide under a
          // centred paragraph.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                ThemeSelector(appState: appState, l10n: l10n),
                const SizedBox(height: 18),
                LanguageSelector(appState: appState, l10n: l10n),
                const SizedBox(height: 28),
                AppButton(
                  label: l10n.importSettings,
                  icon: Icons.upload_file_outlined,
                  variant: AppButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: () => importBackupSettings(context, l10n),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageStep(BuildContext context, AppLocalizations l10n) {
    final appState = Provider.of<AppState>(context);
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l10n.stepStorage, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.storageLocationDesc),
          const SizedBox(height: 24),
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
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            const SizedBox(height: 16),
          TextField(
            controller: _outputDirController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: l10n.outputDirectory,
              suffixIcon: const Icon(Icons.folder_open),
            ),
            onTap: () async {
              String? path = await FilePicker.getDirectoryPath();
              if (path != null) {
                setState(() => _outputDirController.text = path);
                appState.updateOutputDirectory(path);
              }
            },
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _prefixController,
            decoration: InputDecoration(
              labelText: l10n.filenamePrefix,
              helperText: "e.g. 'result' -> result_001.png",
            ),
            onChanged: (v) => appState.setImagePrefix(v),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelStep(BuildContext context, AppLocalizations l10n) {
    final String endpointHint = switch (Vendors.byId(_channelType).family) {
      ProtocolFamily.gemini =>
        "Hint: Google GenAI endpoints usually end with '/v1beta' (internal handling)",
      ProtocolFamily.anthropic =>
        "Hint: Anthropic endpoints usually end with '/v1'",
      ProtocolFamily.openai || ProtocolFamily.midjourney =>
        "Hint: OpenAI compatible endpoints usually end with '/v1'",
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.addChannel, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.addChannelOptional),
          const SizedBox(height: 24),
          TextField(
            controller: _channelNameController,
            decoration: InputDecoration(
              labelText: l10n.displayName,
              hintText: "e.g. My OpenAI",
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _channelType,
            // The same registry-derived catalogue the channel editor uses:
            // a hand-written list here went stale every time a vendor was
            // added, and first-run had no way to pick DashScope at all.
            items: [
              for (final vendorType in channelTypesInDisplayOrder())
                DropdownMenuItem(
                  value: vendorType,
                  child: Text(channelTypeLabel(l10n, vendorType)),
                ),
            ],
            onChanged: (v) {
              setState(() {
                _channelType = v!;
                _updateDefaultEndpoint();
              });
            },
            decoration: InputDecoration(
              labelText: l10n.channelType,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _endpointController,
            // Mono, as `D3` sets it — and as the models screen sets the same
            // value once the channel exists. An endpoint is a path the user
            // checks segment by segment, and this is the one place they type
            // it rather than read it.
            style: Theme.of(context).textTheme.bodyMedium?.mono,
            decoration: InputDecoration(
              labelText: l10n.endpointUrl,
              helperText: endpointHint,
              // Was `Colors.blueGrey` — a literal that ignores the theme
              // entirely, so the hint stayed the same muddy grey in dark mode
              // and did not move with the seed. The scheme has a role for
              // exactly this.
              helperStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 16),
          ApiKeyField(
            controller: _apiKeyController,
            label: l10n.apiKey,
            onChanged: (v) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildModelStep(BuildContext context, AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.addModel, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.configureModelOptional),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _modelIdController,
                  decoration: InputDecoration(
                    labelText: l10n.modelIdLabel,
                    hintText: "e.g. gpt-4o",
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: l10n.fetchModels,
                icon: Icons.refresh,
                variant: AppButtonVariant.secondary,
                loading: _isFetchingModels,
                onPressed: _fetchModels,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelNameController,
            decoration: InputDecoration(
              labelText: l10n.displayName,
              hintText: "e.g. My Model",
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _modelTag,
            items: const [
              DropdownMenuItem(value: 'chat', child: Text('Chat')),
              DropdownMenuItem(value: 'multimodal', child: Text('Multimodal')),
              DropdownMenuItem(value: 'image', child: Text('Image')),
            ],
            onChanged: (v) => setState(() => _modelTag = v!),
            decoration: InputDecoration(
              labelText: l10n.tag,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchModels() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isFetchingModels = true);
    
    try {
      final apiKey = _apiKeyController.text.trim();

      final config = LLMModelConfig(
        modelId: 'discovery',
        channelType: _channelType,
        endpoint: _endpointController.text.trim(),
        apiKey: apiKey,
      );

      final models = await ModelDiscoveryService().discoverModels(config);
      
      if (!mounted) return;
      
      final selected = await AppDialog.show<DiscoveredModel>(
        context,
        title: l10n.selectModelsToAdd,
        maxWidth: 400,
        maxHeight: 400,
        content: ListView.builder(
          itemCount: models.length,
          itemBuilder: (context, index) {
            final m = models[index];
            return ListTile(
              title: Text(m.displayName),
              subtitle: Text(m.modelId),
              onTap: () => Navigator.pop(context, m),
            );
          },
        ),
      );

      if (selected != null) {
        setState(() {
          _modelIdController.text = selected.modelId;
          _modelNameController.text = selected.displayName;
          // Layer 3 owns model-id inference — this used to be a second,
          // divergent contains() chain (the discovery dialog already tags
          // through the classifier).
          _modelTag = ModelFamilyClassifier.inferTag(selected.modelId);
        });
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _isFetchingModels = false);
    }
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

  Widget _buildFinishStep(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          Text(l10n.setupCompleteMessage, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
