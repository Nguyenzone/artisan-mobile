import 'package:flutter/material.dart';

import '../modbus/modbus_command.dart';
import '../services/settings.dart';

const List<int> kButtonColors = [
  0xFF0B5E0B, 0xFF49B160, 0xFF0D0D8A, 0xFF147BB3, 0xFF43A7CF, 0xFF800080, //
  0xFFF01414, 0xFFA30E0E, 0xFFCC0F50, 0xFFE07B00, 0xFFF2A07E, 0xFFFFC107, //
  0xFF808080, 0xFF424242, 0xFF000000, 0xFFFFFFFF,
];

/// Hộp thoại sửa một nút sự kiện (giống bảng Config > Events > Buttons của Artisan).
Future<EventButtonConfig?> showButtonEditor(BuildContext context, EventButtonConfig original) {
  final b = original.copy();
  final labelCtl = TextEditingController(text: b.label);
  final valueCtl = TextEditingController(text: '${b.value}');
  final cmdCtl = TextEditingController(text: b.command);
  String? cmdError;

  return showDialog<EventButtonConfig>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Widget swatch(int c, bool text) {
        final selected = text ? b.textColor == c : b.color == c;
        return GestureDetector(
          onTap: () => setState(() => text ? b.textColor = c : b.color = c),
          child: Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Color(c),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: selected ? Colors.orange : Colors.black26, width: selected ? 3 : 1),
            ),
          ),
        );
      }

      return AlertDialog(
        title: const Text('Nút sự kiện'),
        scrollable: true,
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(color: Color(b.color), borderRadius: BorderRadius.circular(4)),
                  child: Text(labelCtl.text,
                      style: TextStyle(color: Color(b.textColor), fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: labelCtl,
                decoration: const InputDecoration(labelText: 'Label (tên nút)', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Type (loại)', isDense: true),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isDense: true,
                        isExpanded: true,
                        value: ButtonType.names.containsKey(b.type) ? b.type : ButtonType.none,
                        items: [
                          for (final e in ButtonType.names.entries)
                            DropdownMenuItem<int>(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() => b.type = v ?? ButtonType.none),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: valueCtl,
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    decoration: const InputDecoration(labelText: 'Value (giá trị)', isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: cmdCtl,
                decoration: InputDecoration(
                  labelText: 'Modbus Command',
                  hintText: 'write([3,4,1])   hoặc   writem(3,1,{})',
                  errorText: cmdError,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '• Type trống: chỉ gửi lệnh, {} = Value.\n'
                '• Type Air/Drum/Damper/Burner: đặt thanh trượt = Value, {} = Value × Factor + Offset.\n'
                '• Type ±Air, ±Burner…: cộng Value vào thanh trượt hiện tại (ví dụ +5 / −5), {} = giá trị mới.\n'
                '• Nhiều lệnh cách nhau bằng dấu ;   –   \$ = trạng thái nút (0/1).',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              const Text('Màu nút', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(children: [for (final c in kButtonColors) swatch(c, false)]),
              const SizedBox(height: 8),
              const Text('Màu chữ', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(children: [swatch(0xFFFFFFFF, true), swatch(0xFF000000, true), swatch(0xFF424242, true)]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hiện nút (Visibility)'),
                value: b.visible,
                onChanged: (v) => setState(() => b.visible = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              final cmd = cmdCtl.text.trim();
              final err = cmd.isEmpty ? null : ModbusCommandRunner.validate(cmd);
              if (err != null) {
                setState(() => cmdError = err);
                return;
              }
              b.label = labelCtl.text.trim().isEmpty ? 'Nút' : labelCtl.text.trim();
              b.value = int.tryParse(valueCtl.text.trim()) ?? 0;
              b.command = cmd;
              Navigator.pop(ctx, b);
            },
            child: const Text('OK'),
          ),
        ],
      );
    }),
  );
}

/// Danh sách nút trong màn hình Cài đặt: thêm, sửa, xoá, đổi thứ tự.
class ButtonsSettingsSection extends StatefulWidget {
  const ButtonsSettingsSection({super.key, required this.buttons});

  final List<EventButtonConfig> buttons;

  @override
  State<ButtonsSettingsSection> createState() => _ButtonsSettingsSectionState();
}

class _ButtonsSettingsSectionState extends State<ButtonsSettingsSection> {
  List<EventButtonConfig> get list => widget.buttons;

  Future<void> _edit(int i) async {
    final r = await showButtonEditor(context, list[i]);
    if (r != null) setState(() => list[i] = r);
  }

  Future<void> _add() async {
    final r = await showButtonEditor(context, EventButtonConfig(label: 'Nút ${list.length + 1}'));
    if (r != null) setState(() => list.add(r));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++)
            ListTile(
              dense: true,
              leading: Container(
                width: 74,
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Color(list[i].color), borderRadius: BorderRadius.circular(4)),
                child: Text(list[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(list[i].textColor), fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              title: Text(list[i].command.isEmpty ? '(không có lệnh)' : list[i].command,
                  style: TextStyle(
                      fontFamily: 'monospace', color: list[i].visible ? Colors.black87 : Colors.black38, fontSize: 13)),
              subtitle: Text(
                  '${ButtonType.names[list[i].type] ?? ''}  •  Value ${list[i].value}${list[i].visible ? '' : '  •  ẩn'}'),
              onTap: () => _edit(i),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => setState(() {
                  if (v == 'up' && i > 0) {
                    final x = list.removeAt(i);
                    list.insert(i - 1, x);
                  } else if (v == 'down' && i < list.length - 1) {
                    final x = list.removeAt(i);
                    list.insert(i + 1, x);
                  } else if (v == 'del') {
                    list.removeAt(i);
                  }
                }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'up', child: Text('Lên trên')),
                  PopupMenuItem(value: 'down', child: Text('Xuống dưới')),
                  PopupMenuItem(value: 'del', child: Text('Xoá')),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Thêm nút')),
              TextButton(
                onPressed: () => setState(() {
                  list
                    ..clear()
                    ..addAll(AppSettings.defaultButtons());
                }),
                child: const Text('Khôi phục 8 nút mặc định'),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
