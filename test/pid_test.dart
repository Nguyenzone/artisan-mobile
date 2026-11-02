import 'package:artisan_mobile/logic/pid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PID bám theo đường BT tăng dần, đầu ra trong 0..100%', () {
    double et = 230, bt = 90, gas = 50;
    final pid = Pid()..control = (d) => gas = d;
    pid.on();
    var t = 0.0;
    var maxErr = 0.0;
    for (var k = 0; k < 300; k++) {
      t += 2;
      final sv = 90 + (t / 600) * 115;
      pid.setTarget(sv);
      for (var j = 0; j < 8; j++) {
        et += ((150 + 1.6 * gas) - et) * 0.25 / 25;
        bt += (et - bt) * 0.25 / 220;
      }
      pid.update(bt, t);
      expect(gas, inInclusiveRange(0, 100));
      if (t > 300) maxErr = (bt - sv).abs() > maxErr ? (bt - sv).abs() : maxErr;
    }
    expect(maxErr, lessThan(8));
  });
}
