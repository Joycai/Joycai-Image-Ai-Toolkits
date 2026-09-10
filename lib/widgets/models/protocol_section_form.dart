import '../../services/llm/vendors/vendors.dart';

/// The shape the model editor's 「请求方式」 section takes (spec D2a rulings
/// 1 and 2, frames 20a–20e).
///
/// Decided in one pure function rather than in the dialog's build so the
/// rule can be tested without standing up the app.
enum ProtocolSectionForm {
  /// Not built at all: nothing to choose and nothing to explain (18a state ①,
  /// and Midjourney's fixed route). No heading, no placeholder height.
  none,

  /// A real choice — more than one option — or a stale selection that needs
  /// its explanation somewhere (18a state ④).
  dropdown,

  /// Exactly one route for a model its id does not identify (20d). Shown,
  /// because the user needs to see how it will be sent, but as a plain line:
  /// a disabled dropdown would say something is broken, and nothing is.
  readOnly,

  /// The channel has no interface for this kind of model (20e). The heading
  /// stays so the right column keeps its shape; the body is one sentence.
  notice,
}

/// Which [ProtocolSectionForm] a menu resolves to.
///
/// Ruling 1: the section exists when the menu offers more than one option or
/// the id is not recognized — a recognized model with a single route has
/// nothing to say. Ruling 2: a media kind the channel cannot serve at all is
/// a notice, never an empty control.
ProtocolSectionForm protocolSectionForm(ProtocolMenu? menu,
    {required bool pinIsStale}) {
  if (menu == null) return ProtocolSectionForm.none;
  if (menu.fixed) {
    return pinIsStale ? ProtocolSectionForm.dropdown : ProtocolSectionForm.none;
  }
  if (menu.options.length > 1) return ProtocolSectionForm.dropdown;
  final media = menu.surface != Surface.chat;
  if (media && menu.auto == null) return ProtocolSectionForm.notice;
  if (media && !menu.recognized) return ProtocolSectionForm.readOnly;
  return pinIsStale ? ProtocolSectionForm.dropdown : ProtocolSectionForm.none;
}

/// Whether the 「参数」 source row appears under the section (ruling 4).
///
/// Only for an image or video model whose id is not recognized, and only
/// where a route exists: a recognized model uses its own parameter table,
/// which needs no explaining, and a notice has no parameters to talk about.
bool showsParamSourceRow(ProtocolMenu? menu, ProtocolSectionForm form) =>
    menu != null &&
    menu.surface != Surface.chat &&
    !menu.recognized &&
    (form == ProtocolSectionForm.dropdown ||
        form == ProtocolSectionForm.readOnly);
