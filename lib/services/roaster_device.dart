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
