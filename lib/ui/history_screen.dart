import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../logic/roast_controller.dart';
import '../models/roast_profile.dart';
import '../services/roast_storage.dart';
import 'artisan_colors.dart';

/// Lịch sử rang: mở xem, nhập / xuất file .alog, xoá.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.c});

  final RoastController c;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  RoastController get c => widget.c;
  late Future<List<RoastSummary>> _future;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _future = c.storage.list();
  }

  void _reload() => setState(() => _future = c.storage.list());

  void _msg(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? const Color(0xFFB00020) : null));
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _date(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

  Future<void> _import() async {
    try {
      final files = await FilePicker.pickFiles(dialogTitle: 'Chọn file .alog');
      if (files.isEmpty) return;
      var ok = 0;
      final errors = <String>[];
      for (final f in files) {
        try {
          final bytes = await f.readAsBytes();
          await c.storage.importText(RoastStorage.decode(bytes), f.name);
          ok++;
        } catch (e) {
          errors.add('${f.name}: $e');
        }
      }
      _reload();
      if (errors.isEmpty) {
        _msg('Đã nhập $ok file');
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Đã nhập $ok file, lỗi ${errors.length} file'),
            content: SingleChildScrollView(child: Text(errors.join('\n\n'))),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
          ),
        );
      }
    } catch (e) {
      _msg('Lỗi nhập file: $e', error: true);
    }
  }

  Future<void> _export(RoastSummary s) async {
    try {
      final bytes = await c.storage.bytesOf(s.fileName);
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Xuất file .alog',
        fileName: s.fileName,
        bytes: bytes,
        mimeType: 'text/plain',
      );
      if (uri != null) _msg('Đã xuất: ${uri.scheme == 'file' ? uri.toFilePath() : s.fileName}');
    } catch (e) {
      _msg('Lỗi xuất file: $e', error: true);
    }
  }

  Future<void> _open(RoastSummary s) async {
    if (c.isOn) {
      _msg('Đang rang – bấm OFF trước khi mở mẻ khác');
      return;
    }
    if (c.dirty && c.hasData) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mẻ hiện tại chưa lưu'),
          content: const Text('Mở mẻ khác sẽ bỏ dữ liệu chưa lưu. Tiếp tục?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mở')),
          ],
        ),
      );
      if (go != true) return;
    }
    try {
      await c.openFile(s.fileName);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _msg('Không mở được: $e', error: true);
    }
  }

  Future<void> _delete(RoastSummary s) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá mẻ rang?'),
        content: Text('Xoá "${s.title}" (${s.fileName}) khỏi điện thoại?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB00020)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xoá')),
        ],
      ),
    );
    if (go != true) return;
    await c.deleteFile(s.fileName);
    _reload();
  }

  Widget _tile(RoastSummary s) {
    final isCur = c.currentFile == s.fileName;
    final parts = <String>[
      if (s.totalTime != null) 'Tổng ${fmtTime(s.totalTime)}',
      if (s.fcTime != null) 'FC ${fmtTime(s.fcTime)}',
      if (s.dropBT != null) 'DROP ${s.dropBT!.toStringAsFixed(1)}°C',
      if (s.weightIn > 0) '${s.weightIn.toStringAsFixed(0)}${s.weightUnit}',
      if (s.lossPct != null) 'hao hụt ${s.lossPct!.toStringAsFixed(1)}%',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: s.error != null ? Colors.grey : AC.buttonMajor,
          child: Icon(s.error != null ? Icons.error_outline : Icons.local_fire_department,
              color: Colors.white),
        ),
        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: isCur ? FontWeight.bold : FontWeight.w600)),
        subtitle: Text(
          [
            '${_date(s.date)}${s.beans.isNotEmpty ? '  •  ${s.beans}' : ''}',
            if (s.error != null) 'Lỗi đọc file: ${s.error}' else parts.join('  •  '),
          ].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        onTap: s.error == null ? () => _open(s) : null,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'open':
                _open(s);
                break;
              case 'export':
                _export(s);
                break;
              case 'delete':
                _delete(s);
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'open',
                enabled: s.error == null,
                child: const ListTile(leading: Icon(Icons.show_chart), title: Text('Mở xem'))),
            const PopupMenuItem(
                value: 'export', child: ListTile(leading: Icon(Icons.ios_share), title: Text('Xuất file .alog'))),
            const PopupMenuItem(
                value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Xoá'))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử rang'),
        actions: [
          IconButton(tooltip: 'Nhập file .alog', icon: const Icon(Icons.file_open), onPressed: _import),
          IconButton(tooltip: 'Tải lại', icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Tìm theo tên mẻ / loại hạt',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RoastSummary>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Lỗi: ${snap.error}'));
                }
                final all = snap.data ?? const <RoastSummary>[];
                final list = _filter.isEmpty
                    ? all
                    : all
                        .where((s) =>
                            s.title.toLowerCase().contains(_filter) || s.beans.toLowerCase().contains(_filter))
                        .toList();
                if (list.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Chưa có mẻ rang nào.\nBấm ON để rang, hoặc biểu tượng 📂 để nhập file .alog từ Artisan.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => _tile(list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
