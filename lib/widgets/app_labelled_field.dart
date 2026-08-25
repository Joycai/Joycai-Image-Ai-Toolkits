import 'package:flutter/material.dart';

/// A caption over the control it names.
///
/// The form idiom every settled frame draws — `A1 16a`/`17b`'s model card,
/// `D2 13a`/`13c`'s model editor, `15a`/`15c`'s channel editor: an 11px
/// semibold caption, 4px, then the control. Not Material's floating
/// `labelText`, which lives *inside* the box and shrinks when the field has a
/// value.
///
/// Not a variant of [InputDecoration] because the controls under it are not
/// all inputs: a picker, a dropdown and a segmented track all take this
/// caption, and only one of them has a decoration to put a label into.
///
/// There were three byte-identical copies of this — here, `_labelled` in the
/// model editor, and `ChannelLabelledField` in the channel form. Each doc
/// comment named the other two ("same shape as…"), so the duplication was
/// known the whole time; what was missing was a place to put the one copy,
/// and it only appeared once a *third* screen needed it.
class AppLabelledField extends StatelessWidget {
  const AppLabelledField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Merged so a screen reader announces the caption and the control it names
    // as one thing. The control carries its own button role and value; without
    // this the caption is a separate stop that reads "Channel" and nothing else.
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
