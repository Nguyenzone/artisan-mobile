import '../models/roast_profile.dart';

/// Tham số tự nhận diện sự kiện.
class AutoEventParams {
  const AutoEventParams({
    this.autoCharge = true,
    this.autoTP = true,
    this.autoDryEnd = true,
    this.dryEndTemp = 150,
    this.autoFcStart = true,
    this.fcStartTemp = 198,
    this.autoDrop = true,
  });

  final bool autoCharge;
  final bool autoTP;
  final bool autoDryEnd;
  final double dryEndTemp;
  final bool autoFcStart;
  final double fcStartTemp;
  final bool autoDrop;
}

/// Tự nhận diện CHARGE, TP, DRY END, FC START, DROP – chuyển từ logic của Artisan
/// (canvas.py: sample() / main.py: BTbreak, checkTop, findTPint; tham số "Standard",
/// chu kỳ lấy mẫu ≥ 1 giây).
class AutoEventDetector {
  bool _afterTP = false;
  bool chargeDisabled = false; // người dùng đã bỏ CHARGE tự động -> không tự nhận lại
  bool dropDisabled = false;

  void reset() {
    _afterTP = false;
    chargeDisabled = false;
    dropDisabled = false;
  }

  // btbreak_params của Artisan (autoChargeMode/autoDropMode = Standard, delay >= 1000 ms)
  static const double _dCharge = -0.67;
  static const double _offsetCharge = 0.5;
  static const double _dDrop = -0.34;
  static const double _offsetDrop = 0.2;
  static const double _dpreDpostDiff = 0.78;
  static const int _tight = 3;
  static const int _loose = 5;
  static const double _f = 2.5;
  static const double _maxdpre = 6.4;
  static const double _fDtwice = 1.5;
  static const double tpMaxRoastTime = 120; // giây

  static bool _checkTop(double d, double offset, double diff, List<double> p, {bool twice = false}) {
    if (p.any((v) => v < 0)) return false; // bỏ qua lần đọc lỗi (-1)
    final d1 = p[0] - p[1];
    final d2 = p[1] - p[2];
    final d3 = p[4] - p[3];
    final d4 = p[5] - p[4];
    final dpre = (d1 + d2) / 2.0;
    final dpost = (d3 + d4) / 2.0;
    final dd = twice ? d * _fDtwice : d;
    final lim = _maxdpre < offset + _f * dpre.abs() ? _maxdpre : offset + _f * dpre.abs();
    return d3 < dd && d4 < dd && ((dpost.abs() > lim) || (dpost < 0 && dpre < 0 && (-dpre - dpost) > diff));
  }

  /// Trả về độ lệch b > 0 nếu nhận ra BT "gãy" (giảm đột ngột) tại chỉ số i - b + 1, ngược lại 0.
  static int btBreak(List<double> bt, int i, {required bool drop}) {
    final d = drop ? _dDrop : _dCharge;
    final off = drop ? _offsetDrop : _offsetCharge;
    if (bt.length > 5 && 4 < i && i < bt.length) {
      if (_checkTop(d, off, _dpreDpostDiff, [bt[i - 5], bt[i - 4], bt[i - 3], bt[i - 2], bt[i - 1], bt[i]])) {
        return _tight;
      }
      if (bt.length > 10 &&
          i > 10 &&
          _checkTop(d, off, _dpreDpostDiff, [bt[i - 10], bt[i - 8], bt[i - 6], bt[i - 4], bt[i - 2], bt[i]],
              twice: true)) {
        return _loose;
      }
    }
    return 0;
  }

  /// TP = BT thấp nhất từ CHARGE tới FCs/DROP (Artisan: findTPint).
  static int findTP(RoastProfile p) {
    var tp = 1000.0;
    var idx = 0;
    var start = 0;
    var end = p.timex.length;
    final drop = p.timeindex[EventIdx.drop];
    if (drop > 0 && drop < end) end = drop;
    final fcs = p.timeindex[EventIdx.fcStart];
    if (fcs > 0 && fcs < end) end = fcs;
    final charge = p.timeindex[EventIdx.charge];
    if (charge >= 0 && start < charge && charge < end) start = charge;
    for (var i = end - 1; i >= start; i--) {
      final v = p.bt[i];
      if (v > 0 && v < tp) {
        tp = v;
        idx = i;
      }
    }
    return idx;
  }

