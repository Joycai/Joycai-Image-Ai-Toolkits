import 'package:flutter/material.dart';

/// A caption over the control it names.
///
/// The form idiom both workbench panels use, and the one `A1 16a` / `17b` draw
/// for every field in the model card: an 11px semibold caption, 4px, then the
/// control — rather than Material's floating `labelText`, which lives *inside*
/// the box and shrinks when the field has a value.
///
/// Not a variant of [InputDecoration] because the controls under it are not
/// all inputs: a picker, a dropdown and a segmented track all take this
/// caption, and only one of them has a decoration to put a label into.
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
