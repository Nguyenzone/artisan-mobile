/// Tính RoR (Rate of Rise, °C/phút) giống cách Artisan làm:
/// hồi quy tuyến tính trên cửa sổ `span` giây gần nhất, sau đó làm mượt
/// bằng trung bình trượt `smoothing` mẫu.
///
/// Trả về danh sách cùng độ dài với [t]; phần tử null = không có giá trị.
List<double?> computeRoR(
  List<double> t,
  List<double> y, {
  double span = 20,
  int smoothing = 3,
  int startIndex = 0,
}) {
  final n = t.length < y.length ? t.length : y.length;
  final raw = List<double?>.filled(n, null);
  if (n < 2) return raw;
  final first = startIndex < 0 ? 0 : startIndex;
  var j = first;
  for (var i = first; i < n; i++) {
    if (y[i] < 0) continue;
    while (j < i && t[i] - t[j] > span) {
      j++;
    }
    // hồi quy tuyến tính trên các điểm hợp lệ trong [j..i]
    var cnt = 0;
    double sx = 0, sy = 0, sxx = 0, sxy = 0;
    final t0 = t[i];
    for (var k = j; k <= i; k++) {
      final v = y[k];
      if (v < 0) continue;
      final x = t[k] - t0;
      cnt++;
      sx += x;
      sy += v;
      sxx += x * x;
      sxy += x * v;
    }
    if (cnt < 2) continue;
    final den = cnt * sxx - sx * sx;
    if (den.abs() < 1e-9) continue;
    final slope = (cnt * sxy - sx * sy) / den; // °C / giây
    raw[i] = slope * 60.0;
  }
  if (smoothing <= 1) return raw;
  final out = List<double?>.filled(n, null);
  for (var i = 0; i < n; i++) {
    if (raw[i] == null) continue;
    double s = 0;
    var c = 0;
    for (var k = i; k >= 0 && k > i - smoothing; k--) {
      final v = raw[k];
      if (v != null) {
        s += v;
        c++;
      }
    }
    out[i] = c > 0 ? s / c : null;
  }
  return out;
}
