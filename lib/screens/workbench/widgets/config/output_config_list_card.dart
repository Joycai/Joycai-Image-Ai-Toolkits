import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_semantic_colors.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/constants.dart';
import '../../../../core/design_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/image_output_config.dart';
import '../../../../models/llm_channel.dart';
import '../../../../models/llm_model.dart';
import '../../../../services/llm/generation/generation_param.dart';
import '../../../../services/llm/generation/generation_schema.dart';
import '../../../../services/llm/param_spec.dart';
import '../../../../state/app_state.dart';
import '../../../../widgets/ui/app_button.dart';
import '../../../../widgets/ui/app_switch.dart';
import '../../../../widgets/ui/dashed_border.dart';
import '../../../../widgets/ui/scroll_edge_fade.dart';
import '../generation_params/generation_param_texts.dart';

/// Builds compact display chips summarizing the non-trivial parameters of [config].
List<({String label, bool isAccent})> summarizeOutputConfigParams(
  AppLocalizations l10n,
  LLMModel model,
  GenerationSchema schema,
  ImageOutputConfig config, {
  required bool supportsBatch,
  required String Function(ParamSpec spec) valueOf,
}) {
  final chips = <({String label, bool isAccent})>[];
  final draft = {
    for (final spec in schema.capabilities.imageParams)
      spec.key: GenerationParam(spec).decode(valueOf(spec)),
  };
  final operation = schema.operation(draft, const []);

  for (final spec in schema.capabilities.imageParams) {
    final fieldState = schema.fieldState(spec.key, operation, draft);
    if (fieldState == GenerationFieldState.inactive) continue;
    final val = valueOf(spec);
    if (val == 'not_set') continue;
    if (spec.key == 'maxImages' && val == '1') continue;
    if (spec.key == 'background' && val == 'auto') continue;
    if (spec.key == 'promptExtend' && val == 'off') continue;
    if (spec.key == 'webSearch' && val == 'off') continue;
    if (spec.key == 'watermark' && val == 'off') continue;
    if (spec.key == 'imageTask' && val == 'generate') continue;

    final label = GenerationParamTexts.option(
      l10n,
      spec.key,
      val,
      hasExplicitAuto: spec.options.any((o) => o.value == 'auto'),
    );
    chips.add((label: label, isAccent: false));
  }

  if (config.useBatch && supportsBatch) {
    chips.add((label: l10n.batchSubmit, isAccent: true));
  }
  return chips;
}

/// The workbench right panel's Output Configs card: lists configured model/param
/// targets with per-item enable switches, parameter chips, warnings, and
/// Add / Edit / Duplicate / Delete actions.
class OutputConfigListCard extends StatelessWidget {
  const OutputConfigListCard({
    super.key,
    required this.configs,
    required this.selectedImageCount,
    required this.onAdd,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggle,
    this.scrollable = true,
  });

  final List<ImageOutputConfig> configs;
  final int selectedImageCount;
  final VoidCallback onAdd;
  final ValueChanged<ImageOutputConfig> onEdit;
  final ValueChanged<ImageOutputConfig> onDuplicate;
  final ValueChanged<ImageOutputConfig> onDelete;
  final void Function(String id, bool enabled) onToggle;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;
    final enabledCount = configs.where((c) => c.enabled).length;

    final captionStyle = textTheme.labelSmall?.copyWith(
      letterSpacing: AppType.trackedLabelSpacing,
      color: colorScheme.onAccentTint,
    );

    final header = SizedBox(
      height: AppSize.compact,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    l10n.outputConfigs,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: captionStyle,
                  ),
                ),
                if (configs.isNotEmpty) ...[
                  const SizedBox(width: AppSpace.s6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.accentTint,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      l10n.outputConfigsEnabledCount(enabledCount, configs.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.onAccentTint),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s6),
          AppButton(
            label: l10n.addOutputConfig,
            icon: Icons.add,
            variant: AppButtonVariant.tonal,
            size: AppButtonSize.compact,
            onPressed: onAdd,
          ),
        ],
      ),
    );

    final Widget body;
    if (configs.isEmpty) {
      final emptyBox = DashedBorder(
        color: colorScheme.outline,
        radius: AppRadius.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.noOutputConfigs,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpace.s4),
              Text(
                l10n.noOutputConfigsHint,
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
              ),
              const SizedBox(height: AppSpace.s10),
              AppButton(
                label: l10n.addOutputConfig,
                icon: Icons.add,
                variant: AppButtonVariant.tonal,
                size: AppButtonSize.compact,
                onPressed: onAdd,
              ),
            ],
          ),
        ),
      );
      body = scrollable
          ? Flexible(
              child: ScrollEdgeFade(child: SingleChildScrollView(child: emptyBox)),
            )
          : emptyBox;
    } else {
      final listContent = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < configs.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.s6),
            _OutputConfigRow(
              key: ValueKey(configs[i].id),
              config: configs[i],
              selectedImageCount: selectedImageCount,
              onEdit: () => onEdit(configs[i]),
              onDuplicate: () => onDuplicate(configs[i]),
              onDelete: () => onDelete(configs[i]),
              onToggle: (enabled) => onToggle(configs[i].id, enabled),
            ),
          ],
        ],
      );

      body = scrollable
          ? Flexible(
              child: ScrollEdgeFade(child: SingleChildScrollView(child: listContent)),
            )
          : listContent;
    }

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              const SizedBox(height: AppSpace.s6),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

