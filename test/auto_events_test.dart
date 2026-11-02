import 'dart:io';

import 'package:artisan_mobile/logic/auto_events.dart';
import 'package:artisan_mobile/modbus/modbus_command.dart';
import 'package:artisan_mobile/models/roast_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Tự nhận CHARGE, TP, DRY END, FC START, DROP trên profile mẫu', () {
    final src = RoastProfile.fromAlogString(File('assets/profiles/profile_mau_rang_vua.alog').readAsStringSync());
    final p = RoastProfile();
    final det = AutoEventDetector();
    for (var i = 0; i < src.timex.length; i++) {
      p.timex.add(src.timex[i]);
      p.bt.add(src.bt[i]);
      p.et.add(src.et[i]);
      p.ct.add(-1);
      det.check(p, const AutoEventParams(dryEndTemp: 150, fcStartTemp: 198));
    }
    expect(p.timeindex[EventIdx.charge], equals(14));
    expect(p.tpIndex, equals(52));
    expect(p.bt[p.indexOf(RoastEvent.dryEnd)!], greaterThanOrEqualTo(150));
    expect(p.bt[p.indexOf(RoastEvent.fcStart)!], greaterThanOrEqualTo(198));
    expect(p.indexOf(RoastEvent.drop), equals(275));
  });

  test('Kiểm tra cú pháp lệnh Modbus kiểu Artisan', () {
    expect(ModbusCommandRunner.validate('write([3,4,1])'), isNull);
    expect(ModbusCommandRunner.validate('writem(3,1,{})'), isNull);
    expect(ModbusCommandRunner.validate('write([3,6,1]);sleep(0.5);write([3,6,0])'), isNull);
    expect(ModbusCommandRunner.validate('write(3,4'), isNotNull);
    expect(ModbusCommandRunner.substitute('writem(3,1,{})', value: 45), equals('writem(3,1,45)'));
  });
}
