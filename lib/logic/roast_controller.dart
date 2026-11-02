import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/roast_profile.dart';
import '../services/roast_storage.dart';
import '../services/roaster_device.dart';
import '../services/settings.dart';
import 'auto_events.dart';
import 'pid.dart';
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

  // ------------------------------------------------------------ rang tự động (PID)
  final Pid pid = Pid();
  bool _autoRoast = false;
  bool get autoRoast => _autoRoast;
  double? sv; // điểm đặt hiện tại (BT của profile nền)

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
    _pidStep(t, r.bt);
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

  /// BT của profile nền tại [rel] giây sau CHARGE (nội suy tuyến tính), null nếu ngoài phạm vi.
  double? backgroundBTat(double rel) {
    final bg = background;
    if (bg == null || bg.timex.isEmpty || !bg.hasCharge) return null;
    final t = bg.chargeTime + rel;
    final drop = bg.indexOf(RoastEvent.drop);
    final lastT = drop != null ? bg.timex[drop] : bg.timex.last;
    if (t > lastT || t < bg.timex.first) return null;
    var i = 0;
    while (i + 1 < bg.timex.length && bg.timex[i + 1] < t) {
      i++;
    }
    if (i + 1 >= bg.timex.length) return bg.bt[i] < 0 ? null : bg.bt[i];
    final a = bg.bt[i], b = bg.bt[i + 1];
    if (a < 0 || b < 0) return null;
    final t0 = bg.timex[i], t1 = bg.timex[i + 1];
    return t1 == t0 ? a : a + (b - a) * (t - t0) / (t1 - t0);
  }

  /// SV theo Artisan calcSV() chế độ Follow Background:
  /// trước CHARGE = BT lúc CHARGE của nền; sau CHARGE = BT nền tại (thời gian + lookahead).
  double? _calcSV() {
    final bg = background;
    if (bg == null || !bg.hasCharge) return null;
    if (!profile.hasCharge) return bg.bt[bg.timeindex[EventIdx.charge]];
    final rel = profile.timex.last - profile.chargeTime + settings.pidLookahead;
    return backgroundBTat(rel);
  }

  String? canAutoRoast() {
    if (!_on) return 'Bấm ON để kết nối máy rang trước';
    final bg = background;
    if (bg == null) return 'Chưa có profile nền. Vào Menu → Lịch sử / Profile nền để chọn.';
    if (!bg.hasCharge) return 'Profile nền không có CHARGE';
    final c = settings.controls[settings.pidTarget];
    if (c.command.trim().isEmpty) return 'Thanh trượt ${c.label} chưa có lệnh Modbus';
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
    pid
      ..kp = settings.pidKp
      ..ki = settings.pidKi
      ..kd = settings.pidKd
      ..outMin = 0
      ..outMax = 100
      ..dutyMin = settings.pidDutyMin
      ..dutyMax = settings.pidDutyMax
      ..dutySteps = settings.pidDutySteps < 1 ? 1 : settings.pidDutySteps
      ..control = _pidOutput;
    sv = _calcSV();
    if (sv != null) pid.setTarget(sv!);
    pid.reset();
    pid.on();
    _autoRoast = true;
    notice.value = 'Đã bật rang tự động theo BT của profile nền (điều khiển ${settings.controls[settings.pidTarget].label})';
    notifyListeners();
    return null;
  }

  void _stopAutoRoast() {
    pid.off();
    _autoRoast = false;
  }

  void _pidStep(double t, double? bt) {
    final newSv = _calcSV();
    if (_autoRoast) {
      if (settings.pidStopAtDrop && profile.indexOf(RoastEvent.drop) != null) {
        _stopAutoRoast();
        notice.value = 'DROP – đã tắt rang tự động';
        return;
      }
      if (newSv != null) {
        sv = newSv;
        pid.setTarget(newSv);
      }
    }
    pid.update(bt, t);
  }

  /// Đầu ra PID (0..100 %) -> giá trị thanh trượt (giống setEnergy() của Artisan).
  void _pidOutput(double duty) {
    final i = settings.pidTarget;
    final c = settings.controls[i];
    final raw = c.min + (c.max - c.min) * duty.clamp(0, 100) / 100.0;
    final step = c.step < 1 ? 1 : c.step;
    final v = ((raw / step).round() * step).clamp(c.min, c.max).toDouble();
    if (v == controlValues[i] && profile.events.isNotEmpty) {
      // giá trị không đổi: vẫn gửi lại lệnh (Artisan gửi lại định kỳ) nhưng không ghi sự kiện
      final dev = _device;
      if (dev != null) {
        dev.writeControl(i, v).catchError((Object e) {
          lastError = 'Rang tự động: $e';
        });
      }
      return;
    }
    commitControl(i, v);
  }

  // ------------------------------------------------------------ dự đoán DRY / FCs

  /// Dự đoán thời điểm (giây sau CHARGE) đạt DRY / FCs – giống phases LCD của Artisan:
  /// thời gian còn lại = (nhiệt độ mục tiêu − BT) / (ΔBT / 60).
  /// Trả về (nhãn, giá trị): trước sự kiện "»DRY" + thời gian dự đoán; sau sự kiện "DRY»" + thời gian đã qua.
  (String, String) prediction(bool fcs) {
    final p = profile;
    final name = fcs ? 'FCs' : 'DRY';
    if (p.timex.isEmpty || !p.hasCharge) return ('»$name', '--:--');
    final drop = p.indexOf(RoastEvent.drop);
    final tx = p.timex.last;
    final ev = p.indexOf(fcs ? RoastEvent.fcStart : RoastEvent.dryEnd);
    if (ev != null) {
      final end = drop != null ? p.timex[drop] : tx;
      return ('$name»', fmtTime(end - p.timex[ev]));
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
