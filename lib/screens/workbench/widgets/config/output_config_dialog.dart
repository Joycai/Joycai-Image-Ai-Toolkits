import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_semantic_colors.dart';
import '../../../../core/design_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/image_output_config.dart';
import '../../../../models/llm_model.dart';
import '../../../../services/llm/generation/generation_schema.dart';
import '../../../../state/app_state.dart';
import '../../../../state/gallery_state.dart';
import '../../../../widgets/ui/app_button.dart';
import '../../../../widgets/ui/app_dialog.dart';
import '../../../../widgets/ui/app_section_label.dart';
import '../../../../widgets/ui/app_setting_row.dart';
import '../../../../widgets/ui/app_text_field.dart';
import '../../model_selection_section.dart';
import '../generation_params/generation_param_texts.dart';

/// Opens the Add / Edit Output Config dialog using the app's [AppDialog] shell
/// and [ModelSelectionSection] parameter editors.
///
/// When [onCommit] is provided it is invoked synchronously on tap before
/// popping the dialog, so state/persistence updates start immediately without
/// waiting for the close transition.
Future<ImageOutputConfig?> showOutputConfigDialog(
  BuildContext context, {
  ImageOutputConfig? initial,
  Future<void> Function(ImageOutputConfig config)? onCommit,
}) {
  return showDialog<ImageOutputConfig>(
    context: context,
    animationStyle: appDialogAnimation(context),
    builder: (_) => _OutputConfigDialog(initial: initial, onCommit: onCommit),
  );
}

class _OutputConfigDialog extends StatefulWidget {
  const _OutputConfigDialog({this.initial, this.onCommit});

  final ImageOutputConfig? initial;
  final Future<void> Function(ImageOutputConfig config)? onCommit;

  @override
  State<_OutputConfigDialog> createState() => _OutputConfigDialogState();
}

class _OutputConfigDialogState extends State<_OutputConfigDialog> {
  late final TextEditingController _aliasController;
  int? _channelId;
  int? _modelDbId;
  Map<String, String> _params = {};
  bool _useBatch = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final initial = widget.initial;
    _aliasController = TextEditingController(text: initial?.alias ?? '');

    LLMModel? seedModel;
    if (initial != null) {
      seedModel = appState.resolveOutputModel(initial);
    } else if (appState.imageModels.isNotEmpty) {
      final lastOutput = appState.imageOutputConfigs.lastOrNull;
      if (lastOutput != null) {
        seedModel = appState.resolveOutputModel(lastOutput);
      }
      if (seedModel == null && appState.lastSelectedModelId != null) {
        final savedDbId = int.tryParse(appState.lastSelectedModelId!);
        seedModel = appState.imageModels
            .where((m) => m.id == savedDbId || m.modelId == appState.lastSelectedModelId)
            .firstOrNull;
      }
      seedModel ??= appState.imageModels.first;
    }

    if (seedModel != null) {
      _modelDbId = seedModel.id;
      _channelId = seedModel.channelId;
      _params = initial != null
          ? Map<String, String>.from(initial.params)
          : appState.defaultOutputParamsForModel(seedModel);
      _useBatch = (initial?.useBatch ?? false) && appState.supportsImageBatch(seedModel);
    } else {
      _channelId = appState.imageChannels.firstOrNull?.id;
      _params = initial != null ? Map<String, String>.from(initial.params) : {};
      _useBatch = initial?.useBatch ?? false;
    }
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  LLMModel? _resolveSelectedModel(AppState appState) {
    if (_modelDbId == null) return null;
    for (final m in appState.imageModels) {
      if (m.id == _modelDbId) return m;
    }
    return null;
  }

