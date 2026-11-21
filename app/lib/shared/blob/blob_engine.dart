import 'dart:math' as math;
import 'dart:ui';

import 'blob_expressions.dart';
import 'blob_face.dart';
import 'blob_math.dart';
import 'blob_shape.dart';
import 'blob_types.dart';

class BlobEye {
  const BlobEye(this.w, this.h, this.m, this.alpha);
  final double w, h; // px
  final List<double> m; // a, b, c, d, e, f (kiểu matrix SVG)
  final double alpha;
}

/// Một khung vẽ do engine tính ra. Mọi toạ độ tính theo px, tâm ở (0,0).
class BlobFrame {
  const BlobFrame({
    required this.points,
    required this.palette,
    required this.awake,
    required this.eyes,
    required this.cloudT,
    required this.cloudSpeed,
    required this.glow,
    required this.ringT,
    required this.ringAlpha,
    required this.bang,
    required this.bodyR,
  });

  final List<Offset> points;
  final BlobPalette palette;
  final double awake; // 0 ngủ .. 1 thức
  final List<BlobEye> eyes;
  final double cloudT; // pha khói (rad)
  final double cloudSpeed;
  final double glow; // 0..1 độ sáng bóng dưới
  final double ringT; // 0..1 tiến độ vòng sáng nhấn
  final double ringAlpha;
  final double bang; // 0..1 độ hiện dấu "!"
  final double bodyR;
}

/// Bộ máy chuyển động của Vy-Bloub. Giữ trạng thái làm mượt (không phụ thuộc khung hình), mỗi khung gọi [step] rồi [frame].
class BlobEngine {
  BlobEngine({this.seed = 0});

  final double seed;

  double _t = 0;
  double _awake = 0;
  double _level = 0; // âm lượng đã làm mượt
  double _kick = 0; // cú nảy khi nhấn mạnh
  double _ringStart = -10;
  int _emphasisSeen = 0;
  double _cloudPhase = 0;
  double _morphPhase = 0;
  double _bangV = 0;

  BlobPalette _pal = BlobPalette.sleeping;
  BlobExpression _from = kExpressions['neutre']!;
  BlobExpression _to = kExpressions['neutre']!;
  double _exprStart = -10;
  String _exprId = 'neutre';

  final List<double> _base = circleProfile();
  final List<double> _radii = circleProfile();

  double get awake => _awake;

  /// Âm lượng tổng hợp theo nhịp lời nói khi không có số đo thật: mô phỏng các âm tiết nhấp nhô.
  double speechEnvelope(double t) {
    final syl = math.sin(t * 9.0 + seed).abs();
    final word = 0.5 + 0.5 * math.sin(t * 2.3 + 1.0);
    final breath = 0.75 + 0.25 * math.sin(t * 0.9);
    return clamp01(syl * (0.45 + 0.55 * word) * breath);
  }

  String _exprFor(OrbMode mode, BlobMood mood) {
    if (mood != BlobMood.calm) {
      return switch (mood) {
        BlobMood.happy => 'heureux',
        BlobMood.excited => 'excite',
        BlobMood.curious => 'curieux',
        BlobMood.worried => 'confus',
        BlobMood.sad => 'triste',
        BlobMood.alert => 'surpris',
        BlobMood.emergency => 'effraye',
        BlobMood.calm => 'neutre',
      };
    }
    return switch (mode) {
      OrbMode.idle => 'neutre',
      OrbMode.listening => 'attentif',
      OrbMode.thinking => 'curieux',
      OrbMode.speaking => 'heureux',
    };
  }