class _OutputConfigRow extends StatelessWidget {
  const _OutputConfigRow({
    super.key,
    required this.config,
    required this.selectedImageCount,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggle,
  });

  final ImageOutputConfig config;
  final int selectedImageCount;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();

    final LLMModel? model = appState.resolveOutputModel(config);
    final LLMChannel? channel = model == null
        ? null
        : appState.imageChannels.where((c) => c.id == model.channelId).firstOrNull ??
              appState.allChannels.where((c) => c.id == model.channelId).firstOrNull;
    final schema = model == null ? null : appState.generationSchemaForModel(model);
    final supportsBatch = appState.supportsImageBatch(model);

    final chips = (model != null && schema != null)
        ? summarizeOutputConfigParams(
            l10n,
            model,
            schema,
            config,
            supportsBatch: supportsBatch,
            valueOf: (spec) => appState.getOutputParam(model, spec, config.params),
          )
        : const <({String label, bool isAccent})>[];

    String? errorMessage;
    String? warningMessage;
    if (model == null) {
      errorMessage = l10n.outputConfigModelUnavailable;
    } else if (schema != null) {
      final media = [
        for (final image in appState.galleryState.selectedImages)
          GenerationMedia(GenerationMediaRole.reference, image.path),
      ];
      final effective = appState.effectiveParamsForOutput(model, config.params, media: media);
      final diagnostics = appState.generationInputDiagnostics(model, effective, media);
      final blocking = diagnostics.where(
        (d) => const {
          'transparentJpeg',
          'wanEditSize',
          'agentTextOnly',
          'invalidParameter',
        }.contains(d.code),
      );
      if (schema.configurationDiagnostics.isNotEmpty) {
        errorMessage = GenerationParamTexts.diagnostic(l10n, schema.configurationDiagnostics.first);
      } else if (blocking.isNotEmpty) {
        errorMessage = GenerationParamTexts.diagnostic(l10n, blocking.first);
      }

      if (selectedImageCount > 0) {
        final caps = schema.capabilities;
        if (!caps.supportsReferenceImages) {
          warningMessage = l10n.referenceImagesNotSupported;
        } else if (caps.maxReferenceImages != null &&
            selectedImageCount > caps.maxReferenceImages!) {
          warningMessage = l10n.referenceImagesLimited(caps.maxReferenceImages!);
        }
      }
    }

    final displayName = model?.modelName ?? config.modelIdFallback ?? l10n.selectAModel;
    final dotColor = channel?.tag != null
        ? Color(channel!.tagColor ?? AppConstants.defaultTagColor)
        : colorScheme.outline;

    final semantic = context.semantic;

    final Widget details = Opacity(
      opacity: config.enabled ? 1.0 : 0.56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chips.isNotEmpty) ...[
            const SizedBox(height: AppSpace.s6),
            Wrap(
              spacing: AppSpace.s4,
              runSpacing: AppSpace.s4,
              children: [
                for (final chip in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2),
                    decoration: BoxDecoration(
                      color: chip.isAccent
                          ? colorScheme.accentTint
                          : colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      chip.label,
                      style: textTheme.labelSmall?.mono.copyWith(
                        color: chip.isAccent
                            ? colorScheme.onAccentTint
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpace.s6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: AppSpace.s4),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline,
                      size: AppSize.iconSm,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: AppSpace.s4),
                  Expanded(
                    child: Text(
                      errorMessage,
                      style: textTheme.labelSmall?.copyWith(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (warningMessage != null) ...[
            const SizedBox(height: AppSpace.s6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: AppSpace.s4),
              decoration: BoxDecoration(
                color: semantic.warningContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: AppSize.iconSm,
                      color: semantic.warning,
                    ),
                  ),
                  const SizedBox(width: AppSpace.s4),
                  Expanded(
                    child: Text(
                      warningMessage,
                      style: textTheme.labelSmall?.copyWith(color: semantic.onWarningContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s10, AppSpace.s6, AppSpace.s6, AppSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Opacity(
                      opacity: config.enabled ? 1.0 : 0.56,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: AppSpace.s6),
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.mono.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (config.alias.trim().isNotEmpty) ...[
                            const SizedBox(width: AppSpace.s6),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpace.s6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.accentTint,
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Text(
                                  config.alias.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onAccentTint,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s6),
                  Semantics(
                    label: l10n.toggleOutputConfigLabel(displayName),
                    child: AppSwitch(value: config.enabled, onChanged: onToggle),
                  ),
                ],
              ),
              details,
              const SizedBox(height: AppSpace.s4),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Row(
                children: [
                  Expanded(
                    child: Opacity(
                      opacity: config.enabled ? 1.0 : 0.56,
                      child: Text(
                        channel?.displayName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune_outlined),
                    tooltip: l10n.editOutputConfigTooltip,
                    style: _rowIconStyle(colorScheme.onAccentTint),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_copy_outlined),
                    tooltip: l10n.duplicateOutputConfig,
                    style: _rowIconStyle(colorScheme.onSurfaceVariant),
                    onPressed: onDuplicate,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.delete,
                    style: _rowIconStyle(colorScheme.error),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static ButtonStyle _rowIconStyle(Color ink) => IconButton.styleFrom(
    foregroundColor: ink,
    iconSize: AppSize.iconMd,
    minimumSize: const Size.square(AppSize.compact),
    maximumSize: const Size.square(AppSize.compact),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
