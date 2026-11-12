import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/bp_models.dart';

/// Biểu đồ đường: tâm thu, tâm trương và mạch theo thời gian (cũ → mới).
class BpChart extends StatelessWidget {
  const BpChart({super.key, required this.readings});

  /// Thứ tự thời gian tăng dần.
  final List<BpReading> readings;

  static const sysColor = Color(0xFFD84315);
  static const diaColor = Color(0xFF1565C0);
  static const pulseColor = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    return SizedBox(
      height: 220,
      child: CustomPaint(
        size: Size.infinite,
        painter: _BpPainter(readings, muted, Theme.of(context).textTheme.labelSmall!),
      ),
    );
  }
}

class _BpPainter extends CustomPainter {
  _BpPainter(this.data, this.grid, this.labelStyle);

  final List<BpReading> data;
  final Color grid;
  final TextStyle labelStyle;

  void _text(Canvas c, String s, Offset o, {bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle.copyWith(color: grid)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(right ? o.dx - tp.width : o.dx, o.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    const left = 34.0, bottom = 18.0, top = 6.0, rightPad = 8.0;
    final w = size.width - left - rightPad;
    final h = size.height - bottom - top;

    var lo = 1000, hi = 0;
    for (final r in data) {
      hi = max(hi, r.systolic);
      lo = min(lo, min(r.diastolic, r.pulse ?? r.diastolic));
    }
    lo = ((lo - 10) ~/ 10) * 10;
    hi = ((hi + 10) ~/ 10) * 10 + 10;
    double y(num v) => top + h * (1 - (v - lo) / (hi - lo));
    double x(int i) => left + (data.length == 1 ? w / 2 : w * i / (data.length - 1));

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var v = lo; v <= hi; v += 20) {
      canvas.drawLine(Offset(left, y(v)), Offset(size.width - rightPad, y(v)), gridPaint);
      _text(canvas, '$v', Offset(left - 6, y(v) - 6), right: true);
    }

    // Ngưỡng tham chiếu 120 / 80 (nét đứt).
    final ref = Paint()
      ..color = grid.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (final v in [120, 80]) {
      if (v < lo || v > hi) continue;
      for (var dx = left; dx < size.width - rightPad; dx += 8) {
        canvas.drawLine(
          Offset(dx, y(v)),
          Offset(min(dx + 4, size.width - rightPad), y(v)),
          ref,
        );
      }
    }

    void line(num? Function(BpReading) pick, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var started = false;
      for (var i = 0; i < data.length; i++) {
        final v = pick(data[i]);
        if (v == null) continue;
        final p = Offset(x(i), y(v));
        if (started) {
          path.lineTo(p.dx, p.dy);
        } else {
          path.moveTo(p.dx, p.dy);
          started = true;
        }
      }
      canvas.drawPath(path, paint);
      final dot = Paint()..color = color;
      for (var i = 0; i < data.length; i++) {
        final v = pick(data[i]);
        if (v != null) canvas.drawCircle(Offset(x(i), y(v)), 3.4, dot);
      }
    }

    line((r) => r.pulse, BpChart.pulseColor);
    line((r) => r.diastolic, BpChart.diaColor);
    line((r) => r.systolic, BpChart.sysColor);

    String d(DateTime t) => '${t.day}/${t.month}';
    _text(canvas, d(data.first.measuredAt), Offset(left, size.height - 14));
    if (data.length > 1) {
      _text(
        canvas,
        d(data.last.measuredAt),
        Offset(size.width - rightPad, size.height - 14),
        right: true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BpPainter old) => old.data != data;
}
