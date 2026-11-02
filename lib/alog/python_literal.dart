// Đọc / ghi cú pháp "Python literal" – định dạng mà Artisan dùng cho file .alog.
//
// Artisan ghi file bằng `repr(dict)` và đọc lại bằng `ast.literal_eval(...)`.
// Bộ đọc ở đây hỗ trợ: dict, list, tuple, chuỗi (', ", ''' , """ và tiền tố
// u/r/b), số nguyên, số thực, True/False/None.
// Bộ ghi tạo ra văn bản giống hệt `repr()` của Python để Artisan đọc được.

class PythonLiteral {
  PythonLiteral._();

  /// Phân tích văn bản Python literal thành đối tượng Dart
  /// (Map, List, String, int, double, bool, null).
  static dynamic parse(String source) {
    var s = source;
    if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
      s = s.substring(1); // bỏ BOM
    }
    final p = _Parser(s);
    p.skipWs();
    final v = p.value();
    p.skipWs();
    if (p.pos < s.length) {
      throw FormatException('Dữ liệu thừa sau giá trị cuối', s, p.pos);
    }
    return v;
  }

  /// Ghi đối tượng Dart thành văn bản giống `repr()` của Python.
  static String write(dynamic value) {
    final sb = StringBuffer();
    _write(sb, value);
    return sb.toString();
  }

  static void _write(StringBuffer sb, dynamic v) {
    if (v == null) {
      sb.write('None');
    } else if (v is bool) {
      sb.write(v ? 'True' : 'False');
    } else if (v is int) {
      sb.write(v.toString());
    } else if (v is double) {
      sb.write(formatFloat(v));
    } else if (v is String) {
      sb.write(quote(v));
    } else if (v is Map) {
      sb.write('{');
      var first = true;
      v.forEach((key, val) {
        if (!first) sb.write(', ');
        first = false;
        _write(sb, key);
        sb.write(': ');
        _write(sb, val);
      });
      sb.write('}');
    } else if (v is Iterable) {
      sb.write('[');
      var first = true;
      for (final e in v) {
        if (!first) sb.write(', ');
        first = false;
        _write(sb, e);
      }
      sb.write(']');
    } else {
      sb.write(quote(v.toString()));
    }
  }

  /// Định dạng số thực giống Python (luôn có phần thập phân: 200.0, 1.5).
  static String formatFloat(double v) {
    if (v.isNaN || v.isInfinite) {
      return '-1.0'; // Python literal_eval không đọc được nan/inf
    }
    if (v == v.truncateToDouble() && v.abs() < 1e15) {
      return '${v.toInt()}.0';
    }
    final s = v.toString();
    // Dart có thể in "1e-7" – Python vẫn đọc được.
    return s;
  }

  /// Đặt chuỗi trong dấu nháy và escape giống `repr()` của Python.
  static String quote(String s) {
    final useDouble = s.contains("'") && !s.contains('"');
    final q = useDouble ? '"' : "'";
    final sb = StringBuffer(q);
    for (final rune in s.runes) {
      if (rune == 0x5C) {
        sb.write(r'\\');
      } else if (!useDouble && rune == 0x27) {
        sb.write(r"\'");
      } else if (rune == 0x0A) {
        sb.write(r'\n');
      } else if (rune == 0x0D) {
        sb.write(r'\r');
      } else if (rune == 0x09) {
        sb.write(r'\t');
      } else if (rune < 0x20 || rune == 0x7F) {
        sb.write('\\x${rune.toRadixString(16).padLeft(2, '0')}');
      } else {
        sb.writeCharCode(rune);
      }
    }
    sb.write(q);
    return sb.toString();
  }
}

class _Parser {
  _Parser(this.src);

  final String src;
  int pos = 0;

  FormatException _err(String msg) => FormatException(msg, src, pos);

  bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;

  void skipWs() {
    while (pos < src.length) {
      final c = src.codeUnitAt(pos);
      if (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C) {
        pos++;
      } else if (c == 0x23) {
        // chú thích '#'
        while (pos < src.length && src.codeUnitAt(pos) != 0x0A) {
          pos++;
        }
      } else if (c == 0x5C &&
          pos + 1 < src.length &&
          (src.codeUnitAt(pos + 1) == 0x0A || src.codeUnitAt(pos + 1) == 0x0D)) {
        pos += 2; // nối dòng
      } else {
        break;
      }
    }
  }

