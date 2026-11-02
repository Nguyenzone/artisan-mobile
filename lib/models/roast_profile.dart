import 'dart:math' as math;

import '../alog/python_literal.dart';

/// Chỉ số trong mảng `timeindex` của Artisan.
class EventIdx {
  static const int charge = 0;
  static const int dryEnd = 1;
  static const int fcStart = 2;
  static const int fcEnd = 3;
  static const int scStart = 4;
  static const int scEnd = 5;
  static const int drop = 6;
  static const int cool = 7;
}

/// Các nút sự kiện chính trên giao diện.
enum RoastEvent { charge, tp, dryEnd, fcStart, drop }

extension RoastEventInfo on RoastEvent {
  String get label => switch (this) {
        RoastEvent.charge => 'CHARGE',
        RoastEvent.tp => 'TP',
        RoastEvent.dryEnd => 'DRY END',
        RoastEvent.fcStart => 'FC START',
        RoastEvent.drop => 'DROP',
      };

  String get shortLabel => switch (this) {
        RoastEvent.charge => 'CHARGE',
        RoastEvent.tp => 'TP',
        RoastEvent.dryEnd => 'DE',
        RoastEvent.fcStart => 'FCs',
        RoastEvent.drop => 'DROP',
      };
}

/// Sự kiện điều khiển (Air/Drum/Damper/Burner) – "special event" trong Artisan.
class SpecialEvent {
  SpecialEvent({
    required this.index,
    required this.type,
    required this.value,
    this.label = '',
  });

  int index; // chỉ số mẫu trong timex
  int type; // 0..3 = etypes[0..3]
  double value; // giá trị hiển thị 0..100
  String label;
}

/// Giá trị nội bộ của Artisan (v/10 + 1) <-> giá trị hiển thị 0..100.
double eventExternalToInternal(double v) {
  if (v == 0) return 0.0;
  if (v >= 1) return v / 10.0 + 1.0;
  return v / 10.0 - 1.0;
}

double eventInternalToExternal(double? v) {
  if (v == null) return 0;
  if (v >= -1.0 && v <= 1.0) return 0;
  if (v < -1.0) return -((v.abs() * 10).round() - 10).toDouble();
  return ((v * 10).round() - 10).toDouble();
}

const List<String> kDefaultEtypes = ['Air', 'Drum', 'Damper', 'Burner', '--'];

/// Thời lượng các giai đoạn rang.
class PhaseInfo {
  double? drying; // CHARGE -> DRY END
  double? maillard; // DRY END -> FC START
  double? development; // FC START -> DROP
  double? total; // CHARGE -> DROP (hoặc hiện tại)

  double? pct(double? phase) {
    if (phase == null || total == null || total! <= 0) return null;
    return phase / total! * 100.0;
  }
}

/// Một mẻ rang – tương ứng một file .alog của Artisan.
class RoastProfile {
  RoastProfile({this.samplingInterval = 2.0})
      : roastDate = DateTime.now(),
        roastUUID = _newUuid();

  List<double> timex = [];
  List<double> et = []; // temp1 trong Artisan
  List<double> bt = []; // temp2 trong Artisan
  List<double> ct = []; // thiết bị phụ "CT" (nhiệt độ buồng đốt)
  bool hasCT = false;
  String ctName = 'CT';

  List<int> timeindex = [-1, 0, 0, 0, 0, 0, 0, 0];
  int? tpIndex; // TP đánh dấu tay (hoặc từ file)

  List<SpecialEvent> events = [];
  List<String> etypes = List<String>.from(kDefaultEtypes);

  String title = '';
  String beans = '';
  String roastingNotes = '';
  String cuppingNotes = '';
  double weightIn = 0;
  double weightOut = 0;
  String weightUnit = 'g';
  DateTime roastDate;
  double samplingInterval;
  String roastUUID;
  DateTime? _loadedDate; // ngày giờ đọc từ file (để giữ nguyên chuỗi gốc)
  int? tzOffset; // roasttzoffset (giây, theo quy ước Python: phía tây UTC là dương)

