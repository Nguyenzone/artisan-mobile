import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/roast_profile.dart';
import '../services/roast_storage.dart';
import '../services/roaster_device.dart';
import '../services/settings.dart';
import 'ror.dart';

const String kSampleAsset = 'assets/profiles/profile_mau_rang_vua.alog';

/// Bộ điều khiển trung tâm: lấy mẫu, ghi dữ liệu, sự kiện, điều khiển, nền.
class RoastController extends ChangeNotifier {
  RoastController(this.settings, this.storage)
      : controlValues = List<double>.generate(4, (i) => settings.controls[i].min.toDouble());

  AppSettings settings;
  final RoastStorage storage;

  RoastProfile profile = RoastProfile();
  String? currentFile; // tên file trong thư viện (nếu đã lưu / mở)
  bool dirty = false; // có dữ liệu chưa lưu

  bool _on = false;
  bool get isOn => _on;
  bool connecting = false;

  RoasterDevice? _device;
  Timer? _timer;
  Timer? _clockTimer;
  DateTime? _startTime;
  bool _busy = false;
  String? lastError;

  /// Đồng hồ (giây kể từ khi bấm ON), cập nhật 4 lần / giây.
  final ValueNotifier<double> clock = ValueNotifier<double>(0);

  double? curBT, curET, curCT;
  List<double?> rorBT = [];
  List<double?> rorET = [];

  RoastProfile? background;
  String? backgroundFile;
  List<double?> bgRorBT = [];

  List<double> controlValues;

  bool get hasData => profile.timex.isNotEmpty;

  double? get deltaBT => _lastNonNull(rorBT);
  double? get deltaET => _lastNonNull(rorET);

  static double? _lastNonNull(List<double?> l) {
    for (var i = l.length - 1; i >= 0 && i >= l.length - 3; i--) {
      if (l[i] != null) return l[i];
    }
    return null;
  }

  // ------------------------------------------------------------ khởi động

  Future<void> init() async {
    if (!settings.sampleInstalled) {
      try {
        final text = await rootBundle.loadString(kSampleAsset);
        final name = await storage.importText(text, 'profile_mau_rang_vua.alog');
        settings.sampleInstalled = true;
        settings.backgroundFile ??= name;
        await settings.save();
      } catch (e) {
        debugPrint('Không cài được profile mẫu: $e');
      }
    }
    final bg = settings.backgroundFile;
    if (bg != null) {
      try {
        if (await storage.exists(bg)) {
          await setBackgroundFile(bg, persist: false);
        }
      } catch (_) {
        background = null;
      }
    }
  }

  // ------------------------------------------------------------ ON / OFF

