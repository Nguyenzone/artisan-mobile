import 'package:artisan_mobile/alog/python_literal.dart';
import 'package:artisan_mobile/logic/ror.dart';
import 'package:artisan_mobile/models/roast_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PythonLiteral', () {
    test('đọc các kiểu cơ bản', () {
      final v = PythonLiteral.parse(
          "{'a': 1, 'b': -2.5, 'c': 'x\\'y', \"d\": [True, False, None], 'e': (1, 2), 'f': u'Cà phê', 'g': 1e-05}");
      expect(v, isA<Map>());
      final m = v as Map;
      expect(m['a'], equals(1));
      expect(m['b'], equals(-2.5));
      expect(m['c'], equals("x'y"));
      expect(m['d'], equals([true, false, null]));
      expect(m['e'], equals([1, 2]));
      expect(m['f'], equals('Cà phê'));
      expect(m['g'], closeTo(0.00001, 1e-12));
    });

    test('ghi giống repr() của Python', () {
      expect(PythonLiteral.write({'a': 1.0, 'b': 'it\'s', 'c': [true, null], 'd': 2}),
          equals("{'a': 1.0, 'b': \"it's\", 'c': [True, None], 'd': 2}"));
      expect(PythonLiteral.write('a\nb\\c'), equals(r"'a\nb\\c'"));
    });

    test('ghi rồi đọc lại không đổi', () {
      final data = {
        'title': 'Mẻ "thử" số 1 \'A\'',
        'timex': [0.0, 2.0, 4.5],
        'nested': {'x': -1, 'y': <dynamic>[]},
      };
      final back = PythonLiteral.parse(PythonLiteral.write(data));
      expect(back, equals(data));
    });
  });

  group('RoastProfile .alog', () {
    RoastProfile makeProfile() {
      final p = RoastProfile(samplingInterval: 2);
      for (var i = 0; i < 300; i++) {
        final t = i * 2.0;
        p.timex.add(t);
        p.et.add(220 + i * 0.05);
        p.bt.add(i < 40 ? 200 - i * 3.0 : 80 + (i - 40) * 0.5);
        p.ct.add(500);
      }
      p.hasCT = true;
      p.setEvent(RoastEvent.charge, 10);
      p.setEvent(RoastEvent.dryEnd, 150);
      p.setEvent(RoastEvent.fcStart, 250);
      p.setEvent(RoastEvent.drop, 290);
      p.events.add(SpecialEvent(index: 10, type: 3, value: 60));
      p.events.add(SpecialEvent(index: 150, type: 3, value: 45));
      p.title = 'Thử nghiệm';
      p.weightIn = 1000;
      p.weightOut = 850;
      return p;
    }

    test('ghi và đọc lại giữ nguyên dữ liệu', () {
      final p = makeProfile();
      final text = p.toAlogString();
      final q = RoastProfile.fromAlogString(text);
      expect(q.timex.length, equals(300));
      expect(q.timeindex, equals(p.timeindex));
      expect(q.title, equals('Thử nghiệm'));
      expect(q.hasCT, isTrue);
      expect(q.ct[5], equals(500.0));
      expect(q.events.length, equals(2));
      expect(q.events[1].value, equals(45));
      expect(q.weightOut, equals(850));
      expect(q.effectiveTP, isNotNull);
    });

    test('giá trị sự kiện theo quy ước Artisan (v/10 + 1)', () {
      expect(eventExternalToInternal(60), equals(7.0));
      expect(eventInternalToExternal(7.0), equals(60));
      expect(eventInternalToExternal(1.0), equals(0));
    });
  });

  test('RoR của đường thẳng 10°C/phút', () {
    final t = [for (var i = 0; i < 100; i++) i * 2.0];
    final y = [for (final x in t) 100 + x / 6.0];
    final r = computeRoR(t, y, span: 20, smoothing: 3);
    expect(r.last, closeTo(10.0, 1e-6));
  });
}
