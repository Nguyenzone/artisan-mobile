import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/roast_profile.dart';
import '../services/settings.dart';
import 'artisan_colors.dart';

/// Đồ thị mẻ rang kiểu Artisan: ET, BT, CT, ΔET, ΔBT, đường nền, sự kiện.
class RoastChart extends StatelessWidget {
  const RoastChart({
    super.key,
    required this.profile,
    required this.rorBT,
    required this.rorET,
    required this.settings,
    this.background,
    this.bgRorBT = const [],
    this.liveTime,
  });

  final RoastProfile profile;
  final List<double?> rorBT;
  final List<double?> rorET;
  final AppSettings settings;
  final RoastProfile? background;
  final List<double?> bgRorBT;
  final double? liveTime;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _RoastChartPainter(this),
        size: Size.infinite,
      ),
    );
  }
}

class _RoastChartPainter extends CustomPainter {
  _RoastChartPainter(this.w);

  final RoastChart w;

  late Rect plot;
  late double xMin, xMax, tMin, tMax, rMin, rMax;

  double xOf(double rel) => plot.left + (rel - xMin) / (xMax - xMin) * plot.width;
  double yT(double temp) => plot.bottom - (temp - tMin) / (tMax - tMin) * plot.height;
  double yR(double ror) => plot.bottom - (ror - rMin) / (rMax - rMin) * plot.height;

  static Color _alpha(Color c, int a) => c.withAlpha(a);

