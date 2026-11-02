import 'dart:math' as math;

import '../modbus/modbus_command.dart';
import '../modbus/modbus_tcp.dart';
import 'settings.dart';

/// Một lần đọc nhiệt độ. Giá trị null = không đọc được.
class Reading {
  Reading({this.bt, this.et, this.ct, this.error});
  final double? bt;
  final double? et;
  final double? ct;
  final String? error;
}

abstract class RoasterDevice {
  String get description;
  Future<void> connect();
  Future<Reading> read();

  /// Thanh trượt [index] (0 Air, 1 Drum, 2 Damper, 3 Burner) đổi sang [value]:
  /// chạy lệnh Modbus của thanh trượt với {} = value × factor + offset.
  Future<void> writeControl(int index, double value);

  /// Chạy một chuỗi lệnh Modbus Command (của nút sự kiện).
  Future<void> runCommand(String command, {num? value, int buttonState = 0});

  /// Thông báo giá trị điều khiển mới (do nút ± thay đổi) – dùng cho mô phỏng.
  void controlValueChanged(int index, double value) {}

  Future<void> close();
}

/// Máy rang thật qua Modbus TCP.
class ModbusRoasterDevice extends RoasterDevice {
  ModbusRoasterDevice(this.settings)
      : client = ModbusTcpClient(
          host: settings.host,
          port: settings.port,
          timeout: Duration(milliseconds: settings.timeoutMs),
        ) {
    runner = ModbusCommandRunner(client, littleEndianWords: settings.littleEndianWords);
  }

  final AppSettings settings;
  final ModbusTcpClient client;
  late final ModbusCommandRunner runner;

  @override
  String get description => 'Modbus TCP ${settings.host}:${settings.port}';

  @override
  Future<void> connect() => client.connect();

  Future<double?> _readChannel(InputChannelConfig c) async {
    if (!c.enabled) return null;
    final count = ModbusTcpClient.registerCount(c.dataType);
    final regs = await client.readRegisters(c.slaveId, c.functionCode, c.address, count);
    final ordered = (count == 2 && settings.littleEndianWords) ? [regs[1], regs[0]] : regs;
    final raw = ModbusTcpClient.decode(ordered, c.dataType);
    final div = c.divider == 0 ? 1.0 : c.divider;
    return raw / div + c.offset;
  }

  @override
  Future<Reading> read() async {
    String? err;
    Future<double?> safe(InputChannelConfig c) async {
      try {
        return await _readChannel(c);
      } catch (e) {
        err ??= e.toString();
        return null;
      }
    }

    final et = await safe(settings.et);
    final bt = await safe(settings.bt);
    final ct = await safe(settings.ct);
    return Reading(bt: bt, et: et, ct: ct, error: err);
  }

  @override
  Future<void> writeControl(int index, double value) async {
    final c = settings.controls[index];
    if (c.command.trim().isEmpty) return;
    await runner.run(c.command, value: c.toRegister(value));
  }

  @override
  Future<void> runCommand(String command, {num? value, int buttonState = 0}) async {
    if (command.trim().isEmpty) return;
    await runner.run(command, value: value, buttonState: buttonState);
  }

  @override
  Future<void> close() => client.close();
}

/// Máy rang mô phỏng – để chạy thử app khi chưa nối máy thật.
/// Tự "đổ hạt" sau 60 giây và tự "xả hạt" khi hạt đạt ~210°C, để thử chức năng
/// tự nhận diện CHARGE / TP / DRY END / FC START / DROP.
class SimulatedRoasterDevice extends RoasterDevice {
  SimulatedRoasterDevice();

  final _rnd = math.Random();
  DateTime? _start;
  DateTime? _last;
  double _ct = 300;
  double _et = 220;
  double _bean = 25; // nhiệt độ thật của hạt
  double _probe = 190; // đầu dò BT (có độ trễ)
  bool _charged = false;
  bool _dropped = false;
  final List<double> _controls = [40, 50, 0, 70];

  @override
  String get description => 'Mô phỏng';

  @override
  Future<void> connect() async {
    _start = DateTime.now();
    _last = _start;
  }

  void _step(double dt) {
    final gas = _controls[3].clamp(0, 100).toDouble();
    final air = _controls[0].clamp(0, 100).toDouble();
    final ctTarget = 150 + 6.0 * gas;
    _ct += (ctTarget - _ct) * math.min(1.0, dt / 20.0);
    var etTarget = 0.45 * _ct + 10 - air * 0.15;
    if (_charged && !_dropped) {
      etTarget -= 25 * math.exp(-(_bean - 25).clamp(0, 400) / 60.0); // hạt lạnh hút nhiệt
    }
    _et += (etTarget - _et) * math.min(1.0, dt / (30.0 - air * 0.1));
    if (_charged && !_dropped) {
      _bean += (_et - _bean) * math.min(1.0, dt / 250.0);
      if (_bean > 195) _bean += 0.02 * dt; // phản ứng toả nhiệt (crack)
      _probe += (_bean - _probe) * math.min(1.0, dt / 35.0);
    } else if (_dropped) {
      _probe += (_et * 0.55 - _probe) * math.min(1.0, dt / 12.0); // lồng rỗng – đầu dò nguội nhanh
    } else {
      _probe += (_et * 0.92 - _probe) * math.min(1.0, dt / 60.0);
    }
  }

  @override
  Future<Reading> read() async {
    final now = DateTime.now();
    final dt = _last == null ? 1.0 : now.difference(_last!).inMilliseconds / 1000.0;
    _last = now;
    final elapsed = _start == null ? 0 : now.difference(_start!).inSeconds;
    if (!_charged && elapsed >= 60) {
      _charged = true; // tự đổ hạt
      _bean = 25;
    }
    if (_charged && !_dropped && _bean >= 210) {
      _dropped = true; // tự xả hạt
    }
    var remain = dt.clamp(0.0, 10.0).toDouble();
    while (remain > 0) {
      final h = math.min(0.25, remain);
      _step(h);
      remain -= h;
    }
    double noise() => (_rnd.nextDouble() - 0.5) * 0.3;
    return Reading(bt: _probe + noise(), et: _et + noise(), ct: _ct + noise() * 3);
  }

  @override
  Future<void> writeControl(int index, double value) async {
    controlValueChanged(index, value);
  }

  @override
  void controlValueChanged(int index, double value) {
    if (index >= 0 && index < _controls.length) _controls[index] = value;
  }

  @override
  Future<void> runCommand(String command, {num? value, int buttonState = 0}) async {
    final err = ModbusCommandRunner.validate(command);
    if (err != null) throw ModbusException(err);
  }

  @override
  Future<void> close() async {}
}
