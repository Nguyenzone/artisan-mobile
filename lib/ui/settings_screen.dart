import 'package:flutter/material.dart';

import '../logic/roast_controller.dart';
import '../modbus/modbus_command.dart';
import '../services/roaster_device.dart';
import '../services/settings.dart';
import 'artisan_colors.dart';
import 'button_editor.dart';

/// Cài đặt: kết nối Modbus TCP, kênh nhiệt độ, điều khiển, đồ thị.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.c});

  final RoastController c;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings s = widget.c.settings.clone();
  bool _testing = false;

  static const _dataTypes = <String, String>{
    'int16': 'INT16 (có dấu)',
    'uint16': 'UINT16',
    'int32': 'INT32',
    'uint32': 'UINT32',
    'float32': 'FLOAT32 (ABCD)',
    'float32_cdab': 'FLOAT32 (CDAB)',
  };

  // ------------------------------------------------------------- tiện ích

  Widget _section(String title, {IconData? icon}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Row(children: [
          if (icon != null) Icon(icon, color: AC.buttonMajor, size: 20),
          if (icon != null) const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AC.title)),
        ]),
      );

  Widget _field(String label, String initial, ValueChanged<String> onChanged,
      {bool number = true, bool decimal = false, String? suffix, String? helper}) {
    return TextFormField(
      initialValue: initial,
      keyboardType: number ? TextInputType.numberWithOptions(decimal: decimal, signed: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helper,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }

  int? _int(String v) => int.tryParse(v.trim());
  double? _dbl(String v) => double.tryParse(v.trim().replaceAll(',', '.'));

  String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ]
          ],
        ),
      );

  Widget _dropdown<T>(String label, T value, Map<T, String> items, ValueChanged<T> onChanged) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.containsKey(value) ? value : items.keys.first,
          isDense: true,
          isExpanded: true,
          items: [for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            if (v != null) setState(() => onChanged(v));
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------- kênh nhiệt độ

  Widget _channel(String name, String desc, InputChannelConfig ch, {bool canDisable = false}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            SwitchListTile(
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(desc),
              value: ch.enabled,
              onChanged: canDisable ? (v) => setState(() => ch.enabled = v) : null,
            ),
            if (ch.enabled) ...[
              _row([
                _field('Slave ID', '${ch.slaveId}', (v) => ch.slaveId = _int(v) ?? ch.slaveId),
                _field('Địa chỉ thanh ghi', '${ch.address}', (v) => ch.address = _int(v) ?? ch.address,
                    helper: 'Bắt đầu từ 0'),
              ]),
              _row([
                _dropdown<int>('Mã hàm', ch.functionCode, const {3: '3 – Holding', 4: '4 – Input'},
                    (v) => ch.functionCode = v),
                _dropdown<String>('Kiểu dữ liệu', ch.dataType, _dataTypes, (v) => ch.dataType = v),
              ]),
              _row([
                _field('Chia cho', _num(ch.divider), (v) => ch.divider = _dbl(v) ?? ch.divider,
                    decimal: true, helper: '2005 ÷ 10 = 200.5°C'),
                _field('Hiệu chỉnh', _num(ch.offset), (v) => ch.offset = _dbl(v) ?? ch.offset,
                    decimal: true, suffix: '°C'),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- điều khiển

  Widget _control(int i) {
    final cc = s.controls[i];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            SwitchListTile(
              secondary: CircleAvatar(radius: 8, backgroundColor: AC.eventColors[i]),
              title: Text('${cc.label}  (Artisan: ${AppSettings.etypeNames[i]})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Hiện thanh trượt trên màn hình rang'),
              value: cc.visible,
              onChanged: (v) => setState(() => cc.visible = v),
            ),
            if (cc.visible) ...[
              _row([
                _field('Tên hiển thị', cc.label, (v) => cc.label = v.isEmpty ? cc.label : v, number: false),
                _field('Đơn vị', cc.unit, (v) => cc.unit = v, number: false),
              ]),
              _row([
                _field('Nhỏ nhất', '${cc.min}', (v) => cc.min = _int(v) ?? cc.min),
                _field('Lớn nhất', '${cc.max}', (v) => cc.max = _int(v) ?? cc.max),
                _field('Bước', '${cc.step}', (v) => cc.step = _int(v) ?? cc.step),
              ]),
              _row([
                _field('Lệnh Modbus (Modbus Command)', cc.command, (v) => cc.command = v.trim(),
                    number: false, helper: 'Ví dụ: write([3,0,{}])  –  để trống nếu không gửi lệnh'),
              ]),
              _row([
                _field('Factor (hệ số nhân)', _num(cc.factor), (v) => cc.factor = _dbl(v) ?? cc.factor, decimal: true),
                _field('Offset (cộng thêm)', _num(cc.offset), (v) => cc.offset = _dbl(v) ?? cc.offset, decimal: true),
              ]),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('{} trong lệnh = giá trị thanh trượt × Factor + Offset (giống Artisan)',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- kiểm tra / lưu

  String? _validate() {
    if (s.port < 1 || s.port > 65535) return 'Cổng (port) không hợp lệ';
    if (s.host.trim().isEmpty) return 'Chưa nhập địa chỉ IP';
    for (final ch in [s.bt, s.et, s.ct]) {
      if (ch.divider == 0) return 'Hệ số "Chia cho" không được bằng 0';
      if (ch.address < 0 || ch.address > 65535) return 'Địa chỉ thanh ghi không hợp lệ';
      if (ch.slaveId < 0 || ch.slaveId > 255) return 'Slave ID phải từ 0 đến 255';
    }
    for (final cc in s.controls) {
      if (cc.max <= cc.min) return '${cc.label}: "Lớn nhất" phải lớn hơn "Nhỏ nhất"';
      if (cc.step < 1) return '${cc.label}: "Bước" phải ≥ 1';
      final e = cc.command.isEmpty ? null : ModbusCommandRunner.validate(cc.command);
      if (e != null) return '${cc.label}: $e';
    }
    for (final b in s.buttons) {
      final e = b.command.isEmpty ? null : ModbusCommandRunner.validate(b.command);
      if (e != null) return 'Nút ${b.label}: $e';
    }
    if (s.pidDutyMin < 0 || s.pidDutyMax > 100 || s.pidDutyMin >= s.pidDutyMax) {
      return 'Duty min/max phải trong 0–100 và min < max';
    }
    if (s.pidKp < 0 || s.pidKi < 0 || s.pidKd < 0) return 'Kp, Ki, Kd không được âm';
    if (s.fcStartTemp <= s.dryEndTemp) return 'Nhiệt độ FC START phải lớn hơn DRY END';
    if (s.tempMax <= s.tempMin + 10) return 'Trục nhiệt độ: Max phải lớn hơn Min';
    if (s.rorMax <= s.rorMin) return 'Trục RoR: Max phải lớn hơn Min';
    if (s.rorSpan < 1 || s.rorSpan > 60) return 'Khoảng tính RoR phải từ 1 đến 60 giây';
    if (s.timeMaxMinutes < 5) return 'Trục thời gian tối thiểu 5 phút';
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: const Color(0xFFB00020)));
      return;
    }
    s.host = s.host.trim();
    await widget.c.applySettings(s);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _test() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _testing = true);
    final dev = ModbusRoasterDevice(s.clone());
    String result;
    try {
      await dev.connect();
      final r = await dev.read();
      String f(double? v) => v == null ? '—' : v.toStringAsFixed(1);
      result = 'Kết nối thành công tới ${s.host}:${s.port}\n\n'
          'BT = ${f(r.bt)} °C\nET = ${f(r.et)} °C\nCT = ${s.ct.enabled ? '${f(r.ct)} °C' : '(tắt)'}'
          '${r.error != null ? '\n\nCảnh báo: ${r.error}' : ''}';
    } catch (e) {
      result = 'Không kết nối được:\n$e\n\nKiểm tra: điện thoại và PLC cùng mạng WiFi, đúng IP/cổng, '
          'thiết bị bật Modbus TCP.';
    } finally {
      await dev.close();
    }
    if (!mounted) return;
    setState(() => _testing = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kiểm tra kết nối'),
        content: Text(result),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.c.isOn;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
        actions: [
          TextButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Lưu')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (on)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              color: const Color(0xFFFFF3CD),
              child: const Text('Đang rang (ON). Thay đổi kết nối / kênh đọc sẽ có hiệu lực từ lần bấm ON tiếp theo.'),
            ),
          _section('Kết nối', icon: Icons.wifi),
          _row([
            _field('Địa chỉ IP thiết bị Modbus TCP', s.host, (v) => s.host = v, number: false),
          ]),
          _row([
            _field('Cổng (port)', '${s.port}', (v) => s.port = _int(v) ?? s.port),
            _field('Timeout', '${s.timeoutMs}', (v) => s.timeoutMs = _int(v) ?? s.timeoutMs, suffix: 'ms'),
            _dropdown<double>('Chu kỳ lấy mẫu', s.samplingInterval, {1.0: '1 giây', 2.0: '2 giây', 3.0: '3 giây'},
                (v) => s.samplingInterval = v),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check),
              label: const Text('Kiểm tra kết nối & đọc thử nhiệt độ'),
            ),
          ),
          SwitchListTile(
            title: const Text('little-endian words'),
            subtitle: const Text('Thứ tự 2 thanh ghi cho kiểu 32 bit (giống Artisan). Không ảnh hưởng uInt16.'),
            value: s.littleEndianWords,
            onChanged: (v) => setState(() => s.littleEndianWords = v),
          ),
          _section('Kênh nhiệt độ (Modbus)', icon: Icons.thermostat),
          _channel('BT – Nhiệt độ hạt', 'Artisan: Modbus Input 2 (mặc định slave 2, thanh ghi 0)', s.bt),
          _channel('ET – Nhiệt độ môi trường', 'Artisan: Modbus Input 1 (mặc định slave 1, thanh ghi 0)', s.et),
          _channel('CT – Nhiệt độ buồng đốt', 'Mặc định slave 5, thanh ghi 0 (Artisan Input 6) – lưu vào .alog tên "CT"', s.ct, canDisable: true),
          _section('Điều khiển máy rang (ghi Modbus)', icon: Icons.tune),
          for (final i in [3, 0, 1, 2]) _control(i),
          _section('Nút sự kiện (Buttons)', icon: Icons.smart_button),
          ButtonsSettingsSection(buttons: s.buttons),
          _section('Tự động đánh dấu sự kiện', icon: Icons.auto_awesome),
          SwitchListTile(
            title: const Text('Tự nhận CHARGE (đổ hạt)'),
            subtitle: const Text('BT giảm đột ngột khi BT > 77°C – giống Auto CHARGE của Artisan'),
            value: s.autoCharge,
            onChanged: (v) => setState(() => s.autoCharge = v),
          ),
          SwitchListTile(
            title: const Text('Tự nhận TP (điểm đáy)'),
            subtitle: const Text('Sau CHARGE, khi BT ngừng giảm và tăng trở lại'),
            value: s.autoTP,
            onChanged: (v) => setState(() => s.autoTP = v),
          ),
          SwitchListTile(
            title: const Text('Tự nhận DRY END'),
            value: s.autoDryEnd,
            onChanged: (v) => setState(() => s.autoDryEnd = v),
          ),
          _row([
            _field('DRY END khi BT đạt', _num(s.dryEndTemp), (v) => s.dryEndTemp = _dbl(v) ?? s.dryEndTemp,
                decimal: true, suffix: '°C'),
            _field('FC START khi BT đạt', _num(s.fcStartTemp), (v) => s.fcStartTemp = _dbl(v) ?? s.fcStartTemp,
                decimal: true, suffix: '°C'),
          ]),
          SwitchListTile(
            title: const Text('Tự nhận FC START'),
            value: s.autoFcStart,
            onChanged: (v) => setState(() => s.autoFcStart = v),
          ),
          SwitchListTile(
            title: const Text('Tự nhận DROP (xả hạt)'),
            subtitle: const Text('BT giảm đột ngột, sau CHARGE ≥ 7 phút và BT > 160°C – giống Auto DROP của Artisan'),
            value: s.autoDrop,
            onChanged: (v) => setState(() => s.autoDrop = v),
          ),
          _section('Rang tự động theo profile nền (PID)', icon: Icons.precision_manufacturing),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Giống Artisan: Control > PID > Mode "Background Follow", nguồn BT. App tự chỉnh thanh trượt '
              'để BT bám đường BT của profile nền. Bấm nút AUTO trên màn hình rang để bật/tắt.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          _row([
            _dropdown<int>('Điều khiển thanh trượt', s.pidTarget,
                {for (var i = 0; i < 4; i++) i: '${s.controls[i].label} (${AppSettings.etypeNames[i]})'},
                (v) => s.pidTarget = v),
            _field('Lookahead', '${s.pidLookahead}', (v) => s.pidLookahead = _int(v) ?? s.pidLookahead,
                suffix: 'giây', helper: 'Nhìn trước đường nền'),
          ]),
          _row([
            _field('Kp', _num(s.pidKp), (v) => s.pidKp = _dbl(v) ?? s.pidKp, decimal: true),
            _field('Ki', _num(s.pidKi), (v) => s.pidKi = _dbl(v) ?? s.pidKi, decimal: true),
            _field('Kd', _num(s.pidKd), (v) => s.pidKd = _dbl(v) ?? s.pidKd, decimal: true),
          ]),
          _row([
            _field('Duty min', '${s.pidDutyMin}', (v) => s.pidDutyMin = _int(v) ?? s.pidDutyMin, suffix: '%'),
            _field('Duty max', '${s.pidDutyMax}', (v) => s.pidDutyMax = _int(v) ?? s.pidDutyMax, suffix: '%'),
            _field('Duty steps', '${s.pidDutySteps}', (v) => s.pidDutySteps = _int(v) ?? s.pidDutySteps),
          ]),
          SwitchListTile(
            title: const Text('Tự tắt rang tự động khi DROP'),
            value: s.pidStopAtDrop,
            onChanged: (v) => setState(() => s.pidStopAtDrop = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () => setState(() {
                s.pidKp = 15;
                s.pidKi = 0.01;
                s.pidKd = 20;
              }),
              child: const Text('Đặt lại Kp/Ki/Kd mặc định của Artisan (15 / 0.01 / 20)'),
            ),
          ),
          _section('Đồ thị', icon: Icons.show_chart),
          _row([
            _field('Nhiệt độ min', _num(s.tempMin), (v) => s.tempMin = _dbl(v) ?? s.tempMin, suffix: '°C'),
            _field('Nhiệt độ max', _num(s.tempMax), (v) => s.tempMax = _dbl(v) ?? s.tempMax, suffix: '°C'),
          ]),
          _row([
            _field('RoR min', _num(s.rorMin), (v) => s.rorMin = _dbl(v) ?? s.rorMin),
            _field('RoR max', _num(s.rorMax), (v) => s.rorMax = _dbl(v) ?? s.rorMax),
            _field('Trục thời gian', '${s.timeMaxMinutes}', (v) => s.timeMaxMinutes = _int(v) ?? s.timeMaxMinutes,
                suffix: 'phút'),
          ]),
          _row([
            _field('Khoảng tính RoR', _num(s.rorSpan), (v) => s.rorSpan = _dbl(v) ?? s.rorSpan,
                suffix: 'giây', helper: 'Artisan mặc định 20s'),
            _field('Làm mượt RoR', '${s.rorSmoothing}', (v) => s.rorSmoothing = _int(v) ?? s.rorSmoothing,
                suffix: 'mẫu'),
          ]),
          SwitchListTile(
              title: const Text('Hiện đường CT'), value: s.showCT, onChanged: (v) => setState(() => s.showCT = v)),
          SwitchListTile(
              title: const Text('Hiện ΔBT'), value: s.showDeltaBT, onChanged: (v) => setState(() => s.showDeltaBT = v)),
          SwitchListTile(
              title: const Text('Hiện profile nền'),
              value: s.showBackground,
              onChanged: (v) => setState(() => s.showBackground = v)),
          SwitchListTile(
              title: const Text('Hiện bậc thang điều khiển (gas/quạt/trống)'),
              value: s.showEventSteps,
              onChanged: (v) => setState(() => s.showEventSteps = v)),
          SwitchListTile(
              title: const Text('Giữ màn hình sáng khi rang'),
              value: s.keepScreenOn,
              onChanged: (v) => setState(() => s.keepScreenOn = v)),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Artisan Mobile – tương thích file .alog của Artisan (artisan-scope.org). '
              'Đây là ứng dụng độc lập, không phải sản phẩm chính thức của dự án Artisan.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
