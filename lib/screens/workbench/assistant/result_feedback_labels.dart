import '../../../l10n/app_localizations.dart';
import '../../../models/result_feedback.dart';
import '../../../services/assistant/prompt_optimizer_agent.dart';

/// The localized label of one `3b` reason tag. One switch for the dialog,
/// the transcript card and the timeline, so a tag reads the same everywhere.
String resultFeedbackReasonLabel(AppLocalizations l10n, ResultFeedbackReason reason) =>
    switch (reason) {
      ResultFeedbackReason.promptMismatch => l10n.optFeedbackReasonPromptMismatch,
      ResultFeedbackReason.composition => l10n.optFeedbackReasonComposition,
      ResultFeedbackReason.colorLight => l10n.optFeedbackReasonColorLight,
      ResultFeedbackReason.detail => l10n.optFeedbackReasonDetail,
      ResultFeedbackReason.style => l10n.optFeedbackReasonStyle,
    };

/// 「满意」 / 「不满意」.
String resultFeedbackVerdictLabel(AppLocalizations l10n, bool satisfied) =>
    satisfied ? l10n.optFeedbackSatisfied : l10n.optFeedbackUnsatisfied;

/// One line standing for a feedback entry where only one fits (the
/// iteration timeline): the user's own words when they wrote any, else the
/// verdict and its tags — a rating alone is a complete report (`3b`).
String resultFeedbackSummary(AppLocalizations l10n, OptimizerChatEntry entry) {
  if (entry.text.isNotEmpty) return entry.text;
  final satisfied = entry.feedbackSatisfied;
  if (satisfied == null) return '';
  return [
    resultFeedbackVerdictLabel(l10n, satisfied),
    for (final r in entry.feedbackReasons) resultFeedbackReasonLabel(l10n, r),
  ].join(' · ');
}
