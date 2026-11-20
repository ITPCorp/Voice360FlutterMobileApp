/// Replace the first page while keeping cached pages that follow its last row.
/// The overlap moves when a new item arrives at the start of the list.
List<T> mergeFirstPage<T>(List<T> fresh, List<T> old, Object? Function(T) id,
    {required bool hasMore}) {
  if (!hasMore || fresh.isEmpty || old.isEmpty) return [...fresh];
  final boundary = id(fresh.last);
  if (boundary == null) return [...fresh];
  final index = old.indexWhere((row) => id(row) == boundary);
  if (index < 0) return [...fresh];
  final seen = fresh.map(id).toSet();
  return [
    ...fresh,
    for (final row in old.skip(index + 1))
      if (id(row) == null || seen.add(id(row))) row,
  ];
}
