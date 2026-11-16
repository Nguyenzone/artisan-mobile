import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../logic/roast_controller.dart';
import '../models/roast_profile.dart';
import 'artisan_colors.dart';

/// Ô LCD kiểu Artisan.
class Lcd extends StatelessWidget {
  const Lcd({
    super.key,
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
    this.labelColor,
  });

  final String label;
  final String value;
  final Color bg;
  final Color fg;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFBDBDBD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: labelColor ?? fg.withAlpha(0xC0))),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String fmtTemp(double? v) => (v == null || v < 0) ? '--.-' : v.toStringAsFixed(1);
String fmtRoR(double? v) => v == null ? '--.-' : v.toStringAsFixed(1);

/// Bộ LCD: Thời gian, ET, BT, ΔET, ΔBT, CT.
class LcdPanel extends StatelessWidget {
  const LcdPanel({super.key, required this.c, required this.vertical});

  final RoastController c;
  final bool vertical;

  double? _valueAt(List<double> l) {
    final p = c.profile;
    if (l.isEmpty) return null;
    final i = p.indexOf(RoastEvent.drop) ?? (l.length - 1);
    return i < l.length ? l[i] : null;
  }

  double? _rorAt(List<double?> l) {
    final p = c.profile;
    if (l.isEmpty) return null;
    final i = p.indexOf(RoastEvent.drop) ?? (l.length - 1);
    return i < l.length ? l[i] : null;
  }

  @override
  Widget build(BuildContext context) {
    final p = c.profile;
    final on = c.isOn;
    final et = on ? c.curET : _valueAt(p.et);
    final bt = on ? c.curBT : _valueAt(p.bt);
    final ct = on ? c.curCT : (p.hasCT ? _valueAt(p.ct) : null);
    final dbt = on ? c.deltaBT : _rorAt(c.rorBT);

    final timer = ValueListenableBuilder<double>(
      valueListenable: c.clock,
      builder: (context, clock, _) {
        double? t;
        if (on) {
          t = p.hasCharge ? clock - p.chargeTime : clock;
        } else if (p.timex.isNotEmpty) {
          final d = p.indexOf(RoastEvent.drop);
          t = d != null ? p.rel(d) : p.timex.last - p.chargeTime;
        }
        return Lcd(
          label: p.hasCharge ? 'THỜI GIAN' : (on ? 'TRƯỚC CHARGE' : 'THỜI GIAN'),
          value: t == null ? '00:00' : fmtTime(t),
          bg: AC.lcdTimerBg,
          fg: AC.lcdTimerFg,
        );
      },
    );

    final items = <Widget>[
      timer,
      Lcd(label: 'ET', value: fmtTemp(et), bg: AC.lcdEtBg, fg: Colors.white),
      Lcd(label: 'BT', value: fmtTemp(bt), bg: AC.lcdBtBg, fg: Colors.white),
      Lcd(label: 'ΔBT', value: fmtRoR(dbt), bg: AC.lcdDeltaBg, fg: AC.deltaBt),
      if (c.settings.ct.enabled || p.hasCT) Lcd(label: 'CT', value: fmtTemp(ct), bg: AC.lcdCtBg, fg: Colors.white),
      if (c.autoRoast && c.replay != null)
        Lcd(label: 'AUTO – mốc còn lại', value: '${c.replay!.pendingCount}', bg: AC.lcdSvBg, fg: Colors.white),
    ];

    if (vertical) {
      return Column(children: [for (final w in items) Expanded(child: w)]);
    }
    // nằm ngang: 2 hàng x 3 cột
    final row1 = items.take(3).toList();
    final row2 = items.skip(3).toList();
    return Column(
      children: [
        Expanded(child: Row(children: [for (final w in row1) Expanded(child: w)])),
        Expanded(child: Row(children: [for (final w in row2) Expanded(child: w)])),
      ],
    );
  }
}

/// Nút sự kiện kiểu Artisan (xanh; hồng khi đã đánh dấu).
class EventButton extends StatelessWidget {
  const EventButton({
    super.key,
    required this.label,
    required this.marked,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
    this.sub,
  });