  /// Đẩy thời gian và các đầu vào đã làm mượt.
  /// [level] là âm lượng thật (0..1) khi nghe; khi nói mà null thì dùng nhịp tổng hợp. [emphasis] tăng lên một đơn vị = một lần nhấn.
  void step(
    double dt, {
    required OrbMode mode,
    required bool awake,
    required BlobMood mood,
    double? level,
    int emphasis = 0,
  }) {
    dt = dt.clamp(0.0, 0.1);
    _t += dt;

    _awake += ((awake ? 1.0 : 0.0) - _awake) * smoothK(dt, awake ? 2.6 : 1.6);

    // Âm lượng: lên nhanh, xuống chậm để thân không giật.
    final raw = mode == OrbMode.speaking ? (level ?? speechEnvelope(_t)) : (mode == OrbMode.listening ? (level ?? 0) : 0.0);
    final k = raw > _level ? smoothK(dt, 22) : smoothK(dt, 7);
    _level += (clamp01(raw) - _level) * k;

    if (emphasis != _emphasisSeen) {
      _emphasisSeen = emphasis;
      _ringStart = _t;
      _kick = 1;
    }
    _kick *= math.exp(-dt * 4.5);

    // Màu: ngủ xám; thức thì theo cảm xúc.
    final target = awake ? BlobPalette.of(mood) : BlobPalette.sleeping;
    _pal = BlobPalette.lerp(_pal, target, smoothK(dt, 3.2));

    // Biểu cảm: trượt sang biểu cảm mới trong 0.35s.
    final id = _exprFor(mode, mood);
    if (id != _exprId) {
      final cur = _curExpr();
      _from = cur;
      _to = kExpressions[id]!;
      _exprId = id;
      _exprStart = _t;
    }

    final cloudRate = switch (mode) {
      OrbMode.idle => 0.55,
      OrbMode.listening => 1.0,
      OrbMode.thinking => 2.4,
      OrbMode.speaking => 1.5,
    };
    // Ngủ: khói trôi chậm hơn một chút nhưng vẫn sống.
    _cloudPhase += dt * tau / 4 * lerpD(0.6, cloudRate, _awake);

    // Đang nghĩ: đổi dạng liên tục tròn → trứng → lục giác → tam giác; chu kỳ ~1.1s mỗi hình.
    final morphing = mode == OrbMode.thinking && _awake > 0.5;
    _morphPhase += dt * (morphing ? 0.9 : 0.0);
    if (morphing) {
      final n = kMorphCycle.length;
      final x = _morphPhase % n;
      final i = x.floor();
      blendProfiles(_base, kMorphCycle[i % n], kMorphCycle[(i + 1) % n], easeInOutCubic(x - i));
    } else {
      // Thôi đổi dạng: về tròn mượt.
      final k = smoothK(dt, 5);
      for (var i = 0; i < kSamples; i++) {
        _base[i] += (1 - _base[i]) * k;
      }
    }
    _bangV += ((mood == BlobMood.alert || mood == BlobMood.emergency ? 1.0 : 0.0) - _bangV) * smoothK(dt, 7);
  }

  BlobExpression _curExpr() {
    final p = clamp01((_t - _exprStart) / 0.35);
    return BlobExpression.lerp(_from, _to, easeInOutCubic(p));
  }

