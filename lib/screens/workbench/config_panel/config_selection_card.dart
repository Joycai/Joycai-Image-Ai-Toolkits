part of '../workbench_config_panel.dart';

/// The selection card: the dashed empty slot or the reorderable thumbnail
/// strip, and the reference-image notice under it.
extension _SelectionCard on _WorkbenchConfigPanelState {
  Widget _buildSelectionCard(
      BuildContext context, LLMModel? model, List<AppImage> selectedImages, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    if (selectedImages.isEmpty) {
      // `A1` 「未选 = 虚线卡」: the 16:9 slot the selection will fill, drawn
      // as an empty place rather than as a card with nothing in it.
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: DashedBorder(
          color: colorScheme.outline,
          radius: AppRadius.lg,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.collections_outlined, size: AppSize.iconLg, color: colorScheme.outline),
                const SizedBox(height: AppSpace.s6),
                Text(
                  l10n.noImagesSelected,
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final notice = _buildReferenceImageNotice(context, model, selectedImages.length, l10n);

    // The whole thumbnail is the drag source, as `1a` draws it (no handle
    // glyph): straight away under a mouse, after a long press under a finger
    // so a swipe still scrolls the strip — the split Material's own default
    // handles make.
    final bool touchDrag = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      _ => false,
    };

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.selectedCount(selectedImages.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              AppButton(
                label: l10n.clear,
                variant: AppButtonVariant.text,
                size: AppButtonSize.compact,
                onPressed: () => Provider.of<AppState>(context, listen: false).clearImageSelection(),
              ),
            ],
          ),
          const SizedBox(height: _kCardInnerGap),
          SizedBox(
            height: _kThumbSize,
            // `00d · 1b`: the gap the strip opens is the drop target, 88 wide
            // with 「放到第 3 位」 in it; the moved thumbnail confirms with the
            // 600ms ring.
            child: AppReorderGap(
              itemCount: selectedImages.length,
              axis: Axis.horizontal,
              touch: touchDrag,
              // The margin after each thumbnail, so the gap is the picture's
              // own 88.
              slotPadding: Directionality.of(context) == TextDirection.rtl
                  ? const EdgeInsets.only(left: AppSpace.s6)
                  : const EdgeInsets.only(right: AppSpace.s6),
              builder: (context, gap) => ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                itemCount: selectedImages.length,
                // `1f` 到时：触觉 medium.
                onReorderStart: gap.onReorderStart((_) {
                  if (touchDrag) HapticFeedback.mediumImpact();
                }),
                onReorderItem: gap.onReorderItem((oldIndex, newIndex) {
                  Provider.of<AppState>(context, listen: false).galleryState.reorderSelectedImages(oldIndex, newIndex);
                }),
                // `1b` 抬起: the picked-up thumbnail rises 3px inside a 2px
                // accent ring — no 1px edge, which a picture's own edge would
                // swallow — and settles back as it is dropped. With less motion
                // (`1g`) the ring is simply there.
                proxyDecorator: (child, index, animation) {
                  if (index >= selectedImages.length) return child;
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) => Material(
                      type: MaterialType.transparency,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: AppSpace.s6),
                        child: _SelectionThumb(
                          image: selectedImages[index],
                          index: index,
                          lift: AppMotion.prefersReduced(context) ? 1 : AppMotion.enter.transform(animation.value),
                        ),
                      ),
                    ),
                  );
                },
                itemBuilder: (context, index) {
                  final image = selectedImages[index];
                  final thumb = _SelectionThumb(
                    image: image,
                    index: index,
                    onRemove: () => Provider.of<AppState>(context, listen: false).toggleImageSelection(image),
                  );
                  return gap.item(
                    key: ValueKey(image.path),
                    index: index,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: AppSpace.s6),
                      child: touchDrag
                          ? AppLongPressDragStartListener(index: index, child: thumb)
                          : ReorderableDragStartListener(index: index, child: thumb),
                    ),
                  );
                },
              ),
            ),
          ),
          if (selectedImages.length > 1) ...[
            const SizedBox(height: _kCardInnerGap),
            // `1a`: the strip's order is the order the model receives.
            Row(
              children: [
                Icon(Icons.drag_indicator, size: AppSize.iconSm, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpace.s4),
                Expanded(
                  child: Text(
                    l10n.selectionReorderHint,
                    style: textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (notice != null) ...[
            const SizedBox(height: _kCardInnerGap),
            notice,
          ],
        ],
      ),
    );
  }

  /// Warns when the selected model can't use the images the user has picked as
  /// references (Imagen accepts none; OpenAI image caps the count).
  ///
  /// `A1 · 1c` 「琥珀提示条」: 11px warning ink on the warning container, r6.
  /// Null when there is nothing to say.
  Widget? _buildReferenceImageNotice(
      BuildContext context, LLMModel? model, int selectedCount, AppLocalizations l10n) {
    if (model == null || selectedCount == 0) return null;

    // As the channel serves it: a relay model pinned to the Images API has
    // that surface's reference-image ceiling, which its id cannot report.
    final caps = Provider.of<AppState>(context, listen: false).descriptorForModel(model).capabilities;
    String? message;
    if (!caps.supportsReferenceImages) {
      message = l10n.referenceImagesNotSupported;
    } else if (caps.maxReferenceImages != null && selectedCount > caps.maxReferenceImages!) {
      message = l10n.referenceImagesLimited(caps.maxReferenceImages!);
    }
    if (message == null) return null;

    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: AppSize.iconSm, color: semantic.warning),
          ),
          const SizedBox(width: AppSpace.s4),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: semantic.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// One picked image in the selection strip: the picture at r10, its send
/// order in an accent disc, and a remove button on the image plate.
class _SelectionThumb extends StatelessWidget {
  const _SelectionThumb({
    required this.image,
    required this.index,
    this.onRemove,
    this.lift = 0,
  });

  final AppImage image;
  final int index;
  final VoidCallback? onRemove;

  /// 0 at rest, 1 fully picked up.
  final double lift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget thumb = SizedBox(
      width: _kThumbSize,
      height: _kThumbSize,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Image(image: image.imageProvider, fit: BoxFit.cover),
            ),
          ),
          // The same number the grid tile carries, because this is the same
          // fact: the order these are handed to the model. This strip is where
          // the order is actually *edited*, so the two halves of one idea must
          // name a picture the same way.
          Positioned(
            top: _kThumbInset,
            left: _kThumbInset,
            child: Container(
              width: _kThumbBadge,
              height: _kThumbBadge,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
              child: Text(
                '${index + 1}',
                style: theme.textTheme.labelSmall?.mono.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          ),
          // On the fixed image plate, never the theme: this sits on the user's
          // own photograph, where a tinted chip disappears into a picture in
          // that hue.
          Positioned(
            top: _kThumbInset,
            right: _kThumbInset,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: _kThumbBadge,
                height: _kThumbBadge,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppOverlay.imagePlate, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: AppSize.iconSm, color: AppOverlay.onImagePlate),
              ),
            ),
          ),
        ],
      ),
    );

    if (lift > 0) {
      final double t = lift.clamp(0.0, 1.0);
      thumb = Transform.translate(
        offset: Offset(0, -_kThumbLift * t),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            boxShadow: [
              BoxShadow(color: colorScheme.primary.withValues(alpha: t), spreadRadius: 2),
            ],
          ),
          child: thumb,
        ),
      );
    }
    return thumb;
  }
}