  void _selectModel(AppState appState, LLMModel model) {
    setState(() {
      _channelId = model.channelId;
      _modelDbId = model.id;
      _params = appState.defaultOutputParamsForModel(model);
      if (!appState.supportsImageBatch(model)) _useBatch = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.watch<AppState>();
    final selectedImages = context.select<GalleryState, int>((s) => s.selectedImages.length);
    final imageModels = appState.imageModels;
    final imageChannels = appState.imageChannels;

    final resolvedModel = _resolveSelectedModel(appState);
    final modelInChannel = resolvedModel?.channelId == _channelId ? resolvedModel : null;
    final batchSupported = appState.supportsImageBatch(modelInChannel);

    final media = [
      for (final image in appState.galleryState.selectedImages)
        GenerationMedia(GenerationMediaRole.reference, image.path),
    ];

    GenerationDiagnostic? blockingDiag;
    bool hasConfigDiag = false;
    if (modelInChannel != null) {
      final effective = appState.effectiveParamsForOutput(modelInChannel, _params, media: media);
      final diagnostics = appState.generationInputDiagnostics(modelInChannel, effective, media);
      blockingDiag = diagnostics
          .where(
            (d) => const {
              'transparentJpeg',
              'wanEditSize',
              'agentTextOnly',
              'invalidParameter',
            }.contains(d.code),
          )
          .firstOrNull;
      hasConfigDiag = appState
          .generationSchemaForModel(modelInChannel)
          .configurationDiagnostics
          .isNotEmpty;
    }
    final bool hasBlockingDiagnostic = blockingDiag != null || hasConfigDiag;

    String? referenceWarning;
    if (modelInChannel != null && selectedImages > 0) {
      final caps = appState.generationSchemaForModel(modelInChannel).capabilities;
      if (!caps.supportsReferenceImages) {
        referenceWarning = l10n.referenceImagesNotSupported;
      } else if (caps.maxReferenceImages != null && selectedImages > caps.maxReferenceImages!) {
        referenceWarning = l10n.referenceImagesLimited(caps.maxReferenceImages!);
      }
    }

    final bool canSave = modelInChannel != null && !hasBlockingDiagnostic;

    return AppDialog(
      title: _isEditing ? l10n.editOutputConfig : l10n.addOutputConfig,
      subtitle: l10n.outputConfigDialogSubtitle,
      maxWidth: 540,
      maxHeight: 680,
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModelSelectionSection(
            showHeader: false,
            availableModels: imageModels,
            channels: imageChannels,
            selectedChannelId: _channelId,
            selectedModelDbId: _modelDbId,
            isExpanded: true,
            onToggleExpansion: () {},
            onChannelChanged: (val) {
              if (val == null) return;
              final firstInChannel = imageModels.where((m) => m.channelId == val).firstOrNull;
              if (firstInChannel != null) {
                _selectModel(appState, firstInChannel);
              } else {
                setState(() {
                  _channelId = val;
                  _modelDbId = null;
                });
              }
            },
            onModelChanged: (val) {
              if (val == null) return;
              final picked = imageModels.where((m) => m.id == val).firstOrNull;
              if (picked != null) _selectModel(appState, picked);
            },
            imageParamResolver: (model, spec) => appState.getOutputParam(model, spec, _params),
            onImageParamChanged: (model, key, value) {
              setState(() {
                _params = {..._params, key: value};
              });
            },
            schemaOf: appState.generationSchemaForModel,
            capabilitiesOf: (model) => appState.generationSchemaForModel(model).capabilities,
            storedImageParamOf: (model, key) => _params[key],
            specRatesOf: appState.specRatesFor,
          ),
          if (batchSupported) ...[
            const SizedBox(height: AppSpace.s10),
            const Divider(height: 1),
            const SizedBox(height: AppSpace.s4),
            AppToggleRow(
              title: l10n.batchSubmit,
              description: l10n.batchSubmitHint,
              value: _useBatch,
              onChanged: (v) => setState(() => _useBatch = v),
            ),
          ],
          AppSectionLabel(
            l10n.outputConfigAlias,
            padding: const EdgeInsets.only(top: AppSpace.s16, bottom: AppSpace.s6),
          ),
          AppTextField(controller: _aliasController, hint: l10n.outputConfigAliasHint),
          if (blockingDiag != null && blockingDiag.code != 'transparentJpeg') ...[
            const SizedBox(height: AppSpace.s10),
            _DiagnosticErrorBanner(message: GenerationParamTexts.diagnostic(l10n, blockingDiag)),
          ],
          if (referenceWarning != null) ...[
            const SizedBox(height: AppSpace.s10),
            _ReferenceWarningBanner(message: referenceWarning),
          ],
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: _isEditing ? l10n.save : l10n.addOutputConfig,
          variant: AppButtonVariant.primary,
          onPressed: canSave ? () => _commit(appState, modelInChannel) : null,
        ),
      ],
    );
  }

  void _commit(AppState appState, LLMModel model) {
    final config = ImageOutputConfig(
      id: widget.initial?.id ?? appState.nextImageOutputConfigId(),
      modelDbId: model.id,
      modelIdFallback: model.modelId,
      enabled: widget.initial?.enabled ?? true,
      alias: _aliasController.text.trim(),
      params: _params,
      useBatch: _useBatch && appState.supportsImageBatch(model),
    );
    final onCommit = widget.onCommit;
    if (onCommit != null) unawaited(onCommit(config));
    Navigator.pop(context, config);
  }
}

class _DiagnosticErrorBanner extends StatelessWidget {
  const _DiagnosticErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: AppSize.iconSm, color: colorScheme.error),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceWarningBanner extends StatelessWidget {
  const _ReferenceWarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: AppSize.iconSm, color: semantic.warning),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: semantic.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}
