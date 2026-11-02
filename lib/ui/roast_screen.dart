import 'package:flutter/material.dart';

import '../logic/roast_controller.dart';
import '../models/roast_profile.dart';
import 'artisan_colors.dart';
import 'history_screen.dart';
import 'roast_chart.dart';
import 'roast_properties_dialog.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// Màn hình chính – bố cục giống Artisan: đồ thị ở giữa, LCD bên phải,
/// thanh trượt điều khiển bên trái, nút sự kiện phía dưới, ON/OFF phía trên.
class RoastScreen extends StatefulWidget {
  const RoastScreen({super.key, required this.c});

  final RoastController c;

  @override
  State<RoastScreen> createState() => _RoastScreenState();
}

class _RoastScreenState extends State<RoastScreen> {
  RoastController get c => widget.c;
  bool _showSliders = true;

  void _msg(String text, {bool error = false}) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? const Color(0xFFB00020) : null,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<bool> _confirm(String title, String text, {String ok = 'Đồng ý'}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r ?? false;
  }

  // ---------------------------------------------------------------- lệnh

  Future<void> _onPressed() async {
    if (c.dirty && c.hasData) {
      final go = await _confirm('Mẻ rang chưa lưu', 'Dữ liệu hiện tại chưa được lưu. Bắt đầu mẻ mới và bỏ dữ liệu này?',
          ok: 'Bắt đầu');
      if (!go) return;
    }
    final ok = await c.turnOn();
    if (!ok && c.lastError != null) _msg(c.lastError!, error: true);
  }

  Future<void> _offPressed() async {
    await c.turnOff();
    if (!mounted || !c.hasData) return;
    await _saveFlow(askFirst: true);
  }

  Future<void> _resetPressed() async {
    if (c.isOn) return;
    if (c.dirty && c.hasData) {
      final go = await _confirm('RESET', 'Xoá dữ liệu chưa lưu trên màn hình?', ok: 'Xoá');
      if (!go) return;
    }
    c.reset();
  }

  Future<void> _saveFlow({bool askFirst = false}) async {
    if (!c.hasData) {
      _msg('Chưa có dữ liệu để lưu');
      return;
    }
    if (c.isOn) {
      _msg('Bấm OFF trước khi lưu');
      return;
    }
    final saved = await showRoastPropertiesDialog(context, c.profile,
        title: askFirst ? 'Lưu mẻ rang?' : 'Lưu mẻ rang', okLabel: 'Lưu', cancelLabel: askFirst ? 'Không lưu' : 'Huỷ');
    if (!saved) return;
    try {
      final name = await c.save();
      _msg('Đã lưu: $name');
    } catch (e) {
      _msg('Lỗi khi lưu: $e', error: true);
    }
  }

  Future<void> _editProperties() async {
    final ok = await showRoastPropertiesDialog(context, c.profile, title: 'Thuộc tính mẻ rang', okLabel: 'OK');
    if (!ok) return;
    c.dirty = true;
    if (c.currentFile != null && !c.isOn) {
      await c.save();
      _msg('Đã cập nhật ${c.currentFile}');
    } else {
      setState(() {});
    }
  }

  void _event(RoastEvent e) {
    final err = c.markEvent(e);
    if (err != null) {
      if (c.profile.indexOf(e) != null) {
        _msg('${e.label} đã đánh dấu – nhấn giữ để bỏ');
      } else {
        _msg(err);
      }
    }
  }

