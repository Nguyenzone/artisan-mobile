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
    this.dataType = 'int16',
    this.divider = 10,
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

/// Cấu hình một thanh trượt điều khiển (Air / Drum / Damper / Burner).
class ControlConfig {
  ControlConfig({
    required this.label,
    this.visible = true,
    this.modbusEnabled = true,
    this.slaveId = 1,
    this.address = 10,
    this.useFc16 = false,
    this.min = 0,
    this.max = 100,
    this.step = 5,
    this.factor = 1,
    this.offset = 0,
    this.unit = '%',
  });

  String label;
  bool visible;
  bool modbusEnabled;
  int slaveId;
  int address;
  bool useFc16;
  int min;
  int max;
  int step;
  double factor; // giá trị ghi = round(giá trị * factor + offset)
  double offset;
  String unit;

  int toRegister(double v) => (v * factor + offset).round();

  Map<String, dynamic> toJson() => {
        'label': label,
        'visible': visible,
        'modbusEnabled': modbusEnabled,
        'slaveId': slaveId,
        'address': address,
        'useFc16': useFc16,
        'min': min,
        'max': max,
        'step': step,
        'factor': factor,
        'offset': offset,
        'unit': unit,
      };

  factory ControlConfig.fromJson(Map<String, dynamic> j, ControlConfig def) => ControlConfig(
        label: j['label'] as String? ?? def.label,
        visible: j['visible'] as bool? ?? def.visible,
        modbusEnabled: j['modbusEnabled'] as bool? ?? def.modbusEnabled,
        slaveId: (j['slaveId'] as num?)?.toInt() ?? def.slaveId,
        address: (j['address'] as num?)?.toInt() ?? def.address,
        useFc16: j['useFc16'] as bool? ?? def.useFc16,
        min: (j['min'] as num?)?.toInt() ?? def.min,
        max: (j['max'] as num?)?.toInt() ?? def.max,
        step: (j['step'] as num?)?.toInt() ?? def.step,
        factor: (j['factor'] as num?)?.toDouble() ?? def.factor,
        offset: (j['offset'] as num?)?.toDouble() ?? def.offset,
        unit: j['unit'] as String? ?? def.unit,
      );
}

/// Toàn bộ cài đặt của ứng dụng (lưu trong settings.json).
class AppSettings {
  // Kết nối
  bool simulator = true;
  String host = '192.168.1.100';
  int port = 502;
  int timeoutMs = 1000;
  double samplingInterval = 2.0;

  // Kênh nhiệt độ
  InputChannelConfig bt = _defBT();
  InputChannelConfig et = _defET();
  InputChannelConfig ct = _defCT();

  // Điều khiển: thứ tự giống etypes của Artisan: 0 Air, 1 Drum, 2 Damper, 3 Burner
  List<ControlConfig> controls = _defControls();

  // Đồ thị
  double tempMin = 0;
  double tempMax = 275;
  double rorMin = 0;
  double rorMax = 25;
  double rorSpan = 20; // giây (Artisan mặc định 20s)
  int rorSmoothing = 3;
  int timeMaxMinutes = 15;
  bool showCT = true;
  bool showDeltaET = true;
  bool showDeltaBT = true;
  bool showBackground = true;
  bool showEventSteps = true;
  bool keepScreenOn = true;

  // Khác
  String? backgroundFile; // tên file trong thư viện
  bool sampleInstalled = false;

  static InputChannelConfig _defBT() => InputChannelConfig(address: 0);
  static InputChannelConfig _defET() => InputChannelConfig(address: 1);
  static InputChannelConfig _defCT() => InputChannelConfig(address: 2);

  static List<ControlConfig> _defControls() => [
        ControlConfig(label: 'Quạt', address: 11),
        ControlConfig(label: 'Trống', address: 12),
        ControlConfig(label: 'Van gió', address: 13, visible: false),
        ControlConfig(label: 'Gas', address: 10),
      ];

  static const List<String> etypeNames = ['Air', 'Drum', 'Damper', 'Burner'];

  Map<String, dynamic> toJson() => {
        'simulator': simulator,
        'host': host,
        'port': port,
        'timeoutMs': timeoutMs,
        'samplingInterval': samplingInterval,
        'bt': bt.toJson(),
        'et': et.toJson(),
        'ct': ct.toJson(),
        'controls': controls.map((c) => c.toJson()).toList(),
        'tempMin': tempMin,
        'tempMax': tempMax,
        'rorMin': rorMin,
        'rorMax': rorMax,
        'rorSpan': rorSpan,
        'rorSmoothing': rorSmoothing,
        'timeMaxMinutes': timeMaxMinutes,
        'showCT': showCT,
        'showDeltaET': showDeltaET,
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

    s.simulator = g<bool>('simulator') ?? s.simulator;
    s.host = g<String>('host') ?? s.host;
    s.port = g<num>('port')?.toInt() ?? s.port;
    s.timeoutMs = g<num>('timeoutMs')?.toInt() ?? s.timeoutMs;
    s.samplingInterval = g<num>('samplingInterval')?.toDouble() ?? s.samplingInterval;
    final bt = g<Map<String, dynamic>>('bt');
    if (bt != null) s.bt = InputChannelConfig.fromJson(bt, _defBT());
    final et = g<Map<String, dynamic>>('et');
    if (et != null) s.et = InputChannelConfig.fromJson(et, _defET());
    final ct = g<Map<String, dynamic>>('ct');
    if (ct != null) s.ct = InputChannelConfig.fromJson(ct, _defCT());
    final cl = g<List<dynamic>>('controls');
    if (cl != null) {
      final defs = _defControls();
      for (var i = 0; i < defs.length && i < cl.length; i++) {
        final e = cl[i];
        if (e is Map<String, dynamic>) s.controls[i] = ControlConfig.fromJson(e, defs[i]);
      }
    }
    s.tempMin = g<num>('tempMin')?.toDouble() ?? s.tempMin;
    s.tempMax = g<num>('tempMax')?.toDouble() ?? s.tempMax;
    s.rorMin = g<num>('rorMin')?.toDouble() ?? s.rorMin;
    s.rorMax = g<num>('rorMax')?.toDouble() ?? s.rorMax;
    s.rorSpan = g<num>('rorSpan')?.toDouble() ?? s.rorSpan;
    s.rorSmoothing = g<num>('rorSmoothing')?.toInt() ?? s.rorSmoothing;
    s.timeMaxMinutes = g<num>('timeMaxMinutes')?.toInt() ?? s.timeMaxMinutes;
    s.showCT = g<bool>('showCT') ?? s.showCT;
    s.showDeltaET = g<bool>('showDeltaET') ?? s.showDeltaET;
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
