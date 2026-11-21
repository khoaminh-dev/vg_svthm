import 'dart:math' as math;
import 'dart:ui';

import 'blob_math.dart';

/// Hình thân là một hồ sơ bán kính r(θ) lấy mẫu đều 64 góc (như Bloub): hai hình bất kỳ có điểm tương ứng
/// từng cặp nên biến hình chỉ là nội suy tuyến tính các bán kính, không cần thư viện morph.
const int kSamples = 64;

final List<double> _cos = List.generate(kSamples, (i) => math.cos(i / kSamples * tau));
final List<double> _sin = List.generate(kSamples, (i) => math.sin(i / kSamples * tau));

List<double> circleProfile([double r = 1]) => List<double>.filled(kSamples, r);

// Hồ sơ đo trên video gốc của Bloub (MIT, jeremy-prt/bloub): trứng, lục giác, tam giác bo góc.
const List<double> _egg = [0.8369,0.8424,0.8497,0.8585,0.8674,0.8775,0.8878,0.8983,0.9089,0.9185,0.9288,0.9374,0.9445,0.9504,0.9543,0.9559,0.9555,0.9519,0.9466,0.9389,0.9302,0.9193,0.9085,0.8969,0.8852,0.8734,0.8625,0.8513,0.8411,0.8325,0.8243,0.8179,0.8137,0.8112,0.8102,0.8128,0.8178,0.8262,0.8374,0.8518,0.8702,0.8922,0.9169,0.9446,0.9741,1.0023,1.0267,1.0433,1.0481,1.0393,1.0216,0.9970,0.9697,0.9418,0.9169,0.8949,0.8760,0.8604,0.8490,0.8394,0.8337,0.8314,0.8305,0.8326];
const List<double> _hexagon = [0.9210,0.9282,0.9441,0.9706,0.9984,1.0059,0.9896,0.9562,0.9290,0.9124,0.9047,0.9058,0.9157,0.9349,0.9642,0.9873,0.9882,0.9665,0.9336,0.9105,0.8968,0.8918,0.8955,0.9080,0.9293,0.9611,0.9820,0.9812,0.9590,0.9282,0.9089,0.8978,0.8964,0.9026,0.9189,0.9439,0.9778,0.9990,0.9964,0.9713,0.9439,0.9274,0.9196,0.9206,0.9308,0.9502,0.9799,1.0121,1.0226,1.0071,0.9752,0.9510,0.9366,0.9316,0.9351,0.9485,0.9711,1.0026,1.0213,1.0155,0.9863,0.9547,0.9347,0.9232];
const List<double> _triangle = [0.7819,0.8211,0.8747,0.9440,1.0223,1.0960,1.1401,1.1340,1.0808,1.0047,0.9265,0.8603,0.8104,0.7730,0.7450,0.7273,0.7151,0.7118,0.7148,0.7245,0.7427,0.7680,0.8037,0.8518,0.9148,0.9876,1.0583,1.1073,1.1109,1.0667,0.9940,0.9164,0.8482,0.7948,0.7555,0.7261,0.7056,0.6925,0.6859,0.6869,0.6938,0.7084,0.7305,0.7615,0.8040,0.8595,0.9311,1.0092,1.0791,1.1171,1.1054,1.0501,0.9779,0.9050,0.8450,0.7990,0.7656,0.7413,0.7258,0.7160,0.7146,0.7204,0.7330,0.7528];

/// Các hình mà Vy "đổi dạng" qua khi đang nghĩ: tròn → trứng → lục giác → tam giác → tròn.
final List<List<double>> kMorphCycle = [circleProfile(), _egg, _hexagon, _triangle];

/// Nhân các nhiễu hài hoà lên hồ sơ nền rồi chuẩn hoá để bán kính trung bình giữ nguyên (thân không to lên khi méo).
void applyWobble(List<double> out, List<double> base, List<({int k, double amp, double phase})> harmonics) {
  var sum = 0.0;
  for (var i = 0; i < kSamples; i++) {
    final a = i / kSamples * tau;
    var r = base[i];
    for (final h in harmonics) {
      r += h.amp * math.cos(h.k * a + h.phase);
    }
    out[i] = r;
    sum += r;
  }
  final k = kSamples / sum;
  for (var i = 0; i < kSamples; i++) {
    out[i] *= k;
  }
}

/// Nội suy hai hồ sơ.
void blendProfiles(List<double> out, List<double> a, List<double> b, double t) {
  for (var i = 0; i < kSamples; i++) {
    out[i] = a[i] + (b[i] - a[i]) * t;
  }
}

/// Bán kính theo hướng bất kỳ (nội suy hai mẫu kề): đặt mắt khớp mép thân khi thân không còn tròn.
double radiusAtAngle(List<double> radii, double angle) {
  final t = (((angle / tau) % 1) + 1) % 1 * kSamples;
  final i = t.floor();
  return lerpD(radii[i % kSamples], radii[(i + 1) % kSamples], t - i);
}

/// Hồ sơ → các điểm màn hình (đã nhân tỉ lệ, xoay, giãn, dịch).
List<Offset> toPoints(List<double> radii, double scale, {double rot = 0, double sx = 1, double sy = 1, double cx = 0, double cy = 0}) {
  final cr = math.cos(rot);
  final sr = math.sin(rot);
  return List.generate(kSamples, (i) {
    final x = radii[i] * _cos[i];
    final y = radii[i] * _sin[i];
    final rx = x * cr - y * sr;
    final ry = x * sr + y * cr;
    return Offset((rx * sx + cx) * scale, (ry * sy + cy) * scale);
  }, growable: false);
}

/// Đường cong kín Catmull-Rom → Bézier bậc ba (như `closedPath` của Bloub).
Path closedPath(List<Offset> pts, {double tension = 1 / 6}) {
  final n = pts.length;
  final path = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = pts[(i - 1 + n) % n];
    final p1 = pts[i];
    final p2 = pts[(i + 1) % n];
    final p3 = pts[(i + 2) % n];
    path.cubicTo(
      p1.dx + (p2.dx - p0.dx) * tension,
      p1.dy + (p2.dy - p0.dy) * tension,
      p2.dx - (p3.dx - p1.dx) * tension,
      p2.dy - (p3.dy - p1.dy) * tension,
      p2.dx,
      p2.dy,
    );
  }
  return path..close();
}
