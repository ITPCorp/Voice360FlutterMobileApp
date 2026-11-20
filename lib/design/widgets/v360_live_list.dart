import 'package:flutter/material.dart';

/// Builds visible rows only. If a refresh prepends rows while reading, the
/// original first row stays at scroll offset zero and new rows grow above it.
class V360LiveList extends StatefulWidget {
  const V360LiveList({
    super.key,
    required this.ids,
    required this.itemBuilder,
    this.controller,
    this.reverse = false,
    this.padding = EdgeInsets.zero,
    this.versionAt,
  });

  final List<Object> ids;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final bool reverse;
  final EdgeInsets padding;
  final Object? Function(int index)? versionAt;

  @override
  State<V360LiveList> createState() => _V360LiveListState();
}

class _V360LiveListState extends State<V360LiveList> {
  static const _center = ValueKey('center sliver');
  final _local = ScrollController();
  ScrollController get _scroll => widget.controller ?? _local;
  Map<Object, int> _indices = {};
  Set<Object> _inserted = {};
  int _pivot = 0;

  @override
  void initState() {
    super.initState();
    _index();
  }

  void _index() {
    _indices = {for (int i = 0; i < widget.ids.length; i++) widget.ids[i]: i};
  }

  @override
  void didUpdateWidget(V360LiveList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _indices;
    final anchor = oldWidget.ids.elementAtOrNull(_pivot);
    _index();
    _inserted = _indices.keys.where((id) => !previous.containsKey(id)).toSet();
    if (_scroll.hasClients &&
        (_scroll.offset - _scroll.position.minScrollExtent) > 1) {
      _pivot = _indices[anchor] ?? 0;
    } else {
      _pivot = 0;
    }
  }

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }

  Widget _section(bool leading) {
    return SliverList(
      key: leading ? null : _center,
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final index = leading ? _pivot - i - 1 : _pivot + i;
          final id = widget.ids[index];
          Widget row = widget.itemBuilder(context, index);
          final duration = MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160);
          if (widget.versionAt != null) {
            row = AnimatedSwitcher(
                duration: duration,
                child: KeyedSubtree(
                    key: ValueKey(widget.versionAt!(index)), child: row));
          }
          if (_inserted.remove(id) && duration != Duration.zero) {
            row = TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: duration,
              builder: (_, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: row,
            );
          }
          return KeyedSubtree(key: ValueKey(id), child: row);
        },
        childCount: leading ? _pivot : widget.ids.length - _pivot,
        findChildIndexCallback: (key) {
          if (key is! ValueKey) return null;
          final i = _indices[key.value];
          if (i == null || (i < _pivot) != leading) return null;
          return leading ? _pivot - i - 1 : i - _pivot;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
        controller: _scroll,
        center: _center,
        reverse: widget.reverse,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _section(true),
          _section(false),
          SliverToBoxAdapter(child: SizedBox(height: widget.padding.bottom)),
        ],
      );
}
