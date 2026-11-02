import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Cấu hình một kênh đọc nhiệt độ qua Modbus.
class InputChannelConfig {
  InputChannelConfig({
    this.enabled = true,
    this.slaveId = 1,
    this.address = 0,
    this.functionCode = 3,
    this.dataType = 'uint16',
    this.divider = 1,
    this.offset = 0,
  });

  bool enabled;
  int slaveId;
  int address;
  int functionCode; // 3 = holding, 4 = input
  String dataType; // int16, uint16, int32, uint32, float32, float32_cdab
  double divider; // 1, 10, 100 ...
  double offset; // hiệu chỉnh °C

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'slaveId': slaveId,
        'address': address,
        'functionCode': functionCode,
        'dataType': dataType,
        'divider': divider,
        'offset': offset,
      };

  factory InputChannelConfig.fromJson(Map<String, dynamic> j, InputChannelConfig def) => InputChannelConfig(
        enabled: j['enabled'] as bool? ?? def.enabled,
        slaveId: (j['slaveId'] as num?)?.toInt() ?? def.slaveId,
        address: (j['address'] as num?)?.toInt() ?? def.address,
        functionCode: (j['functionCode'] as num?)?.toInt() ?? def.functionCode,
        dataType: j['dataType'] as String? ?? def.dataType,
        divider: (j['divider'] as num?)?.toDouble() ?? def.divider,
        offset: (j['offset'] as num?)?.toDouble() ?? def.offset,
      );
}

/// Thanh trượt điều khiển (Artisan: Config > Events > Sliders).
class ControlConfig {
  ControlConfig({
    required this.label,
    this.visible = true,
    this.command = '',
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.factor = 1,
    this.offset = 0,
    this.unit = '',
  });

  String label;
  bool visible;
  String command; // Modbus Command, ví dụ write([3,0,{}])
  int min;
  int max;
  int step;
  double factor; // {} = round(giá trị * factor + offset)
  double offset;
  String unit;

  int toRegister(double v) => (v * factor + offset).round();

  Map<String, dynamic> toJson() => {
        'label': label,
        'visible': visible,
        'command': command,
        'min': min,
        'max': max,
        'step': step,
        'factor': factor,
        'offset': offset,
        'unit': unit,
      };

  factory ControlConfig.fromJson(Map<String, dynamic> j, ControlConfig def) {
    var cmd = j['command'] as String?;
    if (cmd == null && j['address'] != null) {
      // tương thích cài đặt của phiên bản 1
      final s = (j['slaveId'] as num?)?.toInt() ?? 1;
      final a = (j['address'] as num).toInt();
      final fc16 = j['useFc16'] == true;
      final enabled = j['modbusEnabled'] != false;
      cmd = !enabled ? '' : (fc16 ? 'writem($s,$a,{})' : 'write([$s,$a,{}])');
    }
    return ControlConfig(
      label: j['label'] as String? ?? def.label,
      visible: j['visible'] as bool? ?? def.visible,
      command: cmd ?? def.command,
      min: (j['min'] as num?)?.toInt() ?? def.min,
      max: (j['max'] as num?)?.toInt() ?? def.max,
      step: (j['step'] as num?)?.toInt() ?? def.step,
      factor: (j['factor'] as num?)?.toDouble() ?? def.factor,
      offset: (j['offset'] as num?)?.toDouble() ?? def.offset,
      unit: j['unit'] as String? ?? def.unit,
    );
  }
}

/// Loại nút sự kiện – cùng mã số với Artisan (Config > Events > Buttons > Type).
class ButtonType {
  static const int air = 0;
  static const int drum = 1;
  static const int damper = 2;
  static const int burner = 3;
  static const int none = 4; // " " – chỉ gửi lệnh, không ghi sự kiện
  static const int relAir = 5; // ±Air
  static const int relDrum = 6; // ±Drum
  static const int relDamper = 7; // ±Damper
  static const int relBurner = 8; // ±Burner

  static const Map<int, String> names = {
    none: '(không)',
    air: 'Air',
    drum: 'Drum',
    damper: 'Damper',
    burner: 'Burner',
    relAir: '±Air',
    relDrum: '±Drum',
    relDamper: '±Damper',
    relBurner: '±Burner',
  };
}

