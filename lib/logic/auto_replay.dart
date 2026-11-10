import '../models/roast_profile.dart';

/// Rang tự động bằng cách PHÁT LẠI các thay đổi Gas / Trống / Quạt / Van gió của
/// profile mẫu – giống Artisan "Playback Events" với kiểu phát lại theo BT
/// (canvas.py: playbackevent(), replayType = 1):
///
/// * Lúc CHARGE: đặt ngay các thanh trượt về giá trị của profile mẫu tại CHARGE
///   (không phụ thuộc BT lúc CHARGE của 2 mẻ có bằng nhau hay không).
/// * Trước TP: phát lại theo thời gian kể từ CHARGE (vì BT đang giảm).
/// * Sau TP: phát lại khi BT hiện tại đạt BT mà profile mẫu đã thay đổi thông số,
///   theo đúng thứ tự từng loại (mỗi lần lấy mẫu tối đa 1 sự kiện mỗi loại).
/// * Bỏ qua các thay đổi xảy ra sau DROP của profile mẫu.
class AutoReplay {
  AutoReplay(this.template) {
    final charge = template.timeindex[EventIdx.charge];
    final drop = template.indexOf(RoastEvent.drop);
    final sorted = [...template.events]..sort((a, b) => a.index.compareTo(b.index));
    for (final e in sorted) {
      if (e.type < 0 || e.type > 3) continue;
      if (e.index < 0 || e.index >= template.timex.length) continue;
      if (e.index <= charge) {
        chargeValues[e.type] = e.value; // giá trị cuối cùng tính tới lúc CHARGE
      } else if (drop == null || e.index <= drop) {
        _queues[e.type].add(e);
      }
    }
  }

  final RoastProfile template;

  /// Giá trị từng loại (0 Air, 1 Drum, 2 Damper, 3 Burner) tại CHARGE của profile mẫu.
  final Map<int, double> chargeValues = {};

  final List<List<SpecialEvent>> _queues = [[], [], [], []];
  final List<int> _next = [0, 0, 0, 0];
  bool chargeApplied = false;

  int get pendingCount {
    var n = 0;
    for (var t = 0; t < 4; t++) {
      n += _queues[t].length - _next[t];
    }
    return n;
  }

  int get totalCount => _queues.fold(0, (s, q) => s + q.length);

  /// Gọi khi mẻ rang hiện tại CHARGE: trả về các giá trị cần đặt ngay.
  Map<int, double> onCharge() {
    chargeApplied = true;
    return Map<int, double>.from(chargeValues);
  }

  /// Gọi sau mỗi lần lấy mẫu. Trả về {loại: giá trị} cần đặt (giá trị sau ghi đè giá trị trước).
  Map<int, double> step(RoastProfile p) {
    final out = <int, double>{};
    if (!p.hasCharge || p.timex.isEmpty || !template.hasCharge) return out;
    if (!chargeApplied) out.addAll(onCharge());
    final bt = p.bt.last;
    final now = p.timex.last - p.chargeTime;
    final afterTP = p.tpIndex != null;
    for (var t = 0; t < 4; t++) {
      final q = _queues[t];
      while (_next[t] < q.length) {
        final e = q[_next[t]];
        bool fire;
        if (afterTP) {
          final target = template.bt[e.index];
          fire = target >= 0 && bt >= 0 && bt >= target;
          if (fire) {
            out[t] = e.value;
            _next[t]++;
          }
          break; // theo BT: mỗi loại chỉ xét 1 sự kiện mỗi lần lấy mẫu, giữ đúng thứ tự
        }
        fire = template.rel(e.index) <= now;
        if (!fire) break;
        out[t] = e.value;
        _next[t]++;
      }
    }
    return out;
  }

  /// Danh sách các mốc của profile mẫu (để hiển thị): (loại, giá trị, BT, thời gian sau CHARGE).
  List<(int, double, double, double)> describe() => [
        for (var t = 0; t < 4; t++)
          for (final e in _queues[t]) (t, e.value, template.bt[e.index], template.rel(e.index))
      ]..sort((a, b) => a.$4.compareTo(b.$4));
}
