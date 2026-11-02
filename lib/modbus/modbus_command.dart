import 'dart:typed_data';

import '../alog/python_literal.dart';
import 'modbus_tcp.dart';

/// Thực thi chuỗi lệnh "Modbus Command" theo đúng cú pháp của Artisan
/// (Config > Events > Buttons/Sliders, Action = Modbus Command).
///
/// Hỗ trợ (cách nhau bằng dấu `;`):
///   write(s,r,v)          write([s,r,v],..,[s,r,v])   – FC6 ghi 1 thanh ghi
///   writeSingle(s,r,v)    writeSingle([s,r,v],..)     – FC6
///   writem(s,r,v)         writem(s,r,[v1,..,vn])      – FC16 ghi nhiều thanh ghi
///   writeWord(s,r,f)      – FC16, số thực 32 bit (2 thanh ghi)
///   writeLong(s,r,n)      – FC16, số nguyên 32 bit (2 thanh ghi)
///   writeBCD(s,r,v)       – FC6, giá trị dạng BCD
///   wcoil(s,c,b)          – FC5 ghi 1 coil (b = 0/1, True/False)
///   wcoils(s,c,[b,..])    – FC15 ghi nhiều coil
///   read(s,r)             – FC3 đọc 1 thanh ghi, kết quả dùng lại bằng ký hiệu `_`
///   sleep(giây)
///
/// Thay thế trước khi chạy: `{}` = giá trị sự kiện, `$` = trạng thái nút (0/1),
/// `_` = kết quả lệnh read gần nhất. Phần sau dấu `#` (ngoài ngoặc) là chú thích.
class ModbusCommandRunner {
  ModbusCommandRunner(this.client, {this.littleEndianWords = false});

  final ModbusTcpClient client;
  final bool littleEndianWords;
  int? lastReadResult;

  /// Thay `{}` bằng [value] (giống `str.format` của Python trong Artisan).
  static String substitute(String command, {num? value, int buttonState = 0, int? lastRead}) {
    var cmd = stripComment(command);
    if (value != null) {
      final v = value == value.roundToDouble() ? value.round().toString() : value.toString();
      cmd = cmd.replaceAll('{}', v);
    }
    cmd = cmd.replaceAll(r'$', '$buttonState');
    return cmd;
  }

  /// Bỏ phần chú thích sau dấu '#' không nằm trong ngoặc tròn.
  static String stripComment(String command) {
    var depth = 0;
    for (var i = 0; i < command.length; i++) {
      final c = command[i];
      if (c == '(') depth++;
      if (c == ')') depth = depth > 0 ? depth - 1 : 0;
      if (c == '#' && depth == 0) return command.substring(0, i).trim();
    }
    return command.trim();
  }

  static final RegExp _call = RegExp(r'^([A-Za-z][A-Za-z0-9]*)\s*\((.*)\)$', dotAll: true);

  /// Kiểm tra cú pháp; trả về thông báo lỗi hoặc null nếu hợp lệ.
  static String? validate(String command) {
    final cmd = substitute(command, value: 0);
    for (final part in cmd.split(';')) {
      final c = part.trim();
      if (c.isEmpty) continue;
      final m = _call.firstMatch(c);
      if (m == null) return 'Lệnh không đúng cú pháp: "$c"';
      const known = {
        'write', 'writeSingle', 'writem', 'writeWord', 'writeLong', 'writeBCD',
        'wcoil', 'wcoils', 'read', 'sleep'
      };
      if (!known.contains(m.group(1))) return 'Lệnh chưa hỗ trợ: ${m.group(1)}';
      try {
        _args(m.group(2)!.replaceAll('_', '0'));
      } catch (e) {
        return 'Tham số sai trong "$c"';
      }
    }
    return null;
  }

  /// Phân tích phần trong ngoặc theo cú pháp Python: "(3,4,1)" hoặc "([3,4,1])"
  /// đều cho [3,4,1]; "([3,4,1],[3,5,1])" cho [[3,4,1],[3,5,1]].
  static dynamic _args(String inner) => PythonLiteral.parse('($inner)');