  void _text(Canvas canvas, String s, Offset at,
      {Color color = AC.axisLabel,
      double size = 10,
      FontWeight weight = FontWeight.normal,
      double ax = 0,
      double ay = 0,
      Color? box,
      Color? border}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: weight, height: 1.15)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final off = Offset(at.dx - tp.width * ax, at.dy - tp.height * ay);
    if (box != null) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(off.dx - 3, off.dy - 1, tp.width + 6, tp.height + 2), const Radius.circular(3));
      canvas.drawRRect(r, Paint()..color = box);
      if (border != null) {
        canvas.drawRRect(
            r,
            Paint()
              ..color = border
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
    tp.paint(canvas, off);
    tp.dispose();
  }

  void _series(Canvas canvas, List<double> t, int n, double t0, double? Function(int i) val,
      double Function(double) yMap, Paint paint,
      {int start = 0}) {
    final path = Path();
    var pen = false;
    for (var i = math.max(0, start); i < n && i < t.length; i++) {
      final v = val(i);
      if (v == null) {
        pen = false;
        continue;
      }
      final x = xOf(t[i] - t0);
      final y = yMap(v);
      if (!pen) {
        path.moveTo(x, y);
        pen = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  Paint _line(Color c, double width) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    final s = w.settings;
    final p = w.profile;
    const left = 40.0, right = 34.0, top = 20.0, bottom = 22.0;
    plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    canvas.drawRect(Offset.zero & size, Paint()..color = AC.canvas);
    if (plot.width < 60 || plot.height < 60) return;
    canvas.drawRect(plot, Paint()..color = AC.background);

    tMin = s.tempMin;
    tMax = s.tempMax > s.tempMin + 10 ? s.tempMax : s.tempMin + 10;
    rMin = s.rorMin;
    rMax = s.rorMax > s.rorMin + 1 ? s.rorMax : s.rorMin + 1;

    final charged = p.hasCharge;
    final t0 = p.chargeTime;
    final lastRel = p.timex.isEmpty ? 0.0 : p.timex.last - t0;
    xMin = charged ? -30.0 : 0.0;
    xMax = math.max(s.timeMaxMinutes * 60.0, lastRel + 60);
    final bg = s.showBackground ? w.background : null;
    if (bg != null && bg.timex.isNotEmpty) {
      final bgEnd = (bg.indexOf(RoastEvent.drop) != null ? bg.timex[bg.indexOf(RoastEvent.drop)!] : bg.timex.last) -
          bg.chargeTime;
      xMax = math.max(xMax, math.min(bgEnd + 60, 40 * 60.0));
    }

    _grid(canvas);
    _phaseBar(canvas, p);

    canvas.save();
    canvas.clipRect(plot);

    // ---------- đường nền
    if (bg != null && bg.timex.isNotEmpty) {
      final b0 = bg.chargeTime;
      final n = bg.timex.length;
      _series(canvas, bg.timex, n, b0, (i) => bg.et[i] < 0 ? null : bg.et[i], yT, _line(_alpha(AC.et, 0x55), 1.6));
      _series(canvas, bg.timex, n, b0, (i) => bg.bt[i] < 0 ? null : bg.bt[i], yT, _line(_alpha(AC.bt, 0x55), 1.6));
      if (s.showDeltaBT && w.bgRorBT.length == n) {
        _series(canvas, bg.timex, n, b0, (i) => w.bgRorBT[i], yR, _line(_alpha(AC.deltaBt, 0x40), 1.0),
            start: bg.hasCharge ? bg.timeindex[EventIdx.charge] + 1 : 0);
      }
      _bgEvents(canvas, bg);
    }

    // ---------- sự kiện điều khiển (bậc thang)
    if (s.showEventSteps) _eventSteps(canvas, p);

    final n = p.timex.length;
    final rorStart = charged ? p.timeindex[EventIdx.charge] + 1 : 0;
    // ---------- CT
    if (s.showCT && p.hasCT) {
      _series(canvas, p.timex, n, t0, (i) => (i < p.ct.length && p.ct[i] >= 0 && p.ct[i] <= tMax * 3) ? p.ct[i] : null, yT,
          _line(AC.ct, 1.2));
    }
    // ---------- ET, BT
    _series(canvas, p.timex, n, t0, (i) => p.et[i] < 0 ? null : p.et[i], yT, _line(AC.et, 2.0));
    _series(canvas, p.timex, n, t0, (i) => p.bt[i] < 0 ? null : p.bt[i], yT, _line(AC.bt, 2.4));
    // ---------- ΔET, ΔBT (trục phải)
    if (s.showDeltaET && w.rorET.length == n) {
      _series(canvas, p.timex, n, t0, (i) => w.rorET[i], yR, _line(AC.deltaEt, 1.0), start: rorStart);
    }
    if (s.showDeltaBT && w.rorBT.length == n) {
      _series(canvas, p.timex, n, t0, (i) => w.rorBT[i], yR, _line(AC.deltaBt, 1.4), start: rorStart);
    }
    canvas.restore();

    _annotations(canvas, p);
    _legend(canvas, p);

    canvas.drawRect(
        plot,
        Paint()
          ..color = const Color(0xFFBDBDBD)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  void _grid(Canvas canvas) {
    final gridPaint = Paint()
      ..color = AC.grid
      ..strokeWidth = 1;
    // trục thời gian
    final range = xMax - xMin;
    final step = range <= 21 * 60 ? 60.0 : (range <= 42 * 60 ? 120.0 : 300.0);
    var x = (xMin / step).ceil() * step;
    while (x <= xMax) {
      final px = xOf(x);
      canvas.drawLine(Offset(px, plot.top), Offset(px, plot.bottom), gridPaint);
      _text(canvas, (x / 60).round().toString(), Offset(px, plot.bottom + 3), ax: 0.5);
      x += step;
    }
    if (xMin < 0) {
      final px0 = xOf(0);
      canvas.drawLine(Offset(px0, plot.top), Offset(px0, plot.bottom),
          Paint()
            ..color = const Color(0xFFC8C8C8)
            ..strokeWidth = 1);
    }
    // trục nhiệt độ (trái)
    final tr = tMax - tMin;
    final tStep = tr > 200 ? 50.0 : (tr > 80 ? 25.0 : 10.0);
    var t = (tMin / tStep).ceil() * tStep;
    while (t <= tMax + 0.01) {
      final py = yT(t);
      canvas.drawLine(Offset(plot.left, py), Offset(plot.right, py), gridPaint);
      _text(canvas, t.round().toString(), Offset(plot.left - 4, py), ax: 1, ay: 0.5);
      t += tStep;
    }
    _text(canvas, '°C', Offset(plot.left - 4, plot.top - 3), ax: 1, ay: 1, size: 9);
    // trục RoR (phải)
    final rr = rMax - rMin;
    final rStep = rr > 40 ? 10.0 : (rr > 12 ? 5.0 : 1.0);
    var r = (rMin / rStep).ceil() * rStep;
    while (r <= rMax + 0.01) {
      _text(canvas, r.round().toString(), Offset(plot.right + 4, yR(r)), ax: 0, ay: 0.5);
      r += rStep;
    }
    _text(canvas, '°C/min', Offset(plot.right + 2, plot.top - 3), ax: 0.5, ay: 1, size: 9);
    _text(canvas, 'phút', Offset(plot.right + 4, plot.bottom + 3), size: 9);
  }

  void _phaseBar(Canvas canvas, RoastProfile p) {
    if (!p.hasCharge || p.timex.isEmpty) return;
    final now = w.liveTime ?? p.timex.last;
    final ph = p.phases(now: now);
    final t0 = p.chargeTime;
    final de = p.indexOf(RoastEvent.dryEnd);
    final fc = p.indexOf(RoastEvent.fcStart);
    final dr = p.indexOf(RoastEvent.drop);
    final end = dr != null ? p.timex[dr] : now;
    final barTop = plot.top - 16;
    final barH = 14.0;
    void seg(double a, double b, Color c, String label) {
      final x1 = xOf(a - t0).clamp(plot.left, plot.right).toDouble();
      final x2 = xOf(b - t0).clamp(plot.left, plot.right).toDouble();
      if (x2 - x1 < 1) return;
      final r = Rect.fromLTRB(x1, barTop, x2, barTop + barH);
      canvas.drawRect(r, Paint()..color = c);
      if (x2 - x1 > 46) {
        _text(canvas, label, r.center, ax: 0.5, ay: 0.5, size: 9, color: const Color(0xFF333333));
      }
    }

    String lbl(String name, double? d) {
      if (d == null) return name;
      final pct = ph.pct(d);
      return '$name ${fmtTime(d)}${pct != null ? ' ${pct.toStringAsFixed(0)}%' : ''}';
    }

    final deT = de != null ? p.timex[de] : end;
    seg(t0, deT, AC.phaseDry, lbl('Sấy', ph.drying));
    if (de != null) {
      final fcT = fc != null ? p.timex[fc] : end;
      seg(p.timex[de], fcT, AC.phaseMai, lbl('Maillard', ph.maillard));
    }
    if (fc != null) {
      seg(p.timex[fc], end, AC.phaseDev, lbl('Phát triển', ph.development));
    }
  }

  void _eventSteps(Canvas canvas, RoastProfile p) {
    if (p.events.isEmpty || p.timex.isEmpty) return;
    final t0 = p.chargeTime;
    final h = plot.height * 0.30;
    double yE(double v) => plot.bottom - (v.clamp(0, 100) / 100.0) * h;
    final endT = p.indexOf(RoastEvent.drop) != null ? p.timex[p.indexOf(RoastEvent.drop)!] : p.timex.last;
    for (var type = 0; type < 4; type++) {
      final evs = p.events.where((e) => e.type == type && e.index < p.timex.length).toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      if (evs.isEmpty) continue;
      final color = AC.eventColors[type];
      final path = Path();
      double? lastY;
      for (final e in evs) {
        final x = xOf(p.timex[e.index] - t0);
        final y = yE(e.value);
        if (lastY == null) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, lastY);
          path.lineTo(x, y);
        }
        lastY = y;
      }
      path.lineTo(xOf(endT - t0), lastY ?? plot.bottom);
      canvas.drawPath(path, _line(_alpha(color, 0xB0), 1.4));
      final letter = (type < p.etypes.length && p.etypes[type].isNotEmpty) ? p.etypes[type][0] : 'E';
      for (final e in evs) {
        _text(canvas, '$letter${e.value.round()}', Offset(xOf(p.timex[e.index] - t0), yE(e.value) - 2),
            ax: 0.5, ay: 1, size: 8.5, color: Colors.white, box: _alpha(color, 0xE0), weight: FontWeight.bold);
      }
    }
  }

  void _bgEvents(Canvas canvas, RoastProfile bg) {
    final b0 = bg.chargeTime;
    for (final e in RoastEvent.values) {
      final i = e == RoastEvent.tp ? bg.effectiveTP : bg.indexOf(e);
      if (i == null || bg.bt[i] < 0) continue;
      final x = xOf(bg.timex[i] - b0);
      final y = yT(bg.bt[i]);
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = _alpha(AC.bgEventMarker, 0xA0));
      _text(canvas, e.shortLabel, Offset(x, y + 4), size: 8, color: _alpha(AC.bgEventMarker, 0xC0), ax: 0.5);
    }
  }

  void _annotations(Canvas canvas, RoastProfile p) {
    if (p.timex.isEmpty) return;
    final t0 = p.chargeTime;
    var k = 0;
    for (final e in RoastEvent.values) {
      final i = e == RoastEvent.tp ? p.effectiveTP : p.indexOf(e);
      if (i == null || i >= p.bt.length || p.bt[i] < 0) continue;
      final rel = p.timex[i] - t0;
      if (rel < xMin || rel > xMax) continue;
      final x = xOf(rel);
      final y = yT(p.bt[i]);
      canvas.drawCircle(Offset(x, y), 3.2, Paint()..color = AC.markers);
      final txt = e == RoastEvent.charge
          ? '${e.shortLabel}\n${p.bt[i].toStringAsFixed(1)}°'
          : '${e.shortLabel} ${fmtTime(rel)}\n${p.bt[i].toStringAsFixed(1)}°';
      final up = k.isEven;
      var ly = up ? y - 30 : y + 10;
      if (ly < plot.top + 2) ly = y + 10;
      if (ly > plot.bottom - 28) ly = y - 30;
      final lx = x.clamp(plot.left + 30, plot.right - 30).toDouble();
      canvas.drawLine(Offset(x, y), Offset(lx, up ? ly + 24 : ly), _line(const Color(0xFF9E9E9E), 0.8));
      _text(canvas, txt, Offset(lx, ly),
          ax: 0.5, size: 9, color: AC.text, box: const Color(0xEEFFFFFF), border: _alpha(AC.bt, 0x80));
      k++;
    }
  }

  void _legend(Canvas canvas, RoastProfile p) {
    final items = <MapEntry<String, Color>>[
      const MapEntry('ET', AC.et),
      const MapEntry('BT', AC.bt),
      if (w.settings.showDeltaET) const MapEntry('ΔET', AC.deltaEt),
      if (w.settings.showDeltaBT) const MapEntry('ΔBT', AC.deltaBt),
      if (w.settings.showCT && p.hasCT) const MapEntry('CT', AC.ct),
    ];
    var x = plot.left + 8;
    final y = plot.top + 8;
    for (final it in items) {
      canvas.drawLine(Offset(x, y + 6), Offset(x + 14, y + 6), _line(it.value, it.key.startsWith('Δ') ? 1.2 : 2.2));
      _text(canvas, it.key, Offset(x + 17, y), size: 9.5, color: AC.text);
      x += 17 + (it.key.length * 7.0) + 10;
    }
  }

  @override
  bool shouldRepaint(covariant _RoastChartPainter oldDelegate) => true;
}
