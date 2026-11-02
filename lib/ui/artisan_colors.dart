import 'package:flutter/material.dart';

/// Bảng màu lấy từ Artisan (canvas.py: palette, lcdpalette; styles.py).
class AC {
  AC._();

  // đồ thị
  static const background = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFF8F8F8);
  static const grid = Color(0xFFE5E5E5);
  static const axisLabel = Color(0xFF808080);
  static const et = Color(0xFFCC0F50);
  static const bt = Color(0xFF0A5C90);
  static const ct = Color(0xFFE07B00);
  static const deltaEt = Color(0xFFCC0F50);
  static const deltaBt = Color(0xFF0A5C90);
  static const markers = Color(0xFF000000);
  static const text = Color(0xFF000000);
  static const specialEventBox = Color(0xFFFF5871);
  static const bgEventMarker = Color(0xFF7F7F7F);
  static const title = Color(0xFF0C6AA6);

  // thanh giai đoạn (Drying / Maillard / Development)
  static const phaseDry = Color(0xFFD5E8C4);
  static const phaseMai = Color(0xFFF6DDB0);
  static const phaseDev = Color(0xFFE3B7A0);

  // màu 4 loại sự kiện điều khiển (EvalueColor_default)
  static const eventColors = [
    Color(0xFF43A7CF), // Air
    Color(0xFF49B160), // Drum
    Color(0xFF800080), // Damper
    Color(0xFFAD0427), // Burner
  ];

  // LCD
  static const lcdTimerBg = Color(0xFFF8F8F8);
  static const lcdTimerFg = Color(0xFF262626);
  static const lcdEtBg = Color(0xFFCC0F50);
  static const lcdBtBg = Color(0xFF0A5C90);
  static const lcdDeltaBg = Color(0xFFEBEBEB);
  static const lcdCtBg = Color(0xFFE07B00);

  // nút
  static const buttonMajor = Color(0xFF147BB3);
  static const buttonMajorDark = Color(0xFF116999);
  static const buttonSelected = Color(0xFFD4336A);
  static const buttonDisabled = Color(0xFFE0E0E0);
  static const buttonOn = Color(0xFFCC0F50);
  static const buttonOff = Color(0xFF3979AE);
  static const buttonReset = Color(0xFF4C97C3);
  static const window = Color(0xFFECECEC);
}
