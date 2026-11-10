import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/roast_profile.dart';
import '../services/roast_storage.dart';
import '../services/roaster_device.dart';
import '../services/settings.dart';
import 'auto_events.dart';
import 'auto_replay.dart';
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

  /// Tự nhận diện sự kiện (CHARGE, TP, DRY END, FC START, DROP).
  final AutoEventDetector autoEvents = AutoEventDetector();

  /// Thông báo ngắn (ví dụ "Tự nhận CHARGE") cho giao diện hiển thị.
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  // ------------------------------------------------------------ rang tự động
  bool _autoRoast = false;
  bool get autoRoast => _autoRoast;
  AutoReplay? _replay;
  AutoReplay? get replay => _replay;

  /// Trạng thái nút (0/1, giống buttonStates của Artisan) và nút bấm gần nhất.
  List<int> buttonStates = [];
  int lastButton = -1;

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
    final RoasterDevice dev = ModbusRoasterDevice(settings);
    try {
      await dev.connect();
    } catch (e) {
      connecting = false;
      lastError = e.toString();
      notifyListeners();
      return false;
    }
    _device = dev;
    autoEvents.reset();
    buttonStates = List<int>.filled(settings.buttons.length, 0);
    lastButton = -1;
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
    _autoDetect();
    _recomputeRoR();
    _autoRoastStep();
    notifyListeners();
  }

  AutoEventParams get _autoParams => AutoEventParams(
        autoCharge: settings.autoCharge,
        autoTP: settings.autoTP,
        autoDryEnd: settings.autoDryEnd,
        dryEndTemp: settings.dryEndTemp,
        autoFcStart: settings.autoFcStart,
        fcStartTemp: settings.fcStartTemp,
        autoDrop: settings.autoDrop,
      );

  void _autoDetect() {
    final found = autoEvents.check(profile, _autoParams);
    if (found.isEmpty) return;
    dirty = true;
    final p = profile;
    final msg = found.map((f) {
      final (e, idx) = f;
      final t = e == RoastEvent.charge ? '' : ' ${fmtTime(p.rel(idx))}';
      return '${e.label}$t ${p.bt[idx].toStringAsFixed(1)}°C';
    }).join(' • ');
    notice.value = 'Tự nhận: $msg';
  }

  Future<void> turnOff() async {
    if (!_on) return;
    _stopAutoRoast();
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

  // ------------------------------------------------------------ rang tự động

  String? canAutoRoast() {
    if (!_on) return 'Bấm ON để kết nối máy rang trước';
    final bg = background;
    if (bg == null) return 'Chưa chọn Profile Auto. Bấm nút "Profile Auto" để chọn.';
    if (!bg.hasCharge) return 'Profile Auto không có CHARGE';
    final r = AutoReplay(bg);
    if (r.totalCount == 0 && r.chargeValues.isEmpty) {
      return 'Profile Auto không có thay đổi Gas / Trống / Quạt nào để làm theo';
    }
    if (profile.indexOf(RoastEvent.drop) != null) return 'Mẻ này đã DROP';
    return null;
  }

  /// Bật / tắt rang tự động. Trả về thông báo lỗi hoặc null.
  String? toggleAutoRoast() {
    if (_autoRoast) {
      _stopAutoRoast();
      notice.value = 'Đã tắt rang tự động – điều khiển tay';
      notifyListeners();
      return null;
    }
    final err = canAutoRoast();
    if (err != null) return err;
    _replay = AutoReplay(background!);
    _autoRoast = true;
    notice.value = profile.hasCharge
        ? 'Đã bật rang tự động (${_replay!.totalCount} mốc điều chỉnh)'
        : 'Đã bật rang tự động – chờ CHARGE (${_replay!.totalCount} mốc điều chỉnh)';
    // đã CHARGE rồi thì áp dụng ngay các mốc đã qua
    if (profile.hasCharge) _applyReplay(_replay!.step(profile));
    notifyListeners();
    return null;
  }

  void _stopAutoRoast() {
    _autoRoast = false;
    _replay = null;
  }

  void _autoRoastStep() {
    final r = _replay;
    if (!_autoRoast || r == null) return;
    if (profile.indexOf(RoastEvent.drop) != null) {
      _stopAutoRoast();
      notice.value = 'DROP – đã tắt rang tự động';
      return;
    }
    final wasCharged = r.chargeApplied;
    final vals = r.step(profile);
    if (vals.isEmpty) return;
    _applyReplay(vals);
    final names = vals.entries.map((e) => '${settings.controls[e.key].label} ${e.value.round()}').join(', ');
    notice.value = !wasCharged ? 'CHARGE – đặt theo profile mẫu: $names' : 'Auto: $names';
  }

  void _applyReplay(Map<int, double> vals) {
    vals.forEach((type, v) {
      final c = settings.controls[type];
      final nv = v.clamp(c.min.toDouble(), c.max.toDouble()).toDouble();
      commitControl(type, nv);
    });
  }

  // ------------------------------------------------------------ dự đoán DRY / FCs

  /// Dự đoán thời điểm (giây sau CHARGE) đạt DRY / FCs – giống phases LCD của Artisan:
  /// thời gian còn lại = (nhiệt độ mục tiêu − BT) / (ΔBT / 60).
  /// Trả về (nhãn, giá trị): trước sự kiện "»DRY" + thời gian dự đoán; sau sự kiện "DRY»" + thời gian đã qua.
  (String, String) prediction(bool fcs) {
    final p = profile;
    final name = fcs ? 'FCs' : 'DRY';
    if (p.timex.isEmpty || !p.hasCharge) return ('»$name', '--:--');
    final tx = p.timex.last;
    final ev = p.indexOf(fcs ? RoastEvent.fcStart : RoastEvent.dryEnd);
    if (ev != null) {
      // đã qua mốc: đồng hồ dừng, hiện thời điểm DRY / FCs (tính từ CHARGE)
      return (name, fmtTime(p.rel(ev)));
    }
    final bt = p.bt.last;
    final ror = deltaBT;
    if (ror == null || ror <= 0 || bt < 0) return ('»$name', '--:--');
    final bg = background;
    double target;
    if (!fcs) {
      // Artisan: mục tiêu DRY lấy từ nền nếu không bật Auto DRY, ngược lại dùng nhiệt độ cài đặt
      final bgDry = bg?.indexOf(RoastEvent.dryEnd);
      target = (!settings.autoDryEnd && bg != null && bgDry != null) ? bg.bt[bgDry] : settings.dryEndTemp;
      if (p.effectiveTP == null) return ('»$name', '--:--');
    } else {
      final dryDone = p.indexOf(RoastEvent.dryEnd) != null;
      final dryTarget = settings.dryEndTemp;
      if (!dryDone && dryTarget > bt) return ('»$name', '--:--');
      final bgFcs = bg?.indexOf(RoastEvent.fcStart);
      target = (bg != null && bgFcs != null) ? bg.bt[bgFcs] : settings.fcStartTemp;
    }
    if (target <= bt) return ('»$name', '--:--');
    final remain = (target - bt) / (ror / 60.0);
    if (remain > 3600) return ('»$name', '--:--');
    return ('»$name', fmtTime(tx - p.chargeTime + remain));
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
    if (e == RoastEvent.charge) {
      autoEvents.chargeDisabled = true; // không tự nhận lại sau khi người dùng bỏ
      _recomputeRoR();
    }
    if (e == RoastEvent.drop) autoEvents.dropDisabled = true;
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
    _recordControlEvent(i, v);
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

  void _recordControlEvent(int type, double v) {
    if (!_on || profile.timex.isEmpty) return;
    final idx = profile.timex.length - 1;
    final same = profile.events.where((x) => x.index == idx && x.type == type).toList();
    if (same.isNotEmpty) {
      same.first.value = v;
    } else {
      profile.events.add(SpecialEvent(index: idx, type: type, value: v));
    }
    dirty = true;
  }

  /// Bấm nút sự kiện tuỳ chỉnh – xử lý giống recordextraevent() của Artisan.
  /// Trả về thông báo lỗi hoặc null.
  Future<String?> pressButton(int i) async {
    if (i < 0 || i >= settings.buttons.length) return null;
    final dev = _device;
    if (!_on || dev == null) return 'Bấm ON để kết nối máy rang trước';
    final b = settings.buttons[i];
    if (buttonStates.length != settings.buttons.length) {
      buttonStates = List<int>.filled(settings.buttons.length, 0);
    }
    buttonStates[i] = buttonStates[i] == 0 ? 1 : 0;
    lastButton = i;
    notifyListeners();
    try {
      if (b.type == ButtonType.none) {
        await dev.runCommand(b.command, value: b.value, buttonState: buttonStates[i]);
        return null;
      }
      // Loại Air/Drum/Damper/Burner (tuyệt đối) hoặc ±Air... (tương đối)
      final etype = b.type >= ButtonType.relAir ? b.type - ButtonType.relAir : b.type;
      if (etype < 0 || etype > 3) return null;
      final c = settings.controls[etype];
      var nv = b.type >= ButtonType.relAir ? controlValues[etype] + b.value : b.value.toDouble();
      nv = nv.clamp(c.min.toDouble(), c.max.toDouble()).toDouble();
      controlValues[etype] = nv;
      _recordControlEvent(etype, nv);
      notifyListeners();
      await dev.runCommand(b.command, value: c.toRegister(nv), buttonState: buttonStates[i]);
      return null;
    } catch (e) {
      lastError = 'Nút ${b.label}: $e';
      notifyListeners();
      return lastError;
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
    notice.dispose();
    super.dispose();
  }
}