  /// Dữ liệu gốc khi đọc từ file – giữ lại mọi khoá để ghi lại không mất thông tin.
  Map<String, dynamic> original = {};

  int get length => timex.length;
  bool get isEmpty => timex.isEmpty;
  bool get hasCharge => timeindex[EventIdx.charge] >= 0 && timeindex[EventIdx.charge] < timex.length;
  double get chargeTime => hasCharge ? timex[timeindex[EventIdx.charge]] : 0.0;

  // ---------------------------------------------------------------- sự kiện

  int? indexOf(RoastEvent e) => switch (e) {
        RoastEvent.charge => hasCharge ? timeindex[EventIdx.charge] : null,
        RoastEvent.tp => tpIndex,
        RoastEvent.dryEnd => _idx(EventIdx.dryEnd),
        RoastEvent.fcStart => _idx(EventIdx.fcStart),
        RoastEvent.drop => _idx(EventIdx.drop),
      };

  int? _idx(int k) {
    final v = timeindex[k];
    return (v > 0 && v < timex.length) ? v : null;
  }

  void setEvent(RoastEvent e, int? index) {
    switch (e) {
      case RoastEvent.charge:
        timeindex[EventIdx.charge] = index ?? -1;
        break;
      case RoastEvent.tp:
        tpIndex = index;
        break;
      case RoastEvent.dryEnd:
        timeindex[EventIdx.dryEnd] = index ?? 0;
        break;
      case RoastEvent.fcStart:
        timeindex[EventIdx.fcStart] = index ?? 0;
        break;
      case RoastEvent.drop:
        timeindex[EventIdx.drop] = index ?? 0;
        break;
    }
  }

  /// Tìm điểm TP (Turning Point) tự động: BT thấp nhất sau CHARGE,
  /// với điều kiện sau đó BT đã tăng lại rõ ràng.
  int? computeTP() {
    if (!hasCharge) return null;
    final start = timeindex[EventIdx.charge] + 1;
    final end = _idx(EventIdx.dryEnd) ?? _idx(EventIdx.fcStart) ?? _idx(EventIdx.drop) ?? (bt.length - 1);
    int? best;
    double bestV = double.infinity;
    for (var i = start; i <= end && i < bt.length; i++) {
      final v = bt[i];
      if (v < 0) continue;
      if (v < bestV) {
        bestV = v;
        best = i;
      }
    }
    if (best == null) return null;
    // phải có ít nhất 1 giá trị sau TP cao hơn 1.5 độ
    for (var i = best + 1; i <= end && i < bt.length; i++) {
      if (bt[i] >= 0 && bt[i] > bestV + 1.5) return best;
    }
    return null;
  }

  int? get effectiveTP => tpIndex ?? computeTP();

  /// Thời gian (giây) tương đối so với CHARGE.
  double rel(int i) => timex[i] - chargeTime;

  PhaseInfo phases({double? now}) {
    final p = PhaseInfo();
    if (!hasCharge) return p;
    final c = chargeTime;
    final de = indexOf(RoastEvent.dryEnd);
    final fc = indexOf(RoastEvent.fcStart);
    final dr = indexOf(RoastEvent.drop);
    final double end = dr != null ? timex[dr] : (now ?? (timex.isEmpty ? c : timex.last));
    p.total = end - c;
    if (de != null) {
      p.drying = timex[de] - c;
      p.maillard = (fc != null ? timex[fc] : end) - timex[de];
    } else {
      p.drying = end - c;
    }
    if (fc != null) {
      p.development = end - timex[fc];
    }
    return p;
  }

  RoastProfile copy() => RoastProfile.fromMap(toAlogMap());

  // ------------------------------------------------------------- đọc .alog

  static RoastProfile fromAlogString(String text) {
    final obj = PythonLiteral.parse(text);
    if (obj is! Map) {
      throw const FormatException('File .alog không hợp lệ (không phải dict)');
    }
    final m = <String, dynamic>{};
    obj.forEach((k, v) => m[k.toString()] = v);
    if (m['timex'] is! List || m['temp1'] is! List || m['temp2'] is! List) {
      throw const FormatException('File .alog thiếu dữ liệu timex/temp1/temp2');
    }
    return RoastProfile.fromMap(m);
  }