  final String label;
  final String? sub;
  final bool marked;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bg = marked ? AC.buttonSelected : (enabled ? AC.buttonMajor : AC.buttonDisabled);
    final fg = (marked || enabled) ? Colors.white : const Color(0xFF9E9E9E);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 14)),
                    if (sub != null) Text(sub!, style: TextStyle(color: fg, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nút lệnh lớn ON / OFF / RESET.
class CommandButton extends StatelessWidget {
  const CommandButton({super.key, required this.label, required this.color, this.onPressed, this.width = 64});

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: SizedBox(
        width: width,
        child: Material(
          color: enabled ? color : AC.buttonDisabled,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onPressed,
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      color: enabled ? Colors.white : const Color(0xFF9E9E9E),
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thanh trượt điều khiển (dọc hoặc ngang) kiểu Artisan.
class ControlSlider extends StatelessWidget {
  const ControlSlider({super.key, required this.c, required this.index, required this.vertical});

  final RoastController c;
  final int index;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final cfg = c.settings.controls[index];
    final color = AC.eventColors[index];
    final min = cfg.min.toDouble();
    final max = cfg.max > cfg.min ? cfg.max.toDouble() : min + 1;
    final v = c.controlValues[index].clamp(min, max).toDouble();
    final step = cfg.step < 1 ? 1 : cfg.step;
    final enabled = c.isOn;

    void bump(int dir) {
      if (!enabled) return;
      final nv = (v + dir * step).clamp(min, max).toDouble();
      c.commitControl(index, nv);
    }

    final slider = TapStepSlider(
      value: v,
      min: min,
      max: max,
      step: step.toDouble(),
      tapStep: 5,
      color: color,
      enabled: enabled,
      onChanged: (x) => c.setControlLocal(index, x),
      onChangeEnd: (x) => c.commitControl(index, x),
    );

    final valueBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color),
      ),
      child: Text('${v.round()}${cfg.unit}',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
    );

    Widget smallBtn(IconData icon, int dir) => InkWell(
          onTap: enabled ? () => bump(dir) : null,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon, size: 20, color: enabled ? color : Colors.grey),
          ),
        );

    if (vertical) {
      return SizedBox(
        width: 58,
        child: Column(
          children: [
            const SizedBox(height: 4),
            FittedBox(child: valueBox),
            smallBtn(Icons.keyboard_arrow_up, 1),
            Expanded(child: RotatedBox(quarterTurns: 3, child: slider)),
            smallBtn(Icons.keyboard_arrow_down, -1),
            Text(cfg.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
          ],
        ),
      );
    }
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(cfg.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ),
          smallBtn(Icons.remove, -1),
          Expanded(child: slider),
          smallBtn(Icons.add, 1),
          SizedBox(width: 54, child: valueBox),
        ],
      ),
    );
  }
}

