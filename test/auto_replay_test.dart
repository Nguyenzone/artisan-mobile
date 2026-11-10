import 'dart:io';

import 'package:artisan_mobile/logic/auto_events.dart';
import 'package:artisan_mobile/logic/auto_replay.dart';
import 'package:artisan_mobile/models/roast_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AUTO: đặt thông số lúc CHARGE và chỉnh lại tại các mốc BT của profile mẫu', () {
    final tpl = RoastProfile.fromAlogString(File('assets/profiles/profile_mau_rang_vua.alog').readAsStringSync());
    final r = AutoReplay(tpl);
    expect(r.chargeValues[3], equals(70)); // Gas lúc CHARGE
    // Mẻ mới: BT lúc CHARGE thấp hơn mẻ mẫu 15°C
    final p = RoastProfile();
    final det = AutoEventDetector();
    final applied = <String>[];
    for (var i = 0; i < tpl.timex.length; i++) {
      p.timex.add(tpl.timex[i]);
      p.bt.add(tpl.bt[i] - 15);
      p.et.add(tpl.et[i]);
      p.ct.add(-1);
      det.check(p, const AutoEventParams());
      r.step(p).forEach((t, v) => applied.add('$t=$v@${p.bt.last.toStringAsFixed(0)}'));
    }
    expect(applied.any((a) => a.startsWith('0=40')), isTrue); // Quạt lúc CHARGE
    expect(applied.any((a) => a.startsWith('3=70')), isTrue);
    expect(applied.any((a) => a.startsWith('3=58')), isTrue); // Gas 58 tại mốc BT ~150
    expect(r.pendingCount, lessThanOrEqualTo(2));
  });
}