  bool _checkTPalarmtime(RoastProfile p) {
    final bt = p.bt;
    final n = bt.length;
    final since = p.timex.last - p.chargeTime;
    if (since > 20 &&
        !_afterTP &&
        n > 4 &&
        bt[n - 5] >= 0 &&
        bt[n - 5] <= bt[n - 4] &&
        bt[n - 5] <= bt[n - 3] &&
        bt[n - 5] <= bt[n - 2] &&
        bt[n - 5] <= bt[n - 1] &&
        bt[n - 5] < bt[n - 1]) {
      _afterTP = true;
    }
    return _afterTP;
  }

  /// Gọi sau mỗi lần lấy mẫu. Trả về các sự kiện cần đánh dấu (sự kiện, chỉ số mẫu).
  List<(RoastEvent, int)> check(RoastProfile p, AutoEventParams s) {
    final out = <(RoastEvent, int)>[];
    final n = p.timex.length;
    if (n == 0) return out;
    final btNow = p.bt.last;

    // CHARGE: BT giảm đột ngột, chỉ khi BT > 77°C
    if (s.autoCharge && !chargeDisabled && !p.hasCharge && n >= 5 && btNow > 77) {
      final b = btBreak(p.bt, n - 1, drop: false);
      if (b > 0) {
        final idx = n - b;
        p.setEvent(RoastEvent.charge, idx);
        out.add((RoastEvent.charge, idx));
      }
    } else if (s.autoTP &&
        p.hasCharge &&
        p.tpIndex == null &&
        p.timex.last - p.chargeTime > tpMaxRoastTime) {
      // 2 phút sau CHARGE mà chưa thấy TP -> đặt TP tại thời điểm hiện tại (như Artisan)
      p.tpIndex = n - 1;
      out.add((RoastEvent.tp, n - 1));
    } else if (s.autoTP &&
        p.hasCharge &&
        p.tpIndex == null &&
        p.indexOf(RoastEvent.dryEnd) == null &&
        p.timeindex[EventIdx.charge] + 8 < n &&
        _checkTPalarmtime(p)) {
      final tp = findTP(p);
      if (tp > 0 && p.bt[tp] > 50 && p.bt[tp] < 150) {
        p.tpIndex = tp;
        out.add((RoastEvent.tp, tp));
      }
    }

    // DROP: BT giảm đột ngột, sau CHARGE ít nhất 7 phút và BT > 160°C
    if (s.autoDrop &&
        !dropDisabled &&
        p.hasCharge &&
        p.indexOf(RoastEvent.drop) == null &&
        n >= 5 &&
        btNow > 160 &&
        p.timex.last - p.chargeTime > 7 * 60) {
      final b = btBreak(p.bt, n - 1, drop: true);
      if (b > 0) {
        final idx = n - b;
        p.setEvent(RoastEvent.drop, idx);
        out.add((RoastEvent.drop, idx));
      }
    }

    final tpKnown = p.tpIndex != null || (p.hasCharge && p.timex.last - p.chargeTime > tpMaxRoastTime);
    final dropped = p.indexOf(RoastEvent.drop) != null;
    // DRY END: BT vượt ngưỡng (mặc định 150°C)
    if (s.autoDryEnd &&
        tpKnown &&
        p.hasCharge &&
        !dropped &&
        p.indexOf(RoastEvent.dryEnd) == null &&
        p.indexOf(RoastEvent.fcStart) == null &&
        btNow >= s.dryEndTemp &&
        n - 1 > p.timeindex[EventIdx.charge]) {
      p.setEvent(RoastEvent.dryEnd, n - 1);
      out.add((RoastEvent.dryEnd, n - 1));
    }
    // FC START: BT vượt ngưỡng (mặc định 198°C)
    if (s.autoFcStart &&
        tpKnown &&
        p.hasCharge &&
        !dropped &&
        p.indexOf(RoastEvent.fcStart) == null &&
        btNow >= s.fcStartTemp &&
        (p.indexOf(RoastEvent.dryEnd) ?? 0) < n - 1 &&
        n - 1 > p.timeindex[EventIdx.charge]) {
      p.setEvent(RoastEvent.fcStart, n - 1);
      out.add((RoastEvent.fcStart, n - 1));
    }
    return out;
  }
}
