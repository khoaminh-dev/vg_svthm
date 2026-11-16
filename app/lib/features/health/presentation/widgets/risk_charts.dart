import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bp/domain/bp_models.dart';
import '../../domain/health_models.dart';

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
                      fontWeight: FontWeight.w800,
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
              fontWeight: FontWeight.w700,
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