  dynamic value() {
    skipWs();
    if (pos >= src.length) throw _err('Hết dữ liệu bất ngờ');
    final c = src.codeUnitAt(pos);
    if (c == 0x7B) return _dict(); // {
    if (c == 0x5B) return _list(); // [
    if (c == 0x28) return _tuple(); // (
    if (c == 0x27 || c == 0x22) return _strings(); // ' "
    if (c == 0x2D || c == 0x2B || c == 0x2E || _isDigit(c)) return _number();
    if (_isIdentStart(c)) {
      final start = pos;
      while (pos < src.length) {
        final d = src.codeUnitAt(pos);
        if (_isIdentStart(d) || _isDigit(d)) {
          pos++;
        } else {
          break;
        }
      }
      final word = src.substring(start, pos);
      // tiền tố chuỗi u'..', r'..', b'..', ur'..', rb'..'
      if (pos < src.length &&
          (src.codeUnitAt(pos) == 0x27 || src.codeUnitAt(pos) == 0x22) &&
          word.length <= 2 &&
          RegExp(r'^[uUrRbBfF]+$').hasMatch(word)) {
        pos = start;
        return _strings();
      }
      switch (word) {
        case 'True':
          return true;
        case 'False':
          return false;
        case 'None':
          return null;
        case 'nan':
          return double.nan;
        case 'inf':
          return double.infinity;
      }
      throw _err('Từ khoá không hợp lệ: $word');
    }
    throw _err('Ký tự không mong đợi: ${src[pos]}');
  }

  Map<dynamic, dynamic> _dict() {
    pos++; // {
    final m = <dynamic, dynamic>{};
    skipWs();
    if (pos < src.length && src.codeUnitAt(pos) == 0x7D) {
      pos++;
      return m;
    }
    while (true) {
      final k = value();
      skipWs();
      if (pos >= src.length || src.codeUnitAt(pos) != 0x3A) {
        throw _err("Thiếu ':' trong dict");
      }
      pos++; // :
      final v = value();
      m[k] = v;
      skipWs();
      if (pos >= src.length) throw _err("Thiếu '}'");
      final c = src.codeUnitAt(pos);
      if (c == 0x2C) {
        pos++;
        skipWs();
        if (pos < src.length && src.codeUnitAt(pos) == 0x7D) {
          pos++;
          return m;
        }
        continue;
      }
      if (c == 0x7D) {
        pos++;
        return m;
      }
      throw _err("Thiếu ',' hoặc '}'");
    }
  }

  List<dynamic> _list() {
    pos++; // [
    final l = <dynamic>[];
    skipWs();
    if (pos < src.length && src.codeUnitAt(pos) == 0x5D) {
      pos++;
      return l;
    }
    while (true) {
      l.add(value());
      skipWs();
      if (pos >= src.length) throw _err("Thiếu ']'");
      final c = src.codeUnitAt(pos);
      if (c == 0x2C) {
        pos++;
        skipWs();
        if (pos < src.length && src.codeUnitAt(pos) == 0x5D) {
          pos++;
          return l;
        }
        continue;
      }
      if (c == 0x5D) {
        pos++;
        return l;
      }
      throw _err("Thiếu ',' hoặc ']'");
    }
  }

  dynamic _tuple() {
    pos++; // (
    final l = <dynamic>[];
    skipWs();
    if (pos < src.length && src.codeUnitAt(pos) == 0x29) {
      pos++;
      return l;
    }
    var sawComma = false;
    while (true) {
      l.add(value());
      skipWs();
      if (pos >= src.length) throw _err("Thiếu ')'");
      final c = src.codeUnitAt(pos);
      if (c == 0x2C) {
        sawComma = true;
        pos++;
        skipWs();
        if (pos < src.length && src.codeUnitAt(pos) == 0x29) {
          pos++;
          return l;
        }
        continue;
      }
      if (c == 0x29) {
        pos++;
        // (x) không phải tuple, chỉ là x trong ngoặc
        if (!sawComma && l.length == 1) return l.first;
        return l;
      }
      throw _err("Thiếu ',' hoặc ')'");
    }
  }

