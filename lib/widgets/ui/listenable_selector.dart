import 'package:flutter/widgets.dart';

/// A [ListenableBuilder] that rebuilds only when [selector]'s answer changes.
///
/// `provider`'s `Selector` for a plain [Listenable]: a notifier that fires for
/// many reasons (a session notifying on every request of a turn) would
/// otherwise rebuild a whole subtree for each, including the reasons that
/// subtree never shows. The answer is compared with `==` — a record of the
/// values the builder reads is the usual shape, with lists the notifier
/// replaces rather than mutates, so identity stands for their content.
class ListenableSelector<T> extends StatefulWidget {
  const ListenableSelector({
    super.key,
    required this.listenable,
    required this.selector,
    required this.builder,
  });

  final Listenable listenable;
  final T Function() selector;
  final WidgetBuilder builder;

  @override
  State<ListenableSelector<T>> createState() => _ListenableSelectorState<T>();
}

class _ListenableSelectorState<T> extends State<ListenableSelector<T>> {
  late T _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selector();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ListenableSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listenable, widget.listenable)) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    // A rebuild from above builds anyway; keep the answer current with it.
    _selected = widget.selector();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = widget.selector();
    if (next == _selected) return;
    setState(() => _selected = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