  Future<bool> turnOn() async {
    if (_on || connecting) return false;
    connecting = true;
    lastError = null;
    notifyListeners();
    final RoasterDevice dev = settings.simulator ? SimulatedRoasterDevice() : ModbusRoasterDevice(settings);
    try {
      await dev.connect();
    } catch (e) {
      connecting = false;
      lastError = e.toString();
      notifyListeners();
      return false;
    }
    _device = dev;
    profile = RoastProfile(samplingInterval: settings.samplingInterval)..hasCT = settings.ct.enabled;
    currentFile = null;
    rorBT = [];
    rorET = [];
    curBT = curET = curCT = null;
    _startTime = DateTime.now();
    clock.value = 0;
    _on = true;
    connecting = false;
    dirty = true;
    if (settings.keepScreenOn) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
    if (settings.simulator) {
      for (var i = 0; i < 4; i++) {
        if (settings.controls[i].visible) {
          await dev.writeControl(i, controlValues[i]);
        }
      }
    }
    final ms = (settings.samplingInterval * 1000).round().clamp(500, 10000).toInt();
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) => _sample());
    _clockTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final st = _startTime;
      if (st != null) clock.value = DateTime.now().difference(st).inMilliseconds / 1000.0;
    });
    notifyListeners();
    unawaited(_sample());
    return true;
  }

  Future<void> _sample() async {
    final dev = _device;
    final st = _startTime;
    if (!_on || dev == null || st == null || _busy) return;
    _busy = true;
    final t = DateTime.now().difference(st).inMilliseconds / 1000.0;
    Reading r;
    try {
      r = await dev.read();
    } catch (e) {
      r = Reading(error: e.toString());
    }
    _busy = false;
    if (!_on) return;
    profile.timex.add(t);
    profile.et.add(r.et ?? -1.0);
    profile.bt.add(r.bt ?? -1.0);
    profile.ct.add(r.ct ?? -1.0);
    curBT = r.bt;
    curET = r.et;
    curCT = r.ct;
    lastError = r.error;
    _recomputeRoR();
    notifyListeners();
  }

  Future<void> turnOff() async {
    if (!_on) return;
    _on = false;
    _timer?.cancel();
    _clockTimer?.cancel();
    _timer = null;
    _clockTimer = null;
    final dev = _device;
    _device = null;
    try {
      await dev?.close();
    } catch (_) {}
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    if (profile.ct.every((v) => v < 0)) profile.hasCT = false;
    notifyListeners();
  }

  void reset() {
    if (_on) return;
    profile = RoastProfile(samplingInterval: settings.samplingInterval);
    currentFile = null;
    dirty = false;
    rorBT = [];
    rorET = [];
    curBT = curET = curCT = null;
    clock.value = 0;
    lastError = null;
    notifyListeners();
  }

  void _recomputeRoR() {
    final start = profile.hasCharge ? profile.timeindex[EventIdx.charge] : 0;
    rorBT = computeRoR(profile.timex, profile.bt,
        span: settings.rorSpan, smoothing: settings.rorSmoothing, startIndex: start);
    rorET = computeRoR(profile.timex, profile.et,
        span: settings.rorSpan, smoothing: settings.rorSmoothing, startIndex: start);
  }

  // ------------------------------------------------------------ sự kiện

  String? _checkOrder(RoastEvent e, int idx) {
    if (e != RoastEvent.charge && !profile.hasCharge) {
      return 'Cần đánh dấu CHARGE trước';
    }
    for (final o in RoastEvent.values) {
      if (o == e) continue;
      final oi = profile.indexOf(o);
      if (oi == null) continue;
      if (o.index < e.index && idx <= oi) {
        return 'Chờ dữ liệu mới sau ${o.label}';
      }
      if (o.index > e.index) {
        return 'Đã có ${o.label} – không thể đánh dấu ${e.label}';
      }
    }
    return null;
  }

  bool canMark(RoastEvent e) {
    if (!_on || profile.timex.isEmpty) return false;
    if (profile.indexOf(e) != null) return false;
    return _checkOrder(e, profile.timex.length - 1) == null;
  }

  /// Đánh dấu sự kiện tại mẫu mới nhất. Trả về thông báo lỗi hoặc null.
  String? markEvent(RoastEvent e) {
    if (!_on) return 'Hãy bấm ON trước';
    if (profile.timex.isEmpty) return 'Chưa có dữ liệu';
    if (profile.indexOf(e) != null) return '${e.label} đã được đánh dấu';
    final idx = profile.timex.length - 1;
    final err = _checkOrder(e, idx);
    if (err != null) return err;
    profile.setEvent(e, idx);
    _device?.onRoastEvent(e);
    if (e == RoastEvent.charge) _recomputeRoR();
    dirty = true;
    notifyListeners();
    return null;
  }

  /// Bỏ đánh dấu sự kiện (chỉ khi chưa có sự kiện nào sau nó).
  String? undoEvent(RoastEvent e) {
    if (profile.indexOf(e) == null) return null;
    for (final o in RoastEvent.values) {
      if (o.index > e.index && profile.indexOf(o) != null) {
        return 'Hãy bỏ ${o.label} trước';
      }
    }
    profile.setEvent(e, null);
    if (e == RoastEvent.charge) _recomputeRoR();
    dirty = true;
    notifyListeners();
    return null;
  }

  // ------------------------------------------------------------ điều khiển

  void setControlLocal(int i, double v) {
    controlValues[i] = v;
    notifyListeners();
  }

  /// Gửi giá trị điều khiển xuống máy rang và ghi thành sự kiện (special event).
  Future<void> commitControl(int i, double v) async {
    controlValues[i] = v;
    if (_on && profile.timex.isNotEmpty) {
      final idx = profile.timex.length - 1;
      final same = profile.events.where((x) => x.index == idx && x.type == i).toList();
      if (same.isNotEmpty) {
        same.first.value = v;
      } else {
        profile.events.add(SpecialEvent(index: idx, type: i, value: v));
      }
      dirty = true;
    }
    notifyListeners();
    final dev = _device;
    if (dev == null) return;
    try {
      await dev.writeControl(i, v);
    } catch (e) {
      lastError = 'Lỗi ghi ${settings.controls[i].label}: $e';
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ lưu / mở

  Future<String> save() async {
    final name = await storage.save(profile, fileName: currentFile);
    currentFile = name;
    dirty = false;
    notifyListeners();
    return name;
  }

  Future<void> openFile(String fileName) async {
    if (_on) return;
    final p = await storage.load(fileName);
    profile = p;
    currentFile = fileName;
    dirty = false;
    curBT = curET = curCT = null;
    lastError = null;
    _recomputeRoR();
    notifyListeners();
  }

  Future<void> deleteFile(String fileName) async {
    await storage.delete(fileName);
    if (currentFile == fileName) currentFile = null;
    if (backgroundFile == fileName) await setBackgroundFile(null);
    notifyListeners();
  }

  Future<void> setBackgroundFile(String? fileName, {bool persist = true}) async {
    if (fileName == null) {
      background = null;
      backgroundFile = null;
      bgRorBT = [];
    } else {
      final p = await storage.load(fileName);
      background = p;
      backgroundFile = fileName;
      _recomputeBgRoR();
    }
    settings.backgroundFile = fileName;
    if (persist) await settings.save();
    notifyListeners();
  }

  void _recomputeBgRoR() {
    final bg = background;
    if (bg == null) {
      bgRorBT = [];
      return;
    }
    bgRorBT = computeRoR(bg.timex, bg.bt,
        span: settings.rorSpan,
        smoothing: settings.rorSmoothing,
        startIndex: bg.hasCharge ? bg.timeindex[EventIdx.charge] : 0);
  }

  Future<void> applySettings(AppSettings s) async {
    settings = s;
    for (var i = 0; i < 4; i++) {
      final c = settings.controls[i];
      controlValues[i] = controlValues[i].clamp(c.min.toDouble(), c.max.toDouble()).toDouble();
    }
    await settings.save();
    _recomputeRoR();
    _recomputeBgRoR();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clockTimer?.cancel();
    _device?.close();
    clock.dispose();
    super.dispose();
  }
}
