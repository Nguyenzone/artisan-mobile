import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class ModbusException implements Exception {
  ModbusException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Client Modbus TCP tối giản (FC 3, 4, 5, 6, 16) dùng socket của dart:io.
/// Mỗi lần chỉ gửi một yêu cầu (các yêu cầu được xếp hàng tuần tự).
class ModbusTcpClient {
  ModbusTcpClient({
    required this.host,
    this.port = 502,
    this.timeout = const Duration(milliseconds: 1000),
  });

  final String host;
  final int port;
  final Duration timeout;

  Socket? _socket;
  StreamSubscription<Uint8List>? _sub;
  final List<int> _buffer = <int>[];
  int _tid = 0;
  Completer<Uint8List>? _pending;
  int _pendingTid = -1;
  Future<void> _queue = Future<void>.value();

  bool get isConnected => _socket != null;

  Future<void> connect() async {
    if (_socket != null) return;
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.setOption(SocketOption.tcpNoDelay, true);
      _socket = s;
      _buffer.clear();
      _sub = s.listen(
        _onData,
        onError: (Object e) {
          _fail(ModbusException('Lỗi kết nối: $e'));
          _closeSocket();
        },
        onDone: () {
          _fail(ModbusException('Thiết bị đã đóng kết nối'));
          _closeSocket();
        },
        cancelOnError: true,
      );
    } on SocketException catch (e) {
      throw ModbusException('Không kết nối được $host:$port (${e.osError?.message ?? e.message})');
    } on TimeoutException {
      throw ModbusException('Hết thời gian kết nối tới $host:$port');
    }
  }

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    while (_buffer.length >= 7) {
      final len = (_buffer[4] << 8) | _buffer[5];
      final total = 6 + len;
      if (len < 2 || len > 260) {
        _buffer.clear(); // dữ liệu hỏng
        return;
      }
      if (_buffer.length < total) return;
      final frame = Uint8List.fromList(_buffer.sublist(0, total));
      _buffer.removeRange(0, total);
      final tid = (frame[0] << 8) | frame[1];
      final p = _pending;
      if (p != null && !p.isCompleted && tid == _pendingTid) {
        p.complete(Uint8List.sublistView(frame, 7));
      }
    }
  }

  void _fail(Object e) {
    final p = _pending;
    if (p != null && !p.isCompleted) p.completeError(e);
  }

  void _closeSocket() {
    _sub?.cancel();
    _sub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _buffer.clear();
  }

  Future<void> close() async {
    _fail(ModbusException('Đã đóng kết nối'));
    _closeSocket();
  }

  Future<Uint8List> _transact(int unitId, List<int> pdu) {
    final completer = Completer<Uint8List>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await _doTransact(unitId, pdu));
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<Uint8List> _doTransact(int unitId, List<int> pdu) async {
    await connect();
    final s = _socket;
    if (s == null) throw ModbusException('Chưa kết nối');
    _tid = (_tid + 1) & 0xFFFF;
    final len = pdu.length + 1;
    final frame = <int>[
      (_tid >> 8) & 0xFF, _tid & 0xFF, // transaction id
      0, 0, // protocol id
      (len >> 8) & 0xFF, len & 0xFF,
      unitId & 0xFF,
      ...pdu,
    ];
    final completer = Completer<Uint8List>();
    _pending = completer;
    _pendingTid = _tid;
    try {
      s.add(frame);
      final resp = await completer.future.timeout(timeout);
      if (resp.isEmpty) throw ModbusException('Phản hồi rỗng');
      if ((resp[0] & 0x80) != 0) {
        final code = resp.length > 1 ? resp[1] : 0;
        throw ModbusException('Thiết bị báo lỗi Modbus (mã $code: ${_exceptionText(code)})');
      }
      if (resp[0] != pdu[0]) throw ModbusException('Phản hồi sai mã hàm');
      return resp;
    } on TimeoutException {
      _closeSocket();
      throw ModbusException('Thiết bị không phản hồi (timeout)');
    } on SocketException catch (e) {
      _closeSocket();
      throw ModbusException('Lỗi socket: ${e.message}');
    } finally {
      _pending = null;
      _pendingTid = -1;
    }
  }

  static String _exceptionText(int code) {
    switch (code) {
      case 1:
        return 'mã hàm không hỗ trợ';
      case 2:
        return 'địa chỉ thanh ghi không hợp lệ';
      case 3:
        return 'giá trị không hợp lệ';
      case 4:
        return 'lỗi thiết bị';
      case 6:
        return 'thiết bị bận';
      case 10:
        return 'gateway path unavailable';
      case 11:
        return 'gateway không có phản hồi';
      default:
        return 'không rõ';
    }
  }

  /// Đọc [count] thanh ghi bằng FC3 (holding) hoặc FC4 (input).
  Future<List<int>> readRegisters(int unitId, int functionCode, int address, int count) async {
    if (functionCode != 3 && functionCode != 4) {
      throw ModbusException('Mã hàm đọc phải là 3 hoặc 4');
    }
    final resp = await _transact(unitId, [
      functionCode,
      (address >> 8) & 0xFF, address & 0xFF,
      (count >> 8) & 0xFF, count & 0xFF,
    ]);
    if (resp.length < 2) throw ModbusException('Phản hồi ngắn');
    final byteCount = resp[1];
    if (resp.length < 2 + byteCount || byteCount < count * 2) {
      throw ModbusException('Phản hồi thiếu dữ liệu');
    }
    final out = <int>[];
    for (var i = 0; i < count; i++) {
      out.add((resp[2 + i * 2] << 8) | resp[3 + i * 2]);
    }
    return out;
  }

  /// FC6 – ghi một thanh ghi.
  Future<void> writeSingleRegister(int unitId, int address, int value) async {
    final v = value & 0xFFFF;
    await _transact(unitId, [
      6,
      (address >> 8) & 0xFF, address & 0xFF,
      (v >> 8) & 0xFF, v & 0xFF,
    ]);
  }

  /// FC16 – ghi nhiều thanh ghi.
  Future<void> writeMultipleRegisters(int unitId, int address, List<int> values) async {
    final bytes = <int>[];
    for (final value in values) {
      final v = value & 0xFFFF;
      bytes..add((v >> 8) & 0xFF)..add(v & 0xFF);
    }
    await _transact(unitId, [
      16,
      (address >> 8) & 0xFF, address & 0xFF,
      (values.length >> 8) & 0xFF, values.length & 0xFF,
      bytes.length,
      ...bytes,
    ]);
  }

  /// FC5 – ghi một coil (bật/tắt).
  Future<void> writeSingleCoil(int unitId, int address, bool on) async {
    await _transact(unitId, [
      5,
      (address >> 8) & 0xFF, address & 0xFF,
      on ? 0xFF : 0x00, 0x00,
    ]);
  }

  /// Giải mã giá trị từ thanh ghi.
  /// [dataType]: int16, uint16, int32, uint32, float32 (ABCD), float32_cdab.
  static double decode(List<int> regs, String dataType) {
    switch (dataType) {
      case 'uint16':
        return regs[0].toDouble();
      case 'int32':
      case 'uint32':
        final v = (regs[0] << 16) | regs[1];
        if (dataType == 'int32' && v >= 0x80000000) return (v - 0x100000000).toDouble();
        return v.toDouble();
      case 'float32':
      case 'float32_cdab':
        final hi = dataType == 'float32' ? regs[0] : regs[1];
        final lo = dataType == 'float32' ? regs[1] : regs[0];
        final bd = ByteData(4)
          ..setUint16(0, hi)
          ..setUint16(2, lo);
        return bd.getFloat32(0);
      case 'int16':
      default:
        final v = regs[0];
        return (v >= 0x8000 ? v - 0x10000 : v).toDouble();
    }
  }

  static int registerCount(String dataType) =>
      (dataType == 'float32' || dataType == 'float32_cdab' || dataType == 'int32' || dataType == 'uint32') ? 2 : 1;
}
