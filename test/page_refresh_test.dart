import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itp_voice/design/widgets/v360_live_list.dart';
import 'package:itp_voice/helpers/page_refresh.dart';

void main() {
  test('first-page changes retain the row displaced onto page two', () {
    expect(mergeFirstPage([0, 1, 2], [1, 2, 3, 4], (n) => n, hasMore: true),
        [0, 1, 2, 3, 4]);
    expect(
        mergeFirstPage([2, 4], [1, 2, 3, 4], (n) => n, hasMore: false), [2, 4]);
  });

  testWidgets(
      'a refresh prepending variable-height rows keeps the visible row in place',
      (tester) async {
    final scroll = ScrollController();
    final initial = List<int>.generate(100, (i) => i);
    Widget screen(List<int> ids) => MaterialApp(
            home: V360LiveList(
          ids: ids,
          controller: scroll,
          itemBuilder: (_, i) => SizedBox(
              height: ids[i].isEven ? 64 : 80, child: Text('Row ${ids[i]}')),
        ));
    await tester.pumpWidget(screen(initial));
    scroll.jumpTo(1000);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('Row 16'));
    await tester.pumpWidget(screen([-2, -1, ...initial]));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Row 16')), before);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