  dynamic _number() {
    final start = pos;
    if (src.codeUnitAt(pos) == 0x2D || src.codeUnitAt(pos) == 0x2B) {
      pos++;
      skipWs();
      // -inf / -nan
      if (pos < src.length && _isIdentStart(src.codeUnitAt(pos))) {
        final neg = src.codeUnitAt(start) == 0x2D;
        final v = value();
        if (v is num) return neg ? -v : v;
        throw _err('Số không hợp lệ');
      }
    }
    final numStart = pos;
    var isFloat = false;
    // tiền tố hex/oct/bin
    if (pos + 1 < src.length &&
        src.codeUnitAt(pos) == 0x30 &&
        'xXoObB'.contains(src[pos + 1])) {
      final kind = src[pos + 1].toLowerCase();
      pos += 2;
      final ds = pos;
      while (pos < src.length &&
          RegExp(r'[0-9a-fA-F_]').hasMatch(src[pos])) {
        pos++;
      }
      final digits = src.substring(ds, pos).replaceAll('_', '');
      final radix = kind == 'x' ? 16 : (kind == 'o' ? 8 : 2);
      final v = int.parse(digits, radix: radix);
      return src.codeUnitAt(start) == 0x2D ? -v : v;
    }
    while (pos < src.length) {
      final c = src.codeUnitAt(pos);
      if (_isDigit(c) || c == 0x5F) {
        pos++;
      } else if (c == 0x2E) {
        isFloat = true;
        pos++;
      } else if (c == 0x65 || c == 0x45) {
        // e / E
        isFloat = true;
        pos++;
        if (pos < src.length &&
            (src.codeUnitAt(pos) == 0x2B || src.codeUnitAt(pos) == 0x2D)) {
          pos++;
        }
      } else {
        break;
      }
    }
    var text = src.substring(numStart, pos).replaceAll('_', '');
    if (text.isEmpty) throw _err('Số không hợp lệ');
    final negative = src.codeUnitAt(start) == 0x2D;
    if (isFloat) {
      if (text.startsWith('.')) text = '0$text';
      if (text.endsWith('.')) text = '${text}0';
      text = text.replaceAll('.e', '.0e').replaceAll('.E', '.0E');
      final v = double.parse(text);
      return negative ? -v : v;
    }
    final v = int.parse(text);
    return negative ? -v : v;
  }

  /// Đọc một hoặc nhiều chuỗi liền nhau ('a' 'b' -> 'ab').
  String _strings() {
    final sb = StringBuffer(_string());
    while (true) {
      final save = pos;
      skipWs();
      if (pos < src.length) {
        final c = src.codeUnitAt(pos);
        if (c == 0x27 || c == 0x22) {
          sb.write(_string());
          continue;
        }
      }
      pos = save;
      return sb.toString();
    }
  }

  String _string() {
    var raw = false;
    while (pos < src.length && 'uUrRbBfF'.contains(src[pos])) {
      if (src[pos] == 'r' || src[pos] == 'R') raw = true;
      pos++;
    }
    if (pos >= src.length) throw _err('Chuỗi không hợp lệ');
    final q = src[pos];
    final triple = src.startsWith(q * 3, pos);
    pos += triple ? 3 : 1;
    final sb = StringBuffer();
    while (true) {
      if (pos >= src.length) throw _err('Chuỗi chưa đóng');
      final ch = src[pos];
      if (triple) {
        if (src.startsWith(q * 3, pos)) {
          pos += 3;
          break;
        }
      } else if (ch == q) {
        pos++;
        break;
      }
      if (ch == '\\' && !raw) {
        pos++;
        if (pos >= src.length) throw _err('Chuỗi chưa đóng');
        final e = src[pos];
        pos++;
        switch (e) {
          case '\\':
            sb.write('\\');
            break;
          case "'":
            sb.write("'");
            break;
          case '"':
            sb.write('"');
            break;
          case 'n':
            sb.write('\n');
            break;
          case 'r':
            sb.write('\r');
            break;
          case 't':
            sb.write('\t');
            break;
          case 'a':
            sb.writeCharCode(7);
            break;
          case 'b':
            sb.writeCharCode(8);
            break;
          case 'f':
            sb.writeCharCode(12);
            break;
          case 'v':
            sb.writeCharCode(11);
            break;
          case '\n':
            break; // nối dòng trong chuỗi
          case '\r':
            if (pos < src.length && src[pos] == '\n') pos++;
            break;
          case 'x':
            sb.writeCharCode(_hex(2));
            break;
          case 'u':
            sb.writeCharCode(_hex(4));
            break;
          case 'U':
            sb.writeCharCode(_hex(8));
            break;
          default:
            if (RegExp(r'[0-7]').hasMatch(e)) {
              var oct = e;
              while (oct.length < 3 &&
                  pos < src.length &&
                  RegExp(r'[0-7]').hasMatch(src[pos])) {
                oct += src[pos];
                pos++;
              }
              sb.writeCharCode(int.parse(oct, radix: 8));
            } else {
              sb.write('\\');
              sb.write(e);
            }
        }
      } else {
        sb.write(ch);
        pos++;
      }
    }
    return sb.toString();
  }

  int _hex(int n) {
    if (pos + n > src.length) throw _err('Mã escape không đủ ký tự');
    final h = src.substring(pos, pos + n);
    pos += n;
    final v = int.tryParse(h, radix: 16);
    if (v == null) throw _err('Mã escape không hợp lệ: $h');
    return v;
  }
}
