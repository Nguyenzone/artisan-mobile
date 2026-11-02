/// Bộ điều khiển PID phần mềm – chuyển từ artisanlib/pid.py của Artisan
/// (P theo sai số có trọng số beta, I chống bão hoà + back-calculation,
/// D theo phép đo có trọng số gamma, giới hạn D, chống "giật" D, duty steps).
class Pid {
  Pid({this.kp = 15.0, this.ki = 0.01, this.kd = 20.0});

  double kp;
  double ki;
  double kd;
  double beta = 1.0; // trọng số điểm đặt cho P (1 = PoE)
  double gamma = 1.0; // trọng số điểm đặt cho D (1 = DoE)

  int outMin = 0;
  int outMax = 100;
  int dutyMin = 0;
  int dutyMax = 100;
  int dutySteps = 1;
  final int forceDuty = 3;

  double derivativeLimit = 500.0;
  bool integralWindupPrevention = true;
  double integralLimitFactor = 1.0;
  final double backCalculationFactor = 0.5;
  final double significantSetpointChangeLimit = 15;

  double pTerm = 0, iTerm = 0, dTerm = 0;
  double? _lastError;
  double? _lastInput;
  double? lastOutput;
  double? _lastTime;
  double target = 0;
  double _lastTarget = 0;
  bool active = false;
  int _iterationsSinceDuty = 0;
  bool _setpointChangedSignificantly = false;
  bool _integralJustReset = true;
  final List<double> _history = [];

  /// Gọi khi có giá trị đầu ra mới (0..100 %).
  void Function(double duty)? control;

  void on() {
    lastOutput = null; // lần cập nhật tới chắc chắn gửi lệnh
    active = true;
  }

  void off() => active = false;

  void reset() {
    _lastError = 0;
    _lastInput = null;
    _lastTime = null;
    pTerm = 0;
    iTerm = 0;
    lastOutput = null;
    _lastTarget = target;
    _history.clear();
    _setpointChangedSignificantly = false;
    _integralJustReset = false;
  }

  void setTarget(double sv, {bool init = false}) {
    target = sv;
    if (init) reset();
  }

  (double, double) _integralLimits() {
    final range = (outMax - outMin) * integralLimitFactor;
    if (outMin >= 0) return (0, range);
    if (outMax <= 0) return (-range, 0);
    return (-range / 2, range / 2);
  }

  double _applyIntegralLimits(double it) {
    final (lo, hiBase) = _integralLimits();
    final hi = hiBase + kp * (1 - beta) * target;
    return it < lo ? lo : (it > hi ? hi : it);
  }

  bool _discontinuity(double x) {
    if (_history.length < 2) return false;
    final changes = <double>[];
    for (var i = 1; i < _history.length && i < 4; i++) {
      changes.add((_history[_history.length - i] - _history[_history.length - i - 1]).abs());
    }
    if (changes.isEmpty) return false;
    final avg = changes.reduce((a, b) => a + b) / changes.length;
    final cur = (x - _history.last).abs();
    return cur > 2.5 * avg && cur > 1.0;
  }

  double _derivative(double x, double dt) {
    if (_lastInput == null) return 0;
    final error = gamma * target - x;
    final lastErr = gamma * _lastTarget - _lastInput!;
    var d = (error - lastErr) / dt;
    if (d.abs() > derivativeLimit) d = d > 0 ? derivativeLimit : -derivativeLimit;
    if (_setpointChangedSignificantly) d *= 1 - gamma.clamp(0.0, 1.0) / 2;
    if (_discontinuity(x)) d *= 0.3;
    return kd * d;
  }

  /// Cập nhật với giá trị đo [x] (BT) tại thời điểm [now] (giây).
  void update(double? x, double now) {
    if (x != null && !active) target = x; // khi tắt: SV bám theo PV
    if (x == null || x < 0) return;
    final err = target - x;
    if (_lastError == null || _lastTime == null) {
      _lastTime = now;
      _lastError = err;
      _lastInput = x;
      return;
    }
    final dt = now - _lastTime!;
    if (dt < 0.05) return;
    final spChange = target - _lastTarget;
    _setpointChangedSignificantly = spChange.abs() > 0.001 && spChange.abs() > significantSetpointChangeLimit;
    pTerm = kp * (beta * target - x);
    final before = pTerm + iTerm;
    final shouldIntegrate = !integralWindupPrevention ||
        (!_integralJustReset && !(before > outMax && err > 0) && !(before < outMin && err < 0));
    if (shouldIntegrate) {
      iTerm = _applyIntegralLimits(iTerm + ki * err * dt);
    }
    _integralJustReset = false;
    dTerm = _derivative(x, dt);
    _history.add(x);
    if (_history.length > 5) _history.removeAt(0);
    _lastTime = now;
    _lastError = err;
    _lastInput = x;
    _lastTarget = target;

    var output = pTerm + iTerm + dTerm;
    final beforeClamp = output;
    if (output > outMax) output = outMax.toDouble();
    if (output < outMin) output = outMin.toDouble();
    if (integralWindupPrevention && (beforeClamp - output).abs() > 0.001 && ki != 0) {
      iTerm = _applyIntegralLimits(iTerm - (beforeClamp - output) * backCalculationFactor);
    }
    final finalOut = output.clamp(dutyMin.toDouble(), dutyMax.toDouble()).toDouble();
    var fire = false;
    if (lastOutput == null ||
        _iterationsSinceDuty >= forceDuty ||
        finalOut >= lastOutput! + dutySteps ||
        finalOut <= lastOutput! - dutySteps) {
      fire = active;
      lastOutput = output;
    }
    _iterationsSinceDuty++;
    if (fire) {
      control?.call(finalOut);
      _iterationsSinceDuty = 0;
    }
  }
}
