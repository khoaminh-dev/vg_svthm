import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bp/domain/bp_models.dart';
import '../../domain/health_models.dart';
import '../../../../shared/honorific.dart';

/// Màu của từng nấc trên thanh cột: xanh, vàng, cam, cam đậm, đỏ.
Color barColorFor(BpCategory c) => c.color;

/// Biểu đồ cột kiểu sóng wifi cho mức huyết áp: số cột sáng càng nhiều thì huyết áp càng cao.
/// Các cột mọc lần lượt từ nhỏ đến lớn rồi dừng ở mức hiện tại; mức cao thì sáng màu đỏ.
class BpBars extends StatefulWidget {
  const BpBars({super.key, required this.category, this.height = 64});

  final BpCategory category;
  final double height;

  static const count = 5;

  @override
  State<BpBars> createState() => _BpBarsState();
}

class _BpBarsState extends State<BpBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didUpdateWidget(BpBars old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lit = widget.category.index + 1;
    final color = barColorFor(widget.category);
    return Semantics(
      label:
          'Mức huyết áp: ${widget.category.label}, $lit trên ${BpBars.count} cột',
      excludeSemantics: true,
      child: SizedBox(
        key: const Key('bp-bars'),
        height: widget.height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < BpBars.count; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _bar(i, lit, color),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(int i, int lit, Color color) {
    // Chiều cao tăng dần theo từng cột, như vạch sóng wifi.
    final full = widget.height * (0.3 + 0.7 * (i + 1) / BpBars.count);
    final on = i < lit;
    // Cột thứ i bắt đầu mọc sau i * 0.14 của thời gian chạy.
    final t = ((_c.value - i * 0.14) / 0.36).clamp(0.0, 1.0);
    final grown = Curves.easeOutBack.transform(t).clamp(0.0, 1.05);
    return Container(
      key: Key('bar-$i${on ? '-on' : ''}'),
      width: 16,
      height: on ? full * grown : full,
      decoration: BoxDecoration(
        color: on ? color : AppColors.border.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

/// Vòng tròn một vấn đề sức khoẻ: phần tô đúng bằng tỉ lệ ước tính, số % ở giữa, tên và nhãn thời gian bên dưới.
class RiskDonut extends StatelessWidget {
  const RiskDonut({
    super.key,
    required this.name,
    required this.note,
    required this.p,
    required this.color,
    this.size = 108,
  });

  final String name;

  /// Nhãn nhỏ bên dưới tên ("trong 10 năm", "ước tính").
  final String note;

  /// Xác suất từ 0 đến 1.
  final double p;
  final Color color;
  final double size;

  /// "12%"; dưới 1% hiện "<1%" để không nói là 0.
  static String percent(double p) {
    final v = p * 100;
    if (v <= 0) return '0%';
    if (v < 1) return '<1%';
    if (v > 99) return '>99%';
    return '${v.round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$name $note: ${percent(p)}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: p.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _DonutPainter(fraction: v, color: color),
                child: Center(
                  child: Text(
                    percent(p),
                    key: const Key('donut-percent'),
                    style: TextStyle(
                      fontSize: size * 0.24,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            note,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.border.withValues(alpha: 0.9);
    canvas.drawArc(arc, 0, math.pi * 2, false, track);
    if (fraction <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    // Vòng nhỏ vẫn phải nhìn thấy được: tối thiểu một chấm tròn, nhưng không tô quá phần thật.
    final sweep = math.max(fraction * math.pi * 2, 0.04);
    canvas.drawArc(arc, -math.pi / 2, sweep, false, fill);
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.fraction != fraction || old.color != color;
}

/// Biểu đồ đường xu hướng nguy cơ theo thời gian (đột quỵ, tim mạch, tiểu đường). Trục đứng là xác suất ước tính.
class RiskTrendChart extends StatelessWidget {
  const RiskTrendChart({super.key, required this.points, this.height = 150});

  final List<TrendPoint> points;
  final double height;

  static const strokeColor = Color(0xFFE0785F);
  static const heartColor = Color(0xFF0048A8);
  static const diabetesColor = Color(0xFF2D8B72);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.length < 2) {
      return Padding(
        key: const Key('trend-empty'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          hon('Cần ít nhất 2 lần đánh giá để vẽ xu hướng. Bác cứ đo huyết áp đều nhé.'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      );
    }
    final hasDiabetes = points.any((p) => p.diabetes != null);
    return Column(
      key: const Key('trend-chart'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _legend('Đột quỵ', strokeColor),
            _legend('Tim mạch', heartColor),
            if (hasDiabetes) _legend('Tiểu đường', diabetesColor),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _TrendPainter(points)),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _d(points.first.at),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            Text(
              _d(points.last.at),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _d(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

  Widget _legend(String name, Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 4,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points);

  final List<TrendPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    final plot = Rect.fromLTWH(
      left,
      6,
      size.width - left - 6,
      size.height - 12,
    );
    var top = 0.0;
    for (final p in points) {
      for (final v in [p.stroke, p.heart, p.diabetes]) {
        if (v != null && v > top) top = v;
      }
    }
    top = math.max(0.2, ((top * 10).ceil() / 10) + 0.05).clamp(0.2, 1.0);

    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final label = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      label.text = TextSpan(
        text: '${(top * i / 4 * 100).round()}%',
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
      );
      label.layout();
      label.paint(canvas, Offset(0, y - label.height / 2));
    }

    final t0 = points.first.at.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, points.last.at.millisecondsSinceEpoch - t0);
    double x(TrendPoint p) =>
        plot.left + plot.width * (p.at.millisecondsSinceEpoch - t0) / span;
    double y(double v) => plot.bottom - plot.height * (v / top).clamp(0.0, 1.0);

    void line(double? Function(TrendPoint) get, Color c) {
      final paint = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final dot = Paint()..color = c;
      final path = Path();
      var started = false;
      for (final p in points) {
        final v = get(p);
        if (v == null) continue;
        final o = Offset(x(p), y(v));
        if (!started) {
          path.moveTo(o.dx, o.dy);
          started = true;
        } else {
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawCircle(o, 3.5, dot);
      }
      canvas.drawPath(path, paint);
    }

    line((p) => p.stroke, RiskTrendChart.strokeColor);
    line((p) => p.heart, RiskTrendChart.heartColor);
    line((p) => p.diabetes, RiskTrendChart.diabetesColor);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.points != points;
}

/// Hàng vòng tròn: Đột quỵ và Tim mạch (10 năm), kèm thẻ tên các vấn đề không có % (tăng huyết áp).
class RiskDonuts extends StatelessWidget {
  const RiskDonuts({super.key, required this.result, this.size = 108});

  final RiskResult result;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final stroke = r.strokeP;
    final heart = r.heartP;
    final diabetes = r.diabetesP;
    // Ba vòng thì thu nhỏ một chút để vừa một hàng.
    final s = diabetes != null && size > 96 ? 92.0 : size;
    return Row(
      key: const Key('risk-donuts'),
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stroke != null)
          RiskDonut(
            name: 'Đột quỵ',
            note: 'ước tính',
            p: stroke,
            color: r.strokeLevel.color,
            size: s,
          ),
        if (heart != null)
          RiskDonut(
            name: r.ageOutOfRange ? 'Tim mạch *' : 'Tim mạch',
            note: 'trong 10 năm',
            p: heart,
            color: r.heartLevel.color,
            size: s,
          ),
        if (diabetes != null)
          RiskDonut(
            name: 'Tiểu đường',
            note: 'ước tính',
            p: diabetes,
            color: r.diabetesLevel.color,
            size: s,
          ),
      ],
    );
  }
}
