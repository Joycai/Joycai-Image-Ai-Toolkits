import 'package:flutter/material.dart';

import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/pricing_group.dart';
import '../../screens/models/widgets/model_card.dart';
import 'model_edit_controls.dart';

/// 「卡片预览」: the models screen's own [ModelCard], drawn from the form as it
/// stands, in the column-coloured r10 frame D1c `1a` puts around it.
///
/// The card is the real one rather than a restatement, so the preview cannot
/// drift from the list. It is given no callbacks, which is how it knows to
/// draw no edit or delete buttons.
class ModelEditCardPreview extends StatelessWidget {
  const ModelEditCardPreview({
    super.key,
    required this.model,
    this.channel,
    this.feeGroup,
  });

  /// The in-progress model — unsaved, built from the form.
  final LLMModel model;

  /// Lets the card tell a stale protocol selection from a valid one.
  final LLMChannel? channel;
  final PricingGroup? feeGroup;

  @override
  Widget build(BuildContext context) {
    final metrics = ModelEditMetrics.of(context);
    return ExcludeSemantics(
      child: ModelEditCard(
        padding: const EdgeInsets.all(8),
        child: ModelCard(
          model: model,
          channel: channel,
          feeGroup: feeGroup,
          // The phone density drops the chips, which are the point of a
          // preview; the phone form takes the tablet density instead.
          size: metrics.phone ? ModelCardSize.compact : ModelCardSize.regular,
        ),
      ),
    );
  }
}
