import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/roast_profile.dart';

/// Thông tin tóm tắt một mẻ rang trong thư viện.
class RoastSummary {
  RoastSummary({
    required this.fileName,
    required this.title,
    required this.beans,
    required this.date,
    this.totalTime,
    this.dropBT,
    this.fcTime,
    this.weightIn = 0,
    this.weightOut = 0,
    this.weightUnit = 'g',
    this.error,
  });

  final String fileName;
  final String title;
  final String beans;
  final DateTime date;
  final double? totalTime;
  final double? dropBT;
  final double? fcTime;
  final double weightIn;
  final double weightOut;
  final String weightUnit;
  final String? error;

  double? get lossPct => (weightIn > 0 && weightOut > 0) ? (weightIn - weightOut) / weightIn * 100 : null;
}

RoastProfile _parseAlog(String text) => RoastProfile.fromAlogString(text);

List<RoastSummary> _summarizeAll(List<String> paths) {
  final out = <RoastSummary>[];
  for (final path in paths) {
    final name = path.split(Platform.pathSeparator).last;
    try {
      final text = File(path).readAsStringSync();
      final p = RoastProfile.fromAlogString(text);
      final drop = p.indexOf(RoastEvent.drop);
      final fc = p.indexOf(RoastEvent.fcStart);
      out.add(RoastSummary(
        fileName: name,
        title: p.title.isEmpty ? name : p.title,
        beans: p.beans,
        date: p.roastDate,
        totalTime: drop != null && p.hasCharge ? p.rel(drop) : null,
        dropBT: drop != null ? p.bt[drop] : null,
        fcTime: fc != null && p.hasCharge ? p.rel(fc) : null,
        weightIn: p.weightIn,
        weightOut: p.weightOut,
        weightUnit: p.weightUnit,
      ));
    } catch (e) {
      out.add(RoastSummary(
        fileName: name,
        title: name,
        beans: '',
        date: File(path).statSync().modified,
        error: e.toString(),
      ));
    }
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

/// Thư viện mẻ rang: các file .alog trong thư mục riêng của ứng dụng.
class RoastStorage {
  RoastStorage._(this.dir);

  final Directory dir;

  static Future<RoastStorage> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}${Platform.pathSeparator}roasts');
    if (!await d.exists()) await d.create(recursive: true);
    return RoastStorage._(d);
  }

  String pathOf(String fileName) => '${dir.path}${Platform.pathSeparator}$fileName';

  Future<List<RoastSummary>> list() async {
    final paths = <String>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.alog')) paths.add(e.path);
    }
    if (paths.isEmpty) return <RoastSummary>[];
    return compute(_summarizeAll, paths);
  }

  Future<bool> exists(String fileName) => File(pathOf(fileName)).exists();

  Future<RoastProfile> load(String fileName) async {
    final text = await File(pathOf(fileName)).readAsString();
    return compute(_parseAlog, text);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _slug(String s) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final sb = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      final c = i >= 0 ? to[i] : ch;
      sb.write(RegExp(r'[a-z0-9_-]').hasMatch(c) ? c : '_');
    }
    var r = sb.toString().replaceAll(RegExp(r'_+'), '_');
    if (r.length > 40) r = r.substring(0, 40);
    return r.replaceAll(RegExp(r'^_|_$'), '');
  }

  String suggestFileName(RoastProfile p) {
    final d = p.roastDate;
    final base = '${d.year}-${_two(d.month)}-${_two(d.day)}_${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';
    final slug = _slug(p.title);
    return slug.isEmpty ? '$base.alog' : '${base}_$slug.alog';
  }

  Future<String> _unique(String fileName) async {
    var name = fileName.toLowerCase().endsWith('.alog') ? fileName : '$fileName.alog';
    final stem = name.substring(0, name.length - 5);
    var i = 1;
    while (await File(pathOf(name)).exists()) {
      name = '${stem}_$i.alog';
      i++;
    }
    return name;
  }

  /// Lưu mẻ rang. Nếu [fileName] đã có thì ghi đè, ngược lại tạo tên mới.
  Future<String> save(RoastProfile p, {String? fileName}) async {
    final name = fileName ?? await _unique(suggestFileName(p));
    await File(pathOf(name)).writeAsString(p.toAlogString(), flush: true);
    return name;
  }

  /// Nhập nội dung .alog (từ máy tính / Artisan). Trả về tên file trong thư viện.
  Future<String> importText(String text, String originalName) async {
    final p = await compute(_parseAlog, text); // kiểm tra hợp lệ
    var base = originalName.split(RegExp(r'[\\/]')).last;
    if (!base.toLowerCase().endsWith('.alog')) {
      base = suggestFileName(p);
    }
    final name = await _unique(base);
    await File(pathOf(name)).writeAsString(text, flush: true);
    return name;
  }

  Future<Uint8List> bytesOf(String fileName) async {
    final f = File(pathOf(fileName));
    return f.readAsBytes();
  }

  Future<void> delete(String fileName) async {
    final f = File(pathOf(fileName));
    if (await f.exists()) await f.delete();
  }

  static String decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
}