  /// Tính khung vẽ cho kích thước [size] (px, hình vuông).
  BlobFrame frame(double size, OrbMode mode, {bool still = false}) {
    final t = still ? 0.0 : _t;
    final r = size / 2 * 0.72; // chừa chỗ cho bóng và vòng sáng
    final lvl = _level;
    final aw = _awake;

    // --- hình thân ---
    // Nhiễu hài hoà: luôn có chút "sống" (ngủ thở nhẹ), nói/nghe thì mạnh theo âm lượng và quay quanh thân như sóng.
    final speaking = mode == OrbMode.speaking;
    final breath = 0.012 + 0.008 * math.sin(t * 1.3);
    final audio = lvl * (speaking ? 0.07 : 0.045);
    final spin = t * (speaking ? 3.1 : 0.9);
    final harmonics = <({int k, double amp, double phase})>[
      (k: 2, amp: breath * 1.6 + audio * 0.5, phase: t * 0.7 + seed),
      (k: 3, amp: breath + audio * 0.9, phase: -spin + 1.1),
      (k: 4, amp: breath * 0.6 + audio * 0.7, phase: spin * 1.3 + 2.0),
      (k: 5, amp: audio * 0.55, phase: -spin * 1.7 + 0.4),
      (k: 6, amp: audio * 0.35, phase: spin * 2.1),
    ];
    applyWobble(_radii, _base, harmonics);

    // Nhịp phồng: nghe phồng theo âm lượng, nói nhún theo nhịp, nhấn thì bật lên.
    final pulse = 1 + (speaking ? 0.055 * lvl : 0.09 * lvl) + 0.07 * _kick + 0.012 * math.sin(t * 2.0) * aw;
    final sleepDrift = 1 - 0.03 * (1 - aw); // ngủ nhỏ hơn một chút
    final body = r * pulse * sleepDrift;

    // Rung theo âm thanh: dịch nhẹ và nghiêng thân.
    final shake = lvl * (speaking ? 0.012 : 0.006) + 0.01 * _kick;
    final cx = math.sin(t * 37 + seed) * shake;
    final cy = math.cos(t * 41 + seed) * shake;
    final life = liveliness(t, wander: aw);
    final pts = toPoints(
      _radii,
      body,
      rot: speaking ? math.sin(t * 5.3) * 0.05 * lvl : 0,
      sx: 1 + 0.03 * lvl * math.sin(t * 9),
      sy: 1 - 0.03 * lvl * math.sin(t * 9),
      cx: cx + life.driftX,
      cy: cy + life.driftY,
    );

    // --- mắt ---
    final eyes = <BlobEye>[];
    final eyeOpen = aw > 0.45 ? easeOutBack(clamp01((aw - 0.45) / 0.45)) : 0.0;
    final eyeAlpha = clamp01(aw * 1.6 - 0.5) * (1 - _bangV);
    if (eyeAlpha > 0.01) {
      final ex = _curExpr();
      final g = HeadGaze(
        ex.gaze.yaw + life.dYaw + 3 * lvl * math.sin(t * 17),
        ex.gaze.pitch + life.dPitch + 2.5 * lvl * math.sin(t * 13),
        ex.gaze.roll + life.dRoll,
      );
      final poses = eyePoses(g, split: ex.split);
      final lid = math.min(blinkLid(t), clamp01(eyeOpen));
      final cfgs = [ex.eyes.$1, ex.eyes.$2];
      for (var i = 0; i < 2; i++) {
        final e = poses[i];
        if (e.depth <= 0.02) continue;
        final cfg = cfgs[i];
        final fit = radiusAtAngle(_radii, math.atan2(e.y, e.x));
        final phi = cfg.tilt * math.pi / 180;
        final cp = math.cos(phi);
        final sp = math.sin(phi);
        final ax = e.a * cp + e.c * sp;
        final ay = e.b * cp + e.d * sp;
        final c2 = -e.a * sp + e.c * cp;
        final d2 = -e.b * sp + e.d * cp;
        final kk = blinkScale(math.min(lid, cfg.open));
        eyes.add(BlobEye(
          cfg.w * body,
          cfg.h * body,
          [ax, ay * kk, c2, d2 * kk, (e.x * fit + cx + life.driftX) * body, (e.y * fit + cy + life.driftY) * body],
          eyeAlpha * clamp01(e.depth / 0.12),
        ));
      }
    }

    // --- vòng sáng nhấn mạnh ---
    final rp = (_t - _ringStart) / 0.9;
    final ringOn = rp >= 0 && rp <= 1;
    return BlobFrame(
      points: pts,
      palette: _pal,
      awake: aw,
      eyes: eyes,
      cloudT: _cloudPhase,
      cloudSpeed: 1,
      glow: clamp01(0.35 + 0.4 * aw + 0.35 * lvl + 0.3 * _kick),
      ringT: ringOn ? easeOutCubic(rp) : 0,
      ringAlpha: ringOn ? 1 - rp : 0,
      bang: _bangV,
      bodyR: body,
    );
  }
}