/// Nút sự kiện tuỳ chỉnh (Artisan: Config > Events > Buttons).
class EventButtonConfig {
  EventButtonConfig({
    required this.label,
    this.type = ButtonType.none,
    this.value = 0,
    this.command = '',
    this.color = 0xFF147BB3,
    this.textColor = 0xFFFFFFFF,
    this.visible = true,
  });

  String label;
  int type;
  int value;
  String command;
  int color; // ARGB
  int textColor;
  bool visible;

  Map<String, dynamic> toJson() => {
        'label': label,
        'type': type,
        'value': value,
        'command': command,
        'color': color,
        'textColor': textColor,
        'visible': visible,
      };

  factory EventButtonConfig.fromJson(Map<String, dynamic> j) => EventButtonConfig(
        label: j['label'] as String? ?? 'Nút',
        type: (j['type'] as num?)?.toInt() ?? ButtonType.none,
        value: (j['value'] as num?)?.toInt() ?? 0,
        command: j['command'] as String? ?? '',
        color: (j['color'] as num?)?.toInt() ?? 0xFF147BB3,
        textColor: (j['textColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        visible: j['visible'] as bool? ?? true,
      );

  EventButtonConfig copy() => EventButtonConfig.fromJson(toJson());
}

/// Toàn bộ cài đặt của ứng dụng (lưu trong settings.json).
class AppSettings {
  static const int currentVersion = 2;

  // Kết nối
  String host = '10.10.100.254';
  int port = 502;
  int timeoutMs = 1000;
  double samplingInterval = 2.0;
  bool littleEndianWords = true;

  // Kênh nhiệt độ (theo cấu hình Artisan của máy rang Minh Đăng)
  InputChannelConfig bt = _defBT();
  InputChannelConfig et = _defET();
  InputChannelConfig ct = _defCT();

  // Điều khiển: thứ tự giống etypes của Artisan: 0 Air, 1 Drum, 2 Damper, 3 Burner
  List<ControlConfig> controls = defaultControls();

  // Nút sự kiện tuỳ chỉnh
  List<EventButtonConfig> buttons = defaultButtons();

  // Tự động đánh dấu sự kiện
  bool autoCharge = true;
  bool autoTP = true;
  bool autoDryEnd = true;
  double dryEndTemp = 150;
  bool autoFcStart = true;
  double fcStartTemp = 198;
  bool autoDrop = true;

  // Rang tự động: PID bám BT của profile nền (Artisan: PID > Background Follow)
  double pidKp = 15.0;
  double pidKi = 0.01;
  double pidKd = 20.0;
  int pidLookahead = 0; // giây – Artisan "Lookahead"
  int pidTarget = 3; // thanh trượt nhận đầu ra PID: 0 Air, 1 Drum, 2 Damper, 3 Burner
  int pidDutyMin = 0; // %
  int pidDutyMax = 100; // %
  int pidDutySteps = 1;
  bool pidStopAtDrop = true;

  // Đồ thị
  double tempMin = 0;
  double tempMax = 275;
  double rorMin = 0;
  double rorMax = 25;
  double rorSpan = 20; // giây (Artisan mặc định 20s)
  int rorSmoothing = 3;
  int timeMaxMinutes = 15;
  bool showCT = true;
  bool showDeltaBT = true;
  bool showBackground = true;
  bool showEventSteps = true;
  bool keepScreenOn = true;

  // Khác
  String? backgroundFile; // tên file trong thư viện
  bool sampleInstalled = false;

  static InputChannelConfig _defET() => InputChannelConfig(slaveId: 1, address: 0); // Artisan Input 1
  static InputChannelConfig _defBT() => InputChannelConfig(slaveId: 2, address: 0); // Artisan Input 2
  static InputChannelConfig _defCT() => InputChannelConfig(slaveId: 5, address: 0); // Artisan Input 6

  static List<ControlConfig> defaultControls() => [
        ControlConfig(label: 'Quạt', command: 'write([3,1,{}])', max: 99),
        ControlConfig(label: 'Trống', command: 'write([3,2,{}])', max: 99),
        ControlConfig(label: 'Van gió', command: '', visible: false),
        ControlConfig(label: 'Gas', command: 'write([3,0,{}])', max: 99),
      ];

  static List<EventButtonConfig> defaultButtons() => [
        EventButtonConfig(label: 'Air/ Drum', command: 'write([3,4,1])', color: 0xFF0B5E0B),
        EventButtonConfig(label: 'Air+', type: ButtonType.relAir, value: 5, command: 'writem(3,1,{})', color: 0xFF0D0D8A),
        EventButtonConfig(label: 'Air-', type: ButtonType.relAir, value: -5, command: 'writem(3,1,{})', color: 0xFF808080),
        EventButtonConfig(label: 'Burner', command: 'write([3,5,1])', color: 0xFFF01414),
        EventButtonConfig(label: 'Burner+', type: ButtonType.relBurner, value: 5, command: 'writem(3,0,{})', color: 0xFFA30E0E),
        EventButtonConfig(label: 'Burn-', type: ButtonType.relBurner, value: -5, command: 'writem(3,0,{})', color: 0xFF808080),
        EventButtonConfig(label: 'Cool.Fan', command: 'write([3,7,1])', color: 0xFFF2A07E),
        EventButtonConfig(label: 'Mix', command: 'write([3,6,1])', color: 0xFFF2A07E),
      ];

  static const List<String> etypeNames = ['Air', 'Drum', 'Damper', 'Burner'];

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'host': host,
        'port': port,
        'timeoutMs': timeoutMs,
        'samplingInterval': samplingInterval,
        'littleEndianWords': littleEndianWords,
        'bt': bt.toJson(),
        'et': et.toJson(),
        'ct': ct.toJson(),
        'controls': controls.map((c) => c.toJson()).toList(),
        'buttons': buttons.map((b) => b.toJson()).toList(),
        'autoCharge': autoCharge,
        'autoTP': autoTP,
        'autoDryEnd': autoDryEnd,
        'dryEndTemp': dryEndTemp,
        'autoFcStart': autoFcStart,
        'fcStartTemp': fcStartTemp,
        'autoDrop': autoDrop,
        'pidKp': pidKp,
        'pidKi': pidKi,
        'pidKd': pidKd,
        'pidLookahead': pidLookahead,
        'pidTarget': pidTarget,
        'pidDutyMin': pidDutyMin,
        'pidDutyMax': pidDutyMax,
        'pidDutySteps': pidDutySteps,
        'pidStopAtDrop': pidStopAtDrop,
        'tempMin': tempMin,
        'tempMax': tempMax,
        'rorMin': rorMin,
        'rorMax': rorMax,
        'rorSpan': rorSpan,
        'rorSmoothing': rorSmoothing,
        'timeMaxMinutes': timeMaxMinutes,
        'showCT': showCT,
        'showDeltaBT': showDeltaBT,
        'showBackground': showBackground,
        'showEventSteps': showEventSteps,
        'keepScreenOn': keepScreenOn,
        'backgroundFile': backgroundFile,
        'sampleInstalled': sampleInstalled,
      };

  static AppSettings fromJson(Map<String, dynamic> j) {
    final s = AppSettings();
    T? g<T>(String k) {
      final v = j[k];
      return v is T ? v : null;
    }

    final version = g<num>('version')?.toInt() ?? 1;
    // Phiên bản 1 dùng địa chỉ mẫu – chuyển sang cấu hình máy rang thật (theo Artisan)
    if (version >= 2) {
      s.host = g<String>('host') ?? s.host;
      s.port = g<num>('port')?.toInt() ?? s.port;
      s.timeoutMs = g<num>('timeoutMs')?.toInt() ?? s.timeoutMs;
      s.littleEndianWords = g<bool>('littleEndianWords') ?? s.littleEndianWords;
      final bt = g<Map<String, dynamic>>('bt');
      if (bt != null) s.bt = InputChannelConfig.fromJson(bt, _defBT());
      final et = g<Map<String, dynamic>>('et');
      if (et != null) s.et = InputChannelConfig.fromJson(et, _defET());
      final ct = g<Map<String, dynamic>>('ct');
      if (ct != null) s.ct = InputChannelConfig.fromJson(ct, _defCT());
      final cl = g<List<dynamic>>('controls');
      if (cl != null) {
        final defs = defaultControls();
        for (var i = 0; i < defs.length && i < cl.length; i++) {
          final e = cl[i];
          if (e is Map<String, dynamic>) s.controls[i] = ControlConfig.fromJson(e, defs[i]);
        }
      }
      final bl = g<List<dynamic>>('buttons');
      if (bl != null) {
        s.buttons = [
          for (final e in bl)
            if (e is Map<String, dynamic>) EventButtonConfig.fromJson(e)
        ];
      }
    }
    s.samplingInterval = g<num>('samplingInterval')?.toDouble() ?? s.samplingInterval;
    s.autoCharge = g<bool>('autoCharge') ?? s.autoCharge;
    s.autoTP = g<bool>('autoTP') ?? s.autoTP;
    s.autoDryEnd = g<bool>('autoDryEnd') ?? s.autoDryEnd;
    s.dryEndTemp = g<num>('dryEndTemp')?.toDouble() ?? s.dryEndTemp;
    s.autoFcStart = g<bool>('autoFcStart') ?? s.autoFcStart;
    s.fcStartTemp = g<num>('fcStartTemp')?.toDouble() ?? s.fcStartTemp;
    s.autoDrop = g<bool>('autoDrop') ?? s.autoDrop;
    s.pidKp = g<num>('pidKp')?.toDouble() ?? s.pidKp;
    s.pidKi = g<num>('pidKi')?.toDouble() ?? s.pidKi;
    s.pidKd = g<num>('pidKd')?.toDouble() ?? s.pidKd;
    s.pidLookahead = g<num>('pidLookahead')?.toInt() ?? s.pidLookahead;
    s.pidTarget = g<num>('pidTarget')?.toInt() ?? s.pidTarget;
    s.pidDutyMin = g<num>('pidDutyMin')?.toInt() ?? s.pidDutyMin;
    s.pidDutyMax = g<num>('pidDutyMax')?.toInt() ?? s.pidDutyMax;
    s.pidDutySteps = g<num>('pidDutySteps')?.toInt() ?? s.pidDutySteps;
    s.pidStopAtDrop = g<bool>('pidStopAtDrop') ?? s.pidStopAtDrop;
    s.tempMin = g<num>('tempMin')?.toDouble() ?? s.tempMin;
    s.tempMax = g<num>('tempMax')?.toDouble() ?? s.tempMax;
    s.rorMin = g<num>('rorMin')?.toDouble() ?? s.rorMin;
    s.rorMax = g<num>('rorMax')?.toDouble() ?? s.rorMax;
    s.rorSpan = g<num>('rorSpan')?.toDouble() ?? s.rorSpan;
    s.rorSmoothing = g<num>('rorSmoothing')?.toInt() ?? s.rorSmoothing;
    s.timeMaxMinutes = g<num>('timeMaxMinutes')?.toInt() ?? s.timeMaxMinutes;
    s.showCT = g<bool>('showCT') ?? s.showCT;
    s.showDeltaBT = g<bool>('showDeltaBT') ?? s.showDeltaBT;
    s.showBackground = g<bool>('showBackground') ?? s.showBackground;
    s.showEventSteps = g<bool>('showEventSteps') ?? s.showEventSteps;
    s.keepScreenOn = g<bool>('keepScreenOn') ?? s.keepScreenOn;
    s.backgroundFile = g<String>('backgroundFile');
    s.sampleInstalled = g<bool>('sampleInstalled') ?? s.sampleInstalled;
    return s;
  }

  AppSettings clone() => fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/artisan_mobile_settings.json');
  }

  static Future<AppSettings> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, dynamic>) return fromJson(j);
      }
    } catch (_) {}
    return AppSettings();
  }

  Future<void> save() async {
    try {
      final f = await _file();
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
    } catch (_) {}
  }
}
