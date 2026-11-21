import 'dart:math' as math;

import 'blob_math.dart';

/// Đôi mắt vẽ trên một mặt cầu (như Bloub): mỗi mắt nhận hệ trục tiếp tuyến của mặt cầu, chiếu trực giao,
/// nên mắt gần mép tự bị ép lại và nghiêng, tạo cảm giác khối.
const double kEyeSplit = 15.46; // nửa khoảng cách hai mắt trên cầu, độ
const double kEyeW = 0.186; // theo đơn vị bán kính thân
const double kEyeH = 0.412;

class HeadGaze {
  const HeadGaze(this.yaw, this.pitch, this.roll);
  final double yaw; // độ, dương = nhìn phải
  final double pitch; // độ, dương = nhìn lên
  final double roll; // độ, nghiêng đầu

  static const rest = HeadGaze(28.49, 28.62, -13);

  static HeadGaze lerp(HeadGaze a, HeadGaze b, double t) =>
      HeadGaze(lerpD(a.yaw, b.yaw, t), lerpD(a.pitch, b.pitch, t), lerpD(a.roll, b.roll, t));
}

class EyePose {
  const EyePose(this.x, this.y, this.a, this.b, this.c, this.d, this.depth);
  final double x, y; // vị trí tâm (đơn vị bán kính)
  final double a, b, c, d; // ma trận tiếp tuyến 2x2
  final double depth; // > 0: mặt hướng về người xem
}

typedef _V3 = List<double>;

double _deg(double d) => d * math.pi / 180;

(_V3, _V3) _spin(_V3 u, _V3 v, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return (
    [u[0] * c + v[0] * s, u[1] * c + v[1] * s, u[2] * c + v[2] * s],
    [v[0] * c - u[0] * s, v[1] * c - u[1] * s, v[2] * c - u[2] * s],
  );
}

/// Chỉ số 0 là mắt trong, 1 là mắt ngoài. Toạ độ màn hình: x phải, y xuống, z về phía người xem.
List<EyePose> eyePoses(HeadGaze gaze, {double split = kEyeSplit}) {
  _V3 f = [0, 0, 1];
  _V3 right = [1, 0, 0];
  _V3 down = [0, 1, 0];
  (f, right) = _spin(f, right, _deg(gaze.yaw));
  (down, f) = _spin(down, f, _deg(gaze.pitch));
  (right, down) = _spin(right, down, _deg(gaze.roll));
  EyePose build(double side) {
    final (ef, er) = _spin(f, right, _deg(split * side));
    return EyePose(ef[0], ef[1], er[0], er[1], down[0], down[1], ef[2]);
  }
  return [build(-1), build(1)];
}

/// Vòng chớp mắt có lịch cố định (giả ngẫu nhiên có hạt giống): hàm thuần của thời gian.
final List<double> _blinks = () {
  var a = 0x5eed;
  double rnd() {
    a = (a + 0x6d2b79f5) & 0xFFFFFFFF;
    var t = ((a ^ (a >> 15)) * (1 | a)) & 0xFFFFFFFF;
    t = ((t + (((t ^ (t >> 7)) * (61 | t)) & 0xFFFFFFFF)) ^ t) & 0xFFFFFFFF;
    return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296;
  }
  final out = <double>[];
  var t = 1.4;
  while (t < 900) {
    out.add(t);
    t += 1.9 + rnd() * 2.7;
    if (rnd() < 0.18) {
      out.add(t);
      t += 0.24;
    }
  }
  return out;
}();

const double _blinkDur = 0.18;

/// 1 = mở, 0 = nhắm.
double blinkLid(double t) {
  for (final start in _blinks) {
    if (t < start) break;
    final k = (t - start) / _blinkDur;
    if (k >= 0 && k <= 1) return k < 0.45 ? 1 - k / 0.45 : (k - 0.45) / 0.55;
  }
  return 1;
}

/// Chớp là ép dọc theo màn hình quanh tâm mắt.
double blinkScale(double lid) => 0.06 + 0.94 * clamp01(lid);

class Liveliness {
  const Liveliness(this.dYaw, this.dPitch, this.dRoll, this.driftX, this.driftY);
  final double dYaw, dPitch, dRoll, driftX, driftY;
}

/// Mắt trôi nhẹ khi rảnh: chu kỳ nguyên tố nên không bao giờ lặp lại bằng mắt.
Liveliness liveliness(double t, {double wander = 1}) => Liveliness(
  (loopNoise(t, 11.3, 0.4) * 5.5 + loopNoise(t, 3.7, 2.1) * 1.6) * wander,
  (loopNoise(t, 9.1, 1.3) * 4.2 + loopNoise(t, 4.3, 0.7) * 1.3) * wander,
  loopNoise(t, 13.7, 3.2) * 2.2 * wander,
  loopNoise(t, 7.9, 1.9) * 0.006,
  loopNoise(t, 5.3, 0.3) * 0.007,
);
