import 'package:flutter/material.dart';

import '../logic/roast_controller.dart';
import '../models/roast_profile.dart';
import '../services/settings.dart';
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

  @override
  void initState() {
    super.initState();
    c.notice.addListener(_onNotice);
  }

  @override
  void dispose() {
    c.notice.removeListener(_onNotice);
    super.dispose();
  }

  void _onNotice() {
    final n = c.notice.value;
    if (n != null && mounted) _msg(n);
  }

  Widget _profileAutoButton() {
    final bg = c.background;
    final name = bg == null ? 'Chưa chọn' : (bg.title.isNotEmpty ? bg.title : (c.backgroundFile ?? ''));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: Material(
        color: bg == null ? const Color(0xFFE6E6E6) : const Color(0xFF12382A),
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: c.autoRoast ? () => _msg('Tắt AUTO trước khi đổi Profile Auto') : _pickProfile,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Profile Auto',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: bg == null ? Colors.black87 : const Color(0xFFE8A27C))),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: bg == null ? Colors.black54 : Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickProfile() async {
    final list = await c.storage.list();
    if (!mounted) return;
    String two(int v) => v.toString().padLeft(2, '0');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: c,
        builder: (ctx, _) => AlertDialog(
          title: const Text('Chọn Profile để rang auto'),
          contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          content: SizedBox(
            width: 520,
            child: list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Chưa có mẻ rang nào được lưu. Hãy rang tay một mẻ ưng ý, lưu lại rồi chọn ở đây.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in list.where((x) => x.error == null))
                        Builder(builder: (_) {
                          final sel = c.backgroundFile == s.fileName;
                          return Card(
                            color: sel ? const Color(0xFF12382A) : null,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: sel ? const Color(0xFFC4561D) : Colors.black12, width: sel ? 3 : 1),
                            ),
                            child: ListTile(
                              leading: Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: sel ? const Color(0xFFE8A27C) : Colors.black38),
                              title: Text(s.title,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, color: sel ? Colors.white : Colors.black87)),
                              subtitle: Text(
                                [
                                  '${two(s.date.day)}/${two(s.date.month)}/${s.date.year} ${two(s.date.hour)}:${two(s.date.minute)}',
                                  if (s.beans.isNotEmpty) s.beans,
                                  if (s.totalTime != null) 'Tổng ${fmtTime(s.totalTime)}',
                                  if (s.fcTime != null) 'FC ${fmtTime(s.fcTime)}',
                                  if (s.dropBT != null) 'DROP ${s.dropBT!.toStringAsFixed(1)}°C',
                                ].join('  •  '),
                                style: TextStyle(color: sel ? Colors.white70 : Colors.black54),
                              ),
                              trailing: sel
                                  ? const Text('ĐANG CHỌN',
                                      style: TextStyle(color: Color(0xFFE8A27C), fontWeight: FontWeight.bold))
                                  : null,
                              onTap: () async {
                                try {
                                  await c.setBackgroundFile(s.fileName);
                                  if (!c.settings.showBackground) {
                                    c.settings.showBackground = true;
                                    await c.applySettings(c.settings);
                                  }
                                } catch (e) {
                                  _msg('Không mở được: $e', error: true);
                                }
                              },
                            ),
                          );
                        }),
                    ],
                  ),
          ),
          actions: [
            if (c.background != null)
              TextButton(onPressed: () => c.setBackgroundFile(null), child: const Text('Bỏ chọn')),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Xong')),
          ],
        ),
      ),
    );
  }

  Future<void> _autoPressed() async {
    if (!c.autoRoast) {
      final err = c.canAutoRoast();
      if (err != null) {
        _msg(err, error: true);
        return;
      }
      final bg = c.background!;
      final ok = await _confirm(
          'Rang tự động',
          'Làm theo Profile Auto "${bg.title.isNotEmpty ? bg.title : c.backgroundFile}":\n\n'
              '• Lúc CHARGE: Gas / Trống / Quạt đặt về đúng như mẻ mẫu lúc CHARGE.\n'
              '• Sau đó: mẻ mẫu chỉnh thông số ở mốc BT nào thì mẻ này chỉnh y như vậy khi BT đạt mốc đó '
              '(trước TP thì theo thời gian).\n\n'
              'Bấm AUTO lần nữa để quay về điều khiển tay.',
          ok: 'Bật');
      if (!ok) return;
    }
    final err = c.toggleAutoRoast();
    if (err != null) _msg(err, error: true);
  }

  Future<void> _pressButton(int i) async {
    final err = await c.pressButton(i);
    if (err != null && mounted) _msg(err, error: true);
  }

  Future<void> _eventsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: c,
        builder: (ctx, _) {
          final p = c.profile;
          return AlertDialog(
            title: const Text('Sự kiện mẻ rang'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Các sự kiện được tự nhận diện. Chỉ dùng màn hình này khi cần sửa tay.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  for (final e in RoastEvent.values)
                    ListTile(
                      dense: true,
                      title: Text(e.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(() {
                        final i = e == RoastEvent.tp ? p.effectiveTP : p.indexOf(e);
                        if (i == null) return 'chưa có';
                        final t = e == RoastEvent.charge ? '' : '${fmtTime(p.rel(i))}  •  ';
                        return '$t${fmtTemp(p.bt[i])}°C';
                      }()),
                      trailing: p.indexOf(e) != null
                          ? TextButton(
                              onPressed: () {
                                final err = c.undoEvent(e);
                                if (err != null) _msg(err);
                              },
                              child: const Text('Bỏ'))
                          : TextButton(
                              onPressed: c.canMark(e)
                                  ? () {
                                      final err = c.markEvent(e);
                                      if (err != null) _msg(err);
                                    }
                                  : null,
                              child: const Text('Đánh dấu ngay')),
                    ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
          );
        },
      ),
    );
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'events':
        await _eventsDialog();
        break;
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
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset('assets/icon/app_icon.png', width: 32, height: 32),
          ),
          const SizedBox(width: 8),
          if (compact) ...[
            const Spacer(),
          ] else
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
                    'Modbus ${c.settings.host}:${c.settings.port}',
                    if (c.background != null && c.settings.showBackground)
                      'Profile Auto: ${c.background!.title.isNotEmpty ? c.background!.title : c.backgroundFile}',
                    if (c.dirty && c.hasData && !c.isOn) 'chưa lưu',
                  ].join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Colors.black54),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            SizedBox(width: 150, child: _profileAutoButton()),
            PredictionLcd(label: c.prediction(false).$1, value: c.prediction(false).$2),
            PredictionLcd(label: c.prediction(true).$1, value: c.prediction(true).$2),
          ],
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
              const PopupMenuItem(value: 'events', child: ListTile(leading: Icon(Icons.flag), title: Text('Sự kiện (sửa tay)'))),
              const PopupMenuItem(value: 'props', child: ListTile(leading: Icon(Icons.edit_note), title: Text('Thuộc tính mẻ rang'))),
              PopupMenuItem(
                  value: 'save',
                  enabled: !c.isOn && c.hasData,
                  child: const ListTile(leading: Icon(Icons.save), title: Text('Lưu mẻ rang'))),
              const PopupMenuItem(
                  value: 'history', child: ListTile(leading: Icon(Icons.history), title: Text('Lịch sử rang'))),
              PopupMenuItem(
                  value: 'bg_toggle',
                  child: ListTile(
                      leading: Icon(c.settings.showBackground ? Icons.layers_clear : Icons.layers),
                      title: Text(c.settings.showBackground ? 'Ẩn đường Profile Auto' : 'Hiện đường Profile Auto'))),
              const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings), title: Text('Cài đặt'))),
            ],
          ),
          CommandButton(
              label: c.autoRoast ? 'AUTO ✓' : 'AUTO',
              color: c.autoRoast ? AC.buttonSelected : AC.buttonControl,
              onPressed: c.isOn ? _autoPressed : null,
              width: 68),
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

  Widget _buttonBar() {
    final btns = [
      for (var i = 0; i < c.settings.buttons.length; i++)
        if (c.settings.buttons[i].visible) i
    ];
    if (btns.isEmpty) return const SizedBox(height: 4);
    Widget one(int i) {
      final b = c.settings.buttons[i];
      final toggle = b.type == ButtonType.none;
      final pressed = toggle && i < c.buttonStates.length && c.buttonStates[i] != 0;
      return ArtisanButton(
        label: b.label,
        color: Color(b.color),
        textColor: Color(b.textColor),
        pressed: pressed,
        last: toggle && c.lastButton == i,
        enabled: c.isOn,
        onTap: () => _pressButton(i),
      );
    }

    return SizedBox(
      height: 50,
      child: btns.length <= 10
          ? Row(children: [for (final i in btns) Expanded(child: one(i))])
          : ListView(
              scrollDirection: Axis.horizontal,
              children: [for (final i in btns) SizedBox(width: 96, child: one(i))],
            ),
    );
  }

  String _eventSummary() {
    final p = c.profile;
    String one(RoastEvent e) {
      final i = e == RoastEvent.tp ? p.effectiveTP : p.indexOf(e);
      if (i == null) return '${e.shortLabel} –';
      if (e == RoastEvent.charge) return '${e.shortLabel} ✓';
      return '${e.shortLabel} ${fmtTime(p.rel(i))}';
    }

    return RoastEvent.values.map(one).join('  •  ');
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
                ? '${_eventSummary()}     (${c.profile.length} mẫu, ${c.settings.samplingInterval.toStringAsFixed(0)} s)'
                : (c.hasData
                    ? '${_eventSummary()}${c.currentFile != null ? '     ${c.currentFile}' : ''}'
                    : 'Sẵn sàng – bấm ON để bắt đầu. CHARGE, TP, DRY END, FC START, DROP được tự nhận diện.')),
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
        _buttonBar(),
        _statusLine(),
      ],
    );
  }

  Widget _portrait() {
    final ctrls = _visibleControls;
    return Column(
      children: [
        _topBar(true),
        SizedBox(
          height: 46,
          child: Row(children: [
            const SizedBox(width: 4),
            Expanded(child: _profileAutoButton()),
            PredictionLcd(label: c.prediction(false).$1, value: c.prediction(false).$2),
            PredictionLcd(label: c.prediction(true).$1, value: c.prediction(true).$2),
            const SizedBox(width: 4),
          ]),
        ),
        SizedBox(height: 110, child: LcdPanel(c: c, vertical: false)),
        Expanded(child: _chart()),
        if (ctrls.isNotEmpty)
          Container(
            color: const Color(0xFFF5F5F5),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(children: [for (final i in ctrls) ControlSlider(c: c, index: i, vertical: false)]),
          ),
        _buttonBar(),
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
