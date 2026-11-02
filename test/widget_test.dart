import 'package:artisan_mobile/models/roast_profile.dart';
import 'package:artisan_mobile/services/settings.dart';
import 'package:artisan_mobile/ui/roast_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Đồ thị vẽ được một mẻ rang có sự kiện và đường nền', (tester) async {
    final p = RoastProfile(samplingInterval: 2);
    for (var i = 0; i < 300; i++) {
      p.timex.add(i * 2.0);
      p.et.add(220 + i * 0.05);
      p.bt.add(i < 40 ? 200 - i * 3.0 : 80 + (i - 40) * 0.5);
      p.ct.add(480);
    }
    p.hasCT = true;
    p.setEvent(RoastEvent.charge, 10);
    p.setEvent(RoastEvent.dryEnd, 150);
    p.setEvent(RoastEvent.fcStart, 250);
    p.setEvent(RoastEvent.drop, 290);
    p.events.add(SpecialEvent(index: 10, type: 3, value: 60));
    final ror = List<double?>.generate(300, (i) => i > 10 ? 10.0 : null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: RoastChart(
            profile: p,
            rorBT: ror,
            rorET: ror,
            settings: AppSettings(),
            background: p.copy(),
            bgRorBT: ror,
          ),
        ),
      ),
    ));
    expect(find.byType(RoastChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
