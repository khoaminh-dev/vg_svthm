import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../blob/blob_engine.dart';
import '../blob/blob_painter.dart';
import '../blob/blob_types.dart';

export '../blob/blob_types.dart' show OrbMode, BlobMood;

/// Vy dạng Blob: một khối tròn biến hình liên tục.
/// - Chưa đánh thức ([awake] = false): xám, khói trôi chậm bên trong, đang "ngủ".
/// - Đánh thức: lên màu, mắt mở ra, màu và nét mặt theo [mood].
/// - Nghe: phồng theo [level]; nói: rung theo âm thanh (số đo thật nếu có, không thì nhịp lời nói mô phỏng);
///   nghĩ: đổi dạng tròn → trứng → lục giác → tam giác.
/// - [emphasis] tăng thêm 1 = một lần nhấn mạnh (vòng sáng + nảy). Giảm chuyển động của hệ thống thì đứng yên.
class VyOrb extends StatefulWidget {
  const VyOrb({
    super.key,
    this.mode = OrbMode.idle,
    this.level = 0,
    this.size = 220,
    this.awake = false,
    this.mood = BlobMood.calm,
    this.emphasis = 0,
  });

  final OrbMode mode;
  final double level;
  final double size;
  final bool awake;
  final BlobMood mood;
  final int emphasis;

  @override
  State<VyOrb> createState() => _VyOrbState();
}

class _VyOrbState extends State<VyOrb> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _engine = BlobEngine();
  final _repaint = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    _advance(dt);
    _repaint.value++;
  }

  void _advance(double dt) {
    final w = widget;
    _engine.step(
      dt,
      mode: w.mode,
      awake: w.awake,
      mood: w.mood,
      // Khi nói mà chưa có số đo âm lượng thật thì để engine tự mô phỏng nhịp lời nói.
      level: (w.mode == OrbMode.speaking && w.level < 0.02) ? null : w.level,
      emphasis: w.emphasis,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce != _still) {
      _still = reduce;
      if (reduce) {
        // Đứng yên: vẫn cập nhật trạng thái (màu, mắt) một lần để hiển thị đúng.
        for (var i = 0; i < 30; i++) {
          _advance(0.05);
        }
        _ticker.stop();
        _repaint.value++;
      } else if (!_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    }
  }

  @override
  void didUpdateWidget(VyOrb old) {
    super.didUpdateWidget(old);
    if (_still) {
      for (var i = 0; i < 30; i++) {
        _advance(0.05);
      }
      _repaint.value++;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  String get _label {
    if (!widget.awake && widget.mode == OrbMode.idle) return 'Vy đang nghỉ';
    return switch (widget.mode) {
      OrbMode.idle => 'Vy đang chờ',
      OrbMode.listening => 'Vy đang nghe',
      OrbMode.thinking => 'Vy đang suy nghĩ',
      OrbMode.speaking => 'Vy đang nói',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: _label,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: widget.size,
            child: ListenableBuilder(
              listenable: _repaint,
              builder: (context, _) => CustomPaint(
                painter: BlobPainter(_engine.frame(widget.size, widget.mode, still: _still)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
