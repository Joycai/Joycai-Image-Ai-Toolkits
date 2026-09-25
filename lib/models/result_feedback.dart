/// What the user said about one generated result (`A1 · 3b`): a thumbs
/// up/down, the reasons behind a thumbs down, and an optional note.
///
/// The verdict is the required part — the dialog cannot send without one —
/// and the note may be empty, so "no feedback" is a null [ResultFeedback],
/// never an empty note.
class ResultFeedback {
  final bool satisfied;

  /// Why it fell short. Only meaningful with `satisfied == false`; a thumbs
  /// up carries none.
  final List<ResultFeedbackReason> reasons;

  /// The free-text critique, trimmed; may be empty.
  final String note;

  const ResultFeedback({required this.satisfied, this.reasons = const [], this.note = ''});
}

/// The reason tags under 「不满意」 (`3b`), with the ids they travel under in
/// the feedback message's JSON header — stable and English, since the model
/// reads them, while the labels are localized at the surface.
enum ResultFeedbackReason {
  promptMismatch('prompt_mismatch'),
  composition('composition'),
  colorLight('color_light'),
  detail('detail'),
  style('style');

  const ResultFeedbackReason(this.wireId);

  final String wireId;

  /// The reason for a header id, or null for one this build does not know
  /// (a session written by a newer build degrades to "no tag", not a crash).
  static ResultFeedbackReason? fromWireId(String id) {
    for (final r in values) {
      if (r.wireId == id) return r;
    }
    return null;
  }
}
