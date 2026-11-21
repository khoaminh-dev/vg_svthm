import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'blob_engine.dart';
import 'blob_shape.dart';
import 'blob_types.dart';

/// Vẽ một [BlobFrame]: bóng mềm, thân gradient có khói trôi bên trong, mắt trắng, dấu "!" khi cảnh báo, vòng sáng khi nhấn.
class BlobPainter extends CustomPainter {
  BlobPainter(this.f);

  final BlobFrame f;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final body = f.bodyR;
    final p = f.palette;
    final path = closedPath(f.points);

    // Bóng mềm phía dưới: đậm hơn khi thức.
    canvas.drawPath(
      path.shift(Offset(0, body * 0.2)),
      Paint()
        ..color = p.accent.withValues(alpha: 0.12 + 0.3 * f.glow * (0.4 + 0.6 * f.awake))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, body * 0.34),
    );

    // Vòng sáng nhấn: lan ra rồi mờ.
    if (f.ringAlpha > 0.01) {
      canvas.drawCircle(
        Offset.zero,
        body * (1.0 + 0.55 * f.ringT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = body * (0.07 * (1 - f.ringT) + 0.015)
          ..color = p.accent.withValues(alpha: 0.6 * f.ringAlpha),
      );
    }

    // Thân + khói bên trong (cắt theo đường viền).
    canvas.save();
    canvas.clipPath(path);
    final rect = Rect.fromCircle(center: Offset.zero, radius: body * 1.25);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.top, p.mid, p.low],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    _smoke(canvas, body, p);
    canvas.restore();

    // Viền sáng mảnh phía trên cho cảm giác khối.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, body * 0.02)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.0)],
        ).createShader(rect),
    );

    // Dấu "!" khi cảnh báo.
    if (f.bang > 0.01) _bang(canvas, body);

    // Mắt.
    final eyePaint = Paint();
    for (final e in f.eyes) {
      canvas.save();
      canvas.transform(Matrix4(e.m[0], e.m[1], 0, 0, e.m[2], e.m[3], 0, 0, 0, 0, 1, 0, e.m[4], e.m[5], 0, 1).storage);
      final r = math.min(e.w, e.h) / 2;
      eyePaint.color = Colors.white.withValues(alpha: e.alpha);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: e.w, height: math.max(e.h, 0.5)), Radius.circular(r)), eyePaint);
      canvas.restore();
    }
    canvas.restore();
  }

  void _smoke(Canvas canvas, double body, BlobPalette p) {
    final a = f.cloudT;
    final aw = f.awake;
    void cloud(Offset at, double w, double h, Color col, double blur) {
      canvas.drawOval(
        Rect.fromCenter(center: at, width: w, height: h),
        Paint()
          ..color = col
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    // Khói đậm phía trên, khói sáng bên phải, mây trắng dâng ở dưới. Ngủ: tông xám (bảng màu đã xám); thức: theo màu cảm xúc.
    final deep = Color.lerp(p.top, p.accent, 0.5)!;
    cloud(Offset(-0.25 * body + 0.14 * body * math.cos(a), -0.5 * body + 0.08 * body * math.sin(a)), body * 1.15, body * 0.85, deep.withValues(alpha: 0.9), body * 0.22);
    cloud(Offset(0.5 * body + 0.1 * body * math.sin(a + 1), -0.1 * body + 0.12 * body * math.cos(a + 2)), body * 0.8, body * 0.7, p.mid.withValues(alpha: 0.9), body * 0.2);
    cloud(Offset(0.08 * body * math.sin(a + 3), body * (0.72 - 0.16 * aw) + 0.06 * body * math.cos(a)), body * 2.2, body * 1.1, Colors.white.withValues(alpha: 0.92), body * 0.2);
    cloud(Offset(-0.32 * body + 0.12 * body * math.cos(a + 4), body * (0.42 - 0.1 * aw)), body * 0.95, body * 0.6, p.low.withValues(alpha: 0.95), body * 0.16);
    cloud(Offset(0.3 * body + 0.06 * body * math.sin(a * 1.3), -0.3 * body), body * 0.5, body * 0.32, Colors.white.withValues(alpha: 0.5), body * 0.12);
  }

  void _bang(Canvas canvas, double body) {
    final paint = Paint()..color = Colors.white.withValues(alpha: f.bang);
    final w = body * 0.26;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -body * 0.16), width: w, height: body * 0.68), Radius.circular(w / 2)), paint);
    canvas.drawCircle(Offset(0, body * 0.42), w * 0.62, paint);
  }

  @override
  bool shouldRepaint(BlobPainter old) => true;
}
