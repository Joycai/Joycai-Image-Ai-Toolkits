import '../../../../services/llm/param_spec.dart';

/// Presentation can be replaced independently of a parameter's constraints.
/// Default hints adapt the existing declarations to preserve the current UI.
class ParamPresentation {
  const ParamPresentation({this.editor, this.fullRow});
  final ParamControl? editor;
  final bool? fullRow;

  ParamControl editorFor(ParamSpec spec) => editor ?? spec.control;
  bool fullRowFor(ParamSpec spec) =>
      fullRow ??
      (editorFor(spec) == ParamControl.customSize ||
          editorFor(spec) == ParamControl.slider ||
          editorFor(spec) == ParamControl.segmented && spec.options.length > 2);
}
