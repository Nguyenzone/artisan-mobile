import 'dart:ui' as ui;

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
    final det = on ? c.deltaET : _rorAt(c.rorET);
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
      Lcd(label: 'ΔET', value: fmtRoR(det), bg: AC.lcdDeltaBg, fg: AC.deltaEt),
      Lcd(label: 'ΔBT', value: fmtRoR(dbt), bg: AC.lcdDeltaBg, fg: AC.deltaBt),
      if (c.settings.ct.enabled || p.hasCT) Lcd(label: 'CT', value: fmtTemp(ct), bg: AC.lcdCtBg, fg: Colors.white),
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
    final divisions = ((max - min) / step).round();
    final enabled = c.isOn;

    void bump(int dir) {
      if (!enabled) return;
      final nv = (v + dir * step).clamp(min, max).toDouble();
      c.commitControl(index, nv);
    }

    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: color,
        thumbColor: color,
        inactiveTrackColor: color.withAlpha(0x40),
        trackHeight: 4,
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        value: v,
        min: min,
        max: max,
        divisions: divisions > 0 ? divisions : null,
        onChanged: enabled ? (x) => c.setControlLocal(index, x) : null,
        onChangeEnd: enabled ? (x) => c.commitControl(index, x) : null,
      ),
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