  static int _i(dynamic v) {
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v.round();
    throw FormatException('Không phải số: $v');
  }

  static List<List<dynamic>> _triples(dynamic a) {
    if (a is List && a.isNotEmpty && a.first is List) {
      return [for (final x in a) List<dynamic>.from(x as List)];
    }
    if (a is List) return [a];
    throw const FormatException('Tham số không hợp lệ');
  }

  /// Chạy chuỗi lệnh (đã thay `{}`). Ném [ModbusException] nếu lỗi.
  Future<void> run(String command, {num? value, int buttonState = 0}) async {
    final cmd = substitute(command, value: value, buttonState: buttonState);
    var first = true;
    for (final part in cmd.split(';')) {
      var c = part.trim();
      if (c.isEmpty) continue;
      c = c.replaceAll('_', '${lastReadResult ?? 0}');
      final m = _call.firstMatch(c);
      if (m == null) throw ModbusException('Lệnh không đúng cú pháp: "$c"');
      final name = m.group(1)!;
      final dynamic a;
      try {
        a = _args(m.group(2)!);
      } catch (_) {
        throw ModbusException('Tham số sai trong "$c"');
      }
      if (!first) {
        await Future<void>.delayed(const Duration(milliseconds: 80)); // khoảng nghỉ giữa các lệnh ghi
      }
      first = false;
      switch (name) {
        case 'sleep':
          final s = a is num ? a.toDouble() : 0.0;
          await Future<void>.delayed(Duration(milliseconds: (s * 1000).round()));
          break;
        case 'write':
        case 'writeSingle':
          for (final t in _triples(a)) {
            await client.writeSingleRegister(_i(t[0]), _i(t[1]), _i(t[2]));
          }
          break;
        case 'writeBCD':
          for (final t in _triples(a)) {
            await client.writeSingleRegister(_i(t[0]), _i(t[1]), _bcd(_i(t[2])));
          }
          break;
        case 'writem':
          final l = a as List;
          final vals = l[2] is List ? [for (final v in l[2] as List) _i(v)] : [_i(l[2])];
          await client.writeMultipleRegisters(_i(l[0]), _i(l[1]), vals);
          break;
        case 'writeWord':
          for (final t in _triples(a)) {
            final bd = ByteData(4)..setFloat32(0, (t[2] as num).toDouble());
            await client.writeMultipleRegisters(_i(t[0]), _i(t[1]), _words(bd));
          }
          break;
        case 'writeLong':
          for (final t in _triples(a)) {
            final bd = ByteData(4)..setInt32(0, _i(t[2]));
            await client.writeMultipleRegisters(_i(t[0]), _i(t[1]), _words(bd));
          }
          break;
        case 'wcoil':
          final l = a as List;
          await client.writeSingleCoil(_i(l[0]), _i(l[1]), _i(l[2]) != 0);
          break;
        case 'wcoils':
          final l = a as List;
          final bits = [for (final b in l[2] as List) _i(b) != 0];
          await client.writeMultipleCoils(_i(l[0]), _i(l[1]), bits);
          break;
        case 'read':
          final l = a as List;
          final r = await client.readRegisters(_i(l[0]), 3, _i(l[1]), 1);
          lastReadResult = r.first;
          break;
        default:
          throw ModbusException('Lệnh chưa hỗ trợ: $name');
      }
    }
  }

  List<int> _words(ByteData bd) {
    final hi = bd.getUint16(0);
    final lo = bd.getUint16(2);
    return littleEndianWords ? [lo, hi] : [hi, lo];
  }

  static int _bcd(int v) {
    var out = 0;
    var shift = 0;
    var x = v.abs();
    while (x > 0 && shift < 16) {
      out |= (x % 10) << shift;
      x ~/= 10;
      shift += 4;
    }
    return out;
  }
}
