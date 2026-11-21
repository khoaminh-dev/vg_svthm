import 'blob_face.dart';
import 'blob_math.dart';

/// Cấu hình một mắt (hình viên thuốc): w/h theo bán kính thân, open 1 = mở, tilt = nghiêng riêng (độ).
class EyeCfg {
  const EyeCfg(this.w, this.h, {this.tilt = 0, this.open = 1});
  final double w, h, tilt, open;

  static EyeCfg lerp(EyeCfg a, EyeCfg b, double t) =>
      EyeCfg(lerpD(a.w, b.w, t), lerpD(a.h, b.h, t), tilt: lerpD(a.tilt, b.tilt, t), open: lerpD(a.open, b.open, t));
}

/// Một biểu cảm = hướng đầu + khoảng cách hai mắt + hình từng mắt (đo từ Bloub, 16 biểu cảm).
class BlobExpression {
  const BlobExpression(this.id, this.gaze, this.split, this.eyes);
  final String id;
  final HeadGaze gaze;
  final double split;
  final (EyeCfg, EyeCfg) eyes;

  static BlobExpression lerp(BlobExpression a, BlobExpression b, double t) => BlobExpression(
    b.id,
    HeadGaze.lerp(a.gaze, b.gaze, t),
    lerpD(a.split, b.split, t),
    (EyeCfg.lerp(a.eyes.$1, b.eyes.$1, t), EyeCfg.lerp(a.eyes.$2, b.eyes.$2, t)),
  );
}

(EyeCfg, EyeCfg) _pair(double w, double h, [double tilt = 0, double open = 1]) =>
    (EyeCfg(w, h, tilt: tilt, open: open), EyeCfg(w, h, tilt: -tilt, open: open));

final Map<String, BlobExpression> kExpressions = {
  for (final e in <BlobExpression>[
    const BlobExpression('neutre', HeadGaze.rest, kEyeSplit, (EyeCfg(kEyeW, kEyeH), EyeCfg(kEyeW, kEyeH))),
    BlobExpression('attentif', const HeadGaze(4, 5, -4), 16, _pair(0.21, 0.44)),
    BlobExpression('surpris', const HeadGaze(3, -3, 0), 19, _pair(0.45, 0.47)),
    BlobExpression('excite', const HeadGaze(6, -14, 0), 19.5, _pair(0.4, 0.56, -10)),
    BlobExpression('heureux', const HeadGaze(5, 9, 0), 17, _pair(0.27, 0.17, 14)),
    BlobExpression('hilare', const HeadGaze(4, 14, 0), 18, _pair(0.34, 0.13, 20)),
    BlobExpression('colere', const HeadGaze(3, 7, 0), 17, _pair(0.34, 0.15, 30)),
    BlobExpression('triste', const HeadGaze(3, -13, 0), 16, _pair(0.22, 0.4, -28)),
    BlobExpression('effraye', const HeadGaze(2, -20, 0), 20.5, _pair(0.4, 0.6)),
    const BlobExpression('mefiant', HeadGaze(12, 6, -6), 16, (EyeCfg(0.21, 0.4), EyeCfg(0.22, 0.15))),
    const BlobExpression('confus', HeadGaze(-14, 3, 8), 16.5, (EyeCfg(0.2, 0.44, tilt: -18), EyeCfg(0.28, 0.17, tilt: 14))),
    const BlobExpression('curieux', HeadGaze(16, -9, -15), 16.5, (EyeCfg(0.24, 0.46, tilt: -8), EyeCfg(0.2, 0.38, tilt: -8))),
    BlobExpression('fier', const HeadGaze(5, 17, 0), 17, _pair(0.3, 0.15, 18)),
    BlobExpression('timide', const HeadGaze(-19, -14, -7), 14, _pair(0.17, 0.3)),
    BlobExpression('blase', const HeadGaze(-22, 2, 0), 16, _pair(0.3, 0.12)),
    BlobExpression('somnolent', const HeadGaze(6, -9, -3), 16, _pair(0.2, 0.42, 0, 0.42)),
  ])
    e.id: e,
};
