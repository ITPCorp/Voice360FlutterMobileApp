// Dial keypad: digits register on finger down (no gesture arena), so fast or
// sliding taps inside the Dial tab's TabBarView are not lost.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itp_voice/design/widgets/v360_dialpad.dart';

void main() {
  Future<List<String>> pump(WidgetTester tester, {VoidCallback? onPlus}) async {
    final got = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          // Same as the Dial tab (home_screen.dart): a pager that does not swipe.
          body: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
            Center(child: V360Dialpad(onKey: got.add, onPlus: onPlus)),
            const SizedBox(),
          ]),
        ),
      ),
    ));
    return got;
  }

  testWidgets('a digit registers on touch down, before the finger lifts', (t) async {
    final got = await pump(t);
    final g = await t.startGesture(t.getCenter(find.text('5')));
    await t.pump();
    expect(got, ['5']);
    await g.up();
  });

  testWidgets('10 fast taps = 10 digits', (t) async {
    final got = await pump(t);
    for (final d in '3055550123'.split('')) {
      final g = await t.startGesture(t.getCenter(find.text(d)));
      await t.pump(const Duration(milliseconds: 40));
      await g.up();
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(got.join(), '3055550123');
  });

  testWidgets('a sideways slide during the tap still counts', (t) async {
    final got = await pump(t);
    for (final d in '305'.split('')) {
      final g = await t.startGesture(t.getCenter(find.text(d)));
      await g.moveBy(const Offset(40, 0));
      await t.pump(const Duration(milliseconds: 30));
      await g.up();
      await t.pumpAndSettle();
    }
    expect(got.join(), '305');
  });

  testWidgets('two fingers on keys at once both count', (t) async {
    final got = await pump(t);
    final a = await t.createGesture(pointer: 11);
    final b = await t.createGesture(pointer: 12);
    await a.down(t.getCenter(find.text('1')));
    await b.down(t.getCenter(find.text('2')));
    await t.pump();
    await a.up();
    await b.up();
    expect(got, ['1', '2']);
  });

  testWidgets('holding 0 asks for +', (t) async {
    var plus = 0;
    final got = await pump(t, onPlus: () => plus++);
    final g = await t.startGesture(t.getCenter(find.text('0')));
    await t.pump(const Duration(milliseconds: 700));
    await g.up();
    expect(got, ['0']);
    expect(plus, 1);
    final g2 = await t.startGesture(t.getCenter(find.text('0')));
    await t.pump(const Duration(milliseconds: 100));
    await g2.up();
    await t.pump(const Duration(milliseconds: 700));
    expect(plus, 1, reason: 'a short tap on 0 stays 0');
  });

  testWidgets('(why the pager no longer swipes) a swipeable TabBarView drops the overlapping key',
      (t) async {
    final got = <String>[];
    await t.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          body: TabBarView(children: [
            Center(child: V360Dialpad(onKey: got.add)),
            const SizedBox(),
          ]),
        ),
      ),
    ));
    final a = await t.createGesture(pointer: 21);
    final b = await t.createGesture(pointer: 22);
    await a.down(t.getCenter(find.text('1')));
    await b.down(t.getCenter(find.text('2')));
    await t.pump();
    await a.up();
    await b.up();
    expect(got, ['1'], reason: 'documents the old Dial-tab bug');
  });
}