/// Nút sự kiện tuỳ chỉnh kiểu Artisan (màu tuỳ chọn, viền vàng khi đang bật).
class ArtisanButton extends StatelessWidget {
  const ArtisanButton({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    required this.pressed,
    required this.last,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color textColor;
  final bool pressed;
  final bool last;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? color : color.withAlpha(0x70);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: pressed
                  ? Border.all(color: const Color(0xFFFFD54F), width: 3)
                  : (last ? Border.all(color: Colors.white70, width: 1.5) : null),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ô dự đoán »DRY / »FCs kiểu Artisan (phases LCD).
class PredictionLcd extends StatelessWidget {
  const PredictionLcd({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
      decoration: BoxDecoration(
        color: const Color(0xFFE6E6E6),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFBDBDBD)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
          FittedBox(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF262626),
                    fontFeatures: [ui.FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

/// Thanh trượt chống bấm nhầm (màn hình nhỏ):
/// * Chỉ kéo được khi chạm vào CHẤM TRÒN.
/// * Chạm lên thanh phía trên chấm tròn = +[tapStep], phía dưới = −[tapStep].
/// Bọc trong RotatedBox để thành thanh dọc (toạ độ chạm tự xoay theo).
class TapStepSlider extends StatefulWidget {
  const TapStepSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
    required this.onChangeEnd,
    this.step = 1,
    this.tapStep = 5,
    this.enabled = true,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final double tapStep;
  final Color color;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<TapStepSlider> createState() => _TapStepSliderState();
}

class _TapStepSliderState extends State<TapStepSlider> {
  static const double _pad = 14; // lề hai đầu thanh
  static const double _thumbR = 11;
  static const double _hitR = 26; // bán kính vùng chạm của chấm tròn
  bool _dragging = false;
  double? _dragValue;

  double get _span => (widget.max - widget.min) <= 0 ? 1 : widget.max - widget.min;

  double _xOf(double v, double width) => _pad + (v - widget.min) / _span * (width - 2 * _pad);

  double _valueAt(double x, double width) {
    final t = ((x - _pad) / (width - 2 * _pad)).clamp(0.0, 1.0);
    var v = widget.min + t * _span;
    if (widget.step > 0) v = (v / widget.step).round() * widget.step;
    return v.clamp(widget.min, widget.max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final shown = _dragValue ?? widget.value;
      final thumbX = _xOf(shown, width);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down, // vị trí bắt đầu = chỗ đặt ngón tay
        onTapUp: !widget.enabled
            ? null
            : (d) {
                final dx = d.localPosition.dx;
                if ((dx - thumbX).abs() <= _hitR) return; // chạm đúng chấm tròn: không đổi
                final dir = dx > thumbX ? 1 : -1;
                final nv = (widget.value + dir * widget.tapStep).clamp(widget.min, widget.max).toDouble();
                if (nv != widget.value) widget.onChangeEnd(nv);
              },
        onHorizontalDragStart: !widget.enabled
            ? null
            : (d) {
                _dragging = (d.localPosition.dx - thumbX).abs() <= _hitR;
                if (_dragging) setState(() => _dragValue = widget.value);
              },
        onHorizontalDragUpdate: !widget.enabled
            ? null
            : (d) {
                if (!_dragging) return;
                final v = _valueAt(d.localPosition.dx, width);
                if (v != _dragValue) {
                  setState(() => _dragValue = v);
                  widget.onChanged(v);
                }
              },
        onHorizontalDragEnd: !widget.enabled
            ? null
            : (_) {
                if (_dragging && _dragValue != null) widget.onChangeEnd(_dragValue!);
                setState(() {
                  _dragging = false;
                  _dragValue = null;
                });
              },
        onHorizontalDragCancel: () => setState(() {
          _dragging = false;
          _dragValue = null;
        }),
        child: CustomPaint(
          size: Size(width, box.maxHeight.isFinite ? box.maxHeight : 40),
          painter: _TapStepSliderPainter(
            thumbX: thumbX,
            color: widget.enabled ? widget.color : Colors.grey,
            active: _dragging,
          ),
        ),
      );
    });
  }
}

class _TapStepSliderPainter extends CustomPainter {
  _TapStepSliderPainter({required this.thumbX, required this.color, required this.active});

  final double thumbX;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const pad = _TapStepSliderState._pad;
    final track = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(pad, cy), Offset(size.width - pad, cy), track..color = color.withAlpha(0x40));
    canvas.drawLine(Offset(pad, cy), Offset(thumbX, cy), track..color = color);
    if (active) {
      canvas.drawCircle(Offset(thumbX, cy), _TapStepSliderState._thumbR + 9, Paint()..color = color.withAlpha(0x33));
    }
    canvas.drawCircle(Offset(thumbX, cy), _TapStepSliderState._thumbR, Paint()..color = color);
    canvas.drawCircle(Offset(thumbX, cy), _TapStepSliderState._thumbR - 4, Paint()..color = Colors.white.withAlpha(0x55));
  }

  @override
  bool shouldRepaint(covariant _TapStepSliderPainter old) =>
      old.thumbX != thumbX || old.color != color || old.active != active;
}
