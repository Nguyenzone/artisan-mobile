import 'package:artisan_mobile/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<double>> run(WidgetTester tester, Future<void> Function() act) async {
    final ends = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 328,
            height: 40,
            child: TapStepSlider(
              value: 50,
              min: 0,
              max: 100,
              color: Colors.red,
              onChanged: (_) {},
              onChangeEnd: ends.add,
            ),
          ),
        ),
      ),
    ));
    await act();
    await tester.pump();
    return ends;
  }

  // thanh rộng 328, lề 14 -> chấm tròn ở giữa (x = 164 trong thanh)
  testWidgets('Chạm lên thanh bên phải chấm tròn = +5', (tester) async {
    final ends = await run(tester, () async {
      final r = tester.getRect(find.byType(TapStepSlider));
      await tester.tapAt(Offset(r.left + 300, r.center.dy));
    });
    expect(ends, equals([55.0]));
  });

  testWidgets('Chạm lên thanh bên trái chấm tròn = −5', (tester) async {
    final ends = await run(tester, () async {
      final r = tester.getRect(find.byType(TapStepSlider));
      await tester.tapAt(Offset(r.left + 20, r.center.dy));
    });
    expect(ends, equals([45.0]));
  });

  testWidgets('Kéo từ chỗ không phải chấm tròn thì không đổi', (tester) async {
    final ends = await run(tester, () async {
      final r = tester.getRect(find.byType(TapStepSlider));
      await tester.dragFrom(Offset(r.left + 300, r.center.dy), const Offset(-100, 0));
    });
    expect(ends, isEmpty);
  });

  testWidgets('Kéo chấm tròn thì đổi giá trị', (tester) async {
    final ends = await run(tester, () async {
      final r = tester.getRect(find.byType(TapStepSlider));
      await tester.dragFrom(Offset(r.left + 164, r.center.dy), const Offset(60, 0));
    });
    expect(ends.length, equals(1));
    expect(ends.first, greaterThan(50));
  });
}