  static List<double> _dl(dynamic v) {
    if (v is! List) return <double>[];
    return v.map<double>((e) {
      if (e is num) {
        final d = e.toDouble();
        return (d.isNaN || d.isInfinite) ? -1.0 : d;
      }
      return -1.0;
    }).toList();
  }

  static List<int> _il(dynamic v) {
    if (v is! List) return <int>[];
    return v.map<int>((e) => e is num ? e.toInt() : 0).toList();
  }

  static List<String> _sl(dynamic v) {
    if (v is! List) return <String>[];
    return v.map<String>((e) => e == null ? '' : e.toString()).toList();
  }

  static double _d(dynamic v, [double def = 0]) => v is num ? v.toDouble() : def;
  static String _s(dynamic v) => v == null ? '' : v.toString();

  static List<double> _fit(List<double> l, int n) {
    if (l.length == n) return l;
    if (l.length > n) return l.sublist(0, n);
    return [...l, ...List<double>.filled(n - l.length, -1.0)];
  }

  /// Lấy mẫu lại chuỗi (srcT, srcV) theo trục thời gian dstT (gần nhất).
  static List<double> _resample(List<double> srcT, List<double> srcV, List<double> dstT) {
    final out = <double>[];
    if (srcT.isEmpty || srcV.isEmpty) {
      return List<double>.filled(dstT.length, -1.0);
    }
    final n = math.min(srcT.length, srcV.length);
    var j = 0;
    for (final t in dstT) {
      while (j + 1 < n && (srcT[j + 1] - t).abs() <= (srcT[j] - t).abs()) {
        j++;
      }
      out.add(srcV[j]);
    }
    return out;
  }