  Future<void> _undo(RoastEvent e) async {
    if (c.profile.indexOf(e) == null) return;
    final go = await _confirm('Bỏ ${e.label}?', 'Bỏ đánh dấu sự kiện ${e.label}?', ok: 'Bỏ');
    if (!go) return;
    final err = c.undoEvent(e);
    if (err != null) _msg(err);
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'props':
        await _editProperties();
        break;
      case 'save':
        await _saveFlow();
        break;
      case 'history':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen(c: c)));
        break;
      case 'bg_toggle':
        c.settings.showBackground = !c.settings.showBackground;
        await c.applySettings(c.settings);
        break;
      case 'bg_clear':
        await c.setBackgroundFile(null);
        _msg('Đã bỏ đường nền');
        break;
      case 'settings':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(c: c)));
        break;
    }
  }

  // ---------------------------------------------------------------- giao diện

  Widget _topBar(bool compact) {
    final p = c.profile;
    final title = p.title.isNotEmpty ? p.title : (c.currentFile ?? 'Artisan Mobile');
    return Container(
      height: 44,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AC.title, fontWeight: FontWeight.bold, fontSize: 15)),
                Text(
                  [
                    c.settings.simulator ? 'MÔ PHỎNG' : 'Modbus ${c.settings.host}:${c.settings.port}',
                    if (c.background != null && c.settings.showBackground)
                      'Nền: ${c.background!.title.isNotEmpty ? c.background!.title : c.backgroundFile}',
                    if (c.dirty && c.hasData && !c.isOn) 'chưa lưu',
                  ].join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: c.settings.simulator ? AC.et : Colors.black54),
                ),
              ],
            ),
          ),
          if (!compact && c.settings.controls.any((x) => x.visible))
            IconButton(
              tooltip: 'Ẩn/hiện điều khiển',
              icon: Icon(_showSliders ? Icons.tune : Icons.tune_outlined, color: _showSliders ? AC.buttonMajor : Colors.grey),
              onPressed: () => setState(() => _showSliders = !_showSliders),
            ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'props', child: ListTile(leading: Icon(Icons.edit_note), title: Text('Thuộc tính mẻ rang'))),
              PopupMenuItem(
                  value: 'save',
                  enabled: !c.isOn && c.hasData,
                  child: const ListTile(leading: Icon(Icons.save), title: Text('Lưu mẻ rang'))),
              const PopupMenuItem(
                  value: 'history', child: ListTile(leading: Icon(Icons.history), title: Text('Lịch sử / Profile nền'))),
              PopupMenuItem(
                  value: 'bg_toggle',
                  child: ListTile(
                      leading: Icon(c.settings.showBackground ? Icons.layers_clear : Icons.layers),
                      title: Text(c.settings.showBackground ? 'Ẩn đường nền' : 'Hiện đường nền'))),
              PopupMenuItem(
                  value: 'bg_clear',
                  enabled: c.background != null,
                  child: const ListTile(leading: Icon(Icons.delete_sweep), title: Text('Bỏ profile nền'))),
              const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings), title: Text('Cài đặt'))),
            ],
          ),
          CommandButton(label: 'RESET', color: AC.buttonReset, onPressed: c.isOn ? null : _resetPressed, width: 62),
          c.isOn
              ? CommandButton(label: 'OFF', color: AC.buttonOff, onPressed: _offPressed)
              : CommandButton(label: c.connecting ? '...' : 'ON', color: AC.buttonOn, onPressed: c.connecting ? null : _onPressed),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _chart() {
    return ValueListenableBuilder<double>(
      valueListenable: c.clock,
      builder: (context, clock, _) => RoastChart(
        profile: c.profile,
        rorBT: c.rorBT,
        rorET: c.rorET,
        settings: c.settings,
        background: c.background,
        bgRorBT: c.bgRorBT,
        liveTime: c.isOn ? clock : null,
      ),
    );
  }

  Widget _eventBar() {
    final p = c.profile;
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          for (final e in RoastEvent.values)
            Expanded(
              child: EventButton(
                label: e.label,
                sub: p.indexOf(e) != null
                    ? (e == RoastEvent.charge ? fmtTemp(p.bt[p.indexOf(e)!]) : fmtTime(p.rel(p.indexOf(e)!)))
                    : null,
                marked: p.indexOf(e) != null,
                enabled: c.canMark(e),
                onTap: () => _event(e),
                onLongPress: () => _undo(e),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusLine() {
    final err = c.lastError;
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        err ??
            (c.isOn
                ? 'Đang ghi  •  ${c.profile.length} mẫu  •  chu kỳ ${c.settings.samplingInterval.toStringAsFixed(0)} s'
                : (c.currentFile != null ? 'File: ${c.currentFile}' : 'Sẵn sàng – bấm ON để bắt đầu')),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, color: err != null ? const Color(0xFFB00020) : Colors.black54),
      ),
    );
  }

  List<int> get _visibleControls => [
        for (var i = 0; i < 4; i++)
          if (c.settings.controls[i].visible) i
      ];

  Widget _landscape() {
    final ctrls = _visibleControls;
    return Column(
      children: [
        _topBar(false),
        Expanded(
          child: Row(
            children: [
              if (_showSliders && ctrls.isNotEmpty)
                Container(
                  color: const Color(0xFFF5F5F5),
                  child: Row(children: [for (final i in ctrls) ControlSlider(c: c, index: i, vertical: true)]),
                ),
              Expanded(child: _chart()),
              SizedBox(width: 124, child: LcdPanel(c: c, vertical: true)),
            ],
          ),
        ),
        _eventBar(),
        _statusLine(),
      ],
    );
  }

  Widget _portrait() {
    final ctrls = _visibleControls;
    return Column(
      children: [
        _topBar(true),
        SizedBox(height: 110, child: LcdPanel(c: c, vertical: false)),
        Expanded(child: _chart()),
        if (ctrls.isNotEmpty)
          Container(
            color: const Color(0xFFF5F5F5),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(children: [for (final i in ctrls) ControlSlider(c: c, index: i, vertical: false)]),
          ),
        _eventBar(),
        _statusLine(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
        backgroundColor: AC.window,
        body: SafeArea(
          child: OrientationBuilder(
            builder: (context, o) => o == Orientation.landscape ? _landscape() : _portrait(),
          ),
        ),
      ),
    );
  }
}
