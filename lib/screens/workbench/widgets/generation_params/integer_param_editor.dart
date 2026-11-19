import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../services/llm/param_spec.dart';
import '../../../../widgets/ui/app_text_field.dart';

/// A bounded integer draft. Empty text restores the declared default; input
/// outside the contract never replaces the current value or enters storage.
class IntegerParamEditor extends StatefulWidget {
  const IntegerParamEditor({
    super.key,
    required this.spec,
    required this.value,
    required this.hint,
    required this.onChanged,
  });
  final ParamSpec spec;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<IntegerParamEditor> createState() => _IntegerParamEditorState();
}

class _IntegerParamEditorState extends State<IntegerParamEditor> {
  late final _controller = TextEditingController(text: _text(widget.value));

  String _text(String value) => value == 'not_set' ? '' : value;

  @override
  void didUpdateWidget(IntegerParamEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != _text(widget.value)) {
      _controller.text = _text(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: _controller,
      hint: widget.hint,
      keyboardType: TextInputType.number,
      inputFormatters: [
        TextInputFormatter.withFunction((oldValue, newValue) {
          final text = newValue.text;
          return text.isEmpty || (int.tryParse(text) != null && widget.spec.isValid(text))
              ? newValue
              : oldValue;
        }),
      ],
      onChanged: (text) => widget.onChanged(text.isEmpty ? widget.spec.defaultValue : text),
    );
  }
}