  factory RoastProfile.fromMap(Map<String, dynamic> m) {
    final p = RoastProfile();
    p.original = Map<String, dynamic>.from(m);
    p.timex = _dl(m['timex']);
    final n = p.timex.length;
    p.et = _fit(_dl(m['temp1']), n);
    p.bt = _fit(_dl(m['temp2']), n);

    // CT – tìm thiết bị phụ có tên CT
    final names1 = _sl(m['extraname1']);
    final names2 = _sl(m['extraname2']);
    final extT = m['extratimex'] is List ? m['extratimex'] as List : const [];
    final extV1 = m['extratemp1'] is List ? m['extratemp1'] as List : const [];
    final extV2 = m['extratemp2'] is List ? m['extratemp2'] as List : const [];
    for (var i = 0; i < names1.length || i < names2.length; i++) {
      List<double>? vals;
      if (i < names1.length && names1[i].trim().toUpperCase() == 'CT' && i < extV1.length) {
        vals = _dl(extV1[i]);
      } else if (i < names2.length && names2[i].trim().toUpperCase() == 'CT' && i < extV2.length) {
        vals = _dl(extV2[i]);
      }
      if (vals != null) {
        final t = i < extT.length ? _dl(extT[i]) : <double>[];
        if (t.length == n && vals.length == n) {
          p.ct = vals;
        } else if (t.isNotEmpty) {
          p.ct = _resample(t, vals, p.timex);
        } else {
          p.ct = _fit(vals, n);
        }
        p.hasCT = true;
        break;
      }
    }
    if (!p.hasCT) p.ct = List<double>.filled(n, -1.0);

    // °F -> °C
    if (_s(m['mode']).toUpperCase() == 'F') {
      double f2c(double f) => f == -1.0 ? -1.0 : _round((f - 32.0) * 5.0 / 9.0, 2);
      p.et = p.et.map(f2c).toList();
      p.bt = p.bt.map(f2c).toList();
      p.ct = p.ct.map(f2c).toList();
      // các khoá phụ thuộc đơn vị không còn đúng
      for (final k in ['phases', 'ymax', 'ymin', 'zmax', 'zmin', 'alarmtemperature']) {
        p.original.remove(k);
      }
      p.original['mode'] = 'C';
    }

    final ti = _il(m['timeindex']);
    for (var i = 0; i < 8 && i < ti.length; i++) {
      final v = ti[i];
      if (i == 0) {
        p.timeindex[0] = (v >= 0 && v < n) ? v : -1;
      } else {
        p.timeindex[i] = (v > 0 && v < n) ? v : 0;
      }
    }

    final computed = m['computed'];
    if (computed is Map) {
      final tp = computed['TP_idx'];
      if (tp is num && tp.toInt() > 0 && tp.toInt() < n) {
        p.tpIndex = tp.toInt();
      }
    }

    final se = _il(m['specialevents']);
    final st = _il(m['specialeventstype']);
    final sv = _dl(m['specialeventsvalue']);
    final ss = _sl(m['specialeventsStrings']);
    for (var i = 0; i < se.length && i < st.length && i < sv.length; i++) {
      if (se[i] < 0 || se[i] >= n) continue;
      p.events.add(SpecialEvent(
        index: se[i],
        type: st[i],
        value: eventInternalToExternal(sv[i]),
        label: i < ss.length ? ss[i] : '',
      ));
    }

    final et = _sl(m['etypes']);
    if (et.length >= 4) {
      p.etypes = [...et.take(4), et.length > 4 ? et[4] : '--'];
    }

    p.title = _s(m['title']);
    p.beans = _s(m['beans']);
    p.roastingNotes = _s(m['roastingnotes']);
    p.cuppingNotes = _s(m['cuppingnotes']);
    final w = m['weight'];
    if (w is List && w.length >= 3) {
      p.weightIn = _d(w[0]);
      p.weightOut = _d(w[1]);
      p.weightUnit = _s(w[2]).isEmpty ? 'g' : _s(w[2]);
    }
    p.samplingInterval = _d(m['samplinginterval'], 2.0);
    if (m['roastUUID'] is String && (m['roastUUID'] as String).isNotEmpty) {
      p.roastUUID = m['roastUUID'] as String;
    }
    final tz = m['roasttzoffset'];
    if (tz is num) p.tzOffset = tz.toInt();
    final epoch = m['roastepoch'];
    if (epoch is num) {
      p.roastDate = DateTime.fromMillisecondsSinceEpoch(epoch.toInt() * 1000);
    } else if (m['roastisodate'] is String) {
      final d = DateTime.tryParse('${m['roastisodate']} ${_s(m['roasttime']).isEmpty ? '00:00:00' : _s(m['roasttime'])}') ??
          DateTime.tryParse(m['roastisodate'] as String);
      if (d != null) p.roastDate = d;
    }
    p._loadedDate = p.roastDate;
    return p;
  }

  // ------------------------------------------------------------- ghi .alog

  static double _round(double v, int digits) {
    if (v.isNaN || v.isInfinite) return -1.0;
    final f = math.pow(10, digits).toDouble();
    return (v * f).round() / f;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  Map<String, dynamic> _computed() {
    final c = <String, dynamic>{};
    if (!hasCharge) return c;
    final ci = timeindex[EventIdx.charge];
    final start = timex[ci];
    c['CHARGE_time'] = _round(start, 1);
    c['CHARGE_ET'] = _round(et[ci], 1);
    c['CHARGE_BT'] = _round(bt[ci], 1);
    final tp = effectiveTP;
    if (tp != null) {
      c['TP_idx'] = tp;
      c['TP_time'] = _round(timex[tp] - start, 1);
      c['TP_ET'] = _round(et[tp], 1);
      c['TP_BT'] = _round(bt[tp], 1);
    }
    void put(String name, int? i) {
      if (i == null) return;
      c['${name}_time'] = _round(timex[i] - start, 1);
      c['${name}_ET'] = _round(et[i], 1);
      c['${name}_BT'] = _round(bt[i], 1);
    }

    final drop = indexOf(RoastEvent.drop);
    if (tp != null && drop != null && drop > tp) {
      final ets = et.sublist(tp, drop).where((v) => v >= 0);
      if (ets.isNotEmpty) c['MET'] = _round(ets.reduce(math.max), 1);
    }
    put('DRY', indexOf(RoastEvent.dryEnd));
    put('FCs', indexOf(RoastEvent.fcStart));
    put('FCe', _idx(EventIdx.fcEnd));
    put('SCs', _idx(EventIdx.scStart));
    put('SCe', _idx(EventIdx.scEnd));
    put('DROP', drop);
    put('COOL', _idx(EventIdx.cool));
    if (drop != null) {
      final ph = phases();
      if (ph.total != null) c['totaltime'] = _round(ph.total!, 1);
      if (ph.drying != null) c['dryphasetime'] = _round(ph.drying!, 1);
      if (ph.maillard != null) c['midphasetime'] = _round(ph.maillard!, 1);
      if (ph.development != null) c['finishphasetime'] = _round(ph.development!, 1);
      if (tp != null && drop > tp && timex[drop] - timex[tp] > 0) {
        c['total_ror'] = _round((bt[drop] - bt[tp]) / (timex[drop] - timex[tp]) * 60.0, 1);
      }
    }
    if (weightIn > 0) {
      c['weightin'] = weightIn;
      if (weightOut > 0) {
        c['weightout'] = weightOut;
        c['weight_loss'] = _round((weightIn - weightOut) / weightIn * 100.0, 1);
      }
    }
    return c;
  }

  /// Tạo dict theo đúng khoá và kiểu dữ liệu mà Artisan mong đợi.
  Map<String, dynamic> toAlogMap() {
    final m = <String, dynamic>{...original};
    // Chữ ký/hash gốc của Artisan không còn đúng sau khi sửa – bỏ đi.
    m.remove('hash');
    m.remove('signature');
    final n = timex.length;

    m['mode'] = 'C';
    m['timeindex'] = List<int>.from(timeindex);
    m['title'] = title;
    m['beans'] = beans;
    m['weight'] = <dynamic>[weightIn, weightOut, weightUnit];
    final d = roastDate;
    final keepOriginalDate = _loadedDate != null &&
        _loadedDate == roastDate &&
        original['roastisodate'] is String &&
        original['roasttime'] is String;
    if (!keepOriginalDate) {
      m['roastdate'] = '${_wd[d.weekday - 1]} ${_mo[d.month - 1]} ${d.day} ${d.year}';
      m['roastisodate'] = '${d.year}-${_two(d.month)}-${_two(d.day)}';
      m['roasttime'] = '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
      m['roastepoch'] = d.millisecondsSinceEpoch ~/ 1000;
      m['roasttzoffset'] = tzOffset ?? -d.timeZoneOffset.inSeconds;
    }
    m['roastUUID'] = roastUUID;

    final evs = [...events]..sort((a, b) => a.index.compareTo(b.index));
    m['specialevents'] = evs.map((e) => e.index).toList();
    m['specialeventstype'] = evs.map((e) => e.type).toList();
    m['specialeventsvalue'] = evs.map((e) => eventExternalToInternal(e.value)).toList();
    m['specialeventsStrings'] = evs.map((e) => e.label).toList();
    m['etypes'] = List<String>.from(etypes);
    m['default_etypes'] = List<bool>.generate(5, (i) => i < etypes.length && etypes[i] == kDefaultEtypes[i]);
    m.putIfAbsent('default_etypes_set', () => <int>[0, 0, 0, 0, 0]);

    m['roastingnotes'] = roastingNotes;
    m['cuppingnotes'] = cuppingNotes;
    m['timex'] = timex.map((v) => _round(v, 3)).toList();
    m['temp1'] = et.map((v) => _round(v, 2)).toList();
    m['temp2'] = bt.map((v) => _round(v, 2)).toList();
    m['samplinginterval'] = samplingInterval;

    if (hasCT) {
      _writeCT(m, n);
    }
    m['computed'] = _computed();
    return m;
  }

  void _writeCT(Map<String, dynamic> m, int n) {
    final ctVals = ct.map((v) => _round(v, 2)).toList();
    final tx = timex.map((v) => _round(v, 3)).toList();
    // Nếu file gốc đã có thiết bị CT -> chỉ cập nhật dữ liệu của nó.
    final names1 = _sl(m['extraname1']);
    final names2 = _sl(m['extraname2']);
    for (var i = 0; i < names1.length || i < names2.length; i++) {
      final in1 = i < names1.length && names1[i].trim().toUpperCase() == 'CT';
      final in2 = !in1 && i < names2.length && names2[i].trim().toUpperCase() == 'CT';
      if (!in1 && !in2) continue;
      final extT = List<dynamic>.from(m['extratimex'] as List? ?? []);
      final ext1 = List<dynamic>.from(m['extratemp1'] as List? ?? []);
      final ext2 = List<dynamic>.from(m['extratemp2'] as List? ?? []);
      while (extT.length <= i) {
        extT.add(<double>[]);
      }
      while (ext1.length <= i) {
        ext1.add(<double>[]);
      }
      while (ext2.length <= i) {
        ext2.add(<double>[]);
      }
      final oldT = _dl(extT[i]);
      // Chỉ ghi đè khi độ dài khác (tránh thay đổi dữ liệu Artisan gốc)
      if (oldT.length != n) {
        extT[i] = tx;
        if (in1) {
          ext1[i] = ctVals;
          ext2[i] = List<double>.filled(n, -1.0);
        } else {
          ext2[i] = ctVals;
          ext1[i] = List<double>.filled(n, -1.0);
        }
      }
      m['extratimex'] = extT;
      m['extratemp1'] = ext1;
      m['extratemp2'] = ext2;
      return;
    }
    // Mẻ rang mới: thêm 1 thiết bị phụ "+MODBUS 34" (id 33) với kênh 1 = CT.
    m['extradevices'] = <int>[33];
    m['extraname1'] = <String>[ctName];
    m['extraname2'] = <String>['Extra 2'];
    m['extratimex'] = [tx];
    m['extratemp1'] = [ctVals];
    m['extratemp2'] = [List<double>.filled(n, -1.0)];
    m['extramathexpression1'] = <String>[''];
    m['extramathexpression2'] = <String>[''];
    m['extradevicecolor1'] = <String>['#e07b00'];
    m['extradevicecolor2'] = <String>['#000000'];
    m['extraLCDvisibility1'] = <bool>[true];
    m['extraLCDvisibility2'] = <bool>[false];
    m['extraCurveVisibility1'] = <bool>[true];
    m['extraCurveVisibility2'] = <bool>[false];
    m['extraDelta1'] = <bool>[false];
    m['extraDelta2'] = <bool>[false];
    m['extraFill1'] = <int>[0];
    m['extraFill2'] = <int>[0];
    m['extramarkersizes1'] = <double>[6.0];
    m['extramarkersizes2'] = <double>[6.0];
    m['extramarkers1'] = <String>['None'];
    m['extramarkers2'] = <String>['None'];
    m['extralinewidths1'] = <double>[1.0];
    m['extralinewidths2'] = <double>[1.0];
    m['extralinestyles1'] = <String>['-'];
    m['extralinestyles2'] = <String>['-'];
    m['extradrawstyles1'] = <String>['default'];
    m['extradrawstyles2'] = <String>['default'];
    m['extraNoneTempHint1'] = <bool>[false];
    m['extraNoneTempHint2'] = <bool>[false];
    m['devices'] = <String>['MODBUS', '+MODBUS 34'];
  }

  String toAlogString() => PythonLiteral.write(toAlogMap());

  static String _newUuid() {
    final r = math.Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < 16; i++) {
      var b = r.nextInt(256);
      if (i == 6) b = (b & 0x0f) | 0x40; // version 4
      if (i == 8) b = (b & 0x3f) | 0x80; // variant
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// Định dạng giây thành mm:ss (có dấu âm nếu trước CHARGE).
String fmtTime(double? secs) {
  if (secs == null || secs.isNaN) return '--:--';
  final neg = secs < 0;
  final s = secs.abs().round();
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '${neg ? '-' : ''}$mm:$ss';
}
