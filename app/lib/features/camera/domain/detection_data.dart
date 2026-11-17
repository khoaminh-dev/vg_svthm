import 'dart:convert';
import 'dart:ui';

/// Một vật được nhận diện trong một khung hình. Toạ độ chuẩn hoá 0..1 theo khung hình gốc của video.
class DetObject {
  const DetObject({
    required this.id,
    required this.label,
    required this.rect,
  });

  final int id;

  /// `person`, `bed` hoặc `pillow`.
  final String label;
  final Rect rect;

  bool get isPerson => label == 'person';
  bool get isBed => label == 'bed';

  DetObject copyWith({Rect? rect}) =>
      DetObject(id: id, label: label, rect: rect ?? this.rect);
}

class DetFrame {
  const DetFrame({required this.t, required this.objects});

  /// Giây kể từ đầu clip.
  final double t;
  final List<DetObject> objects;
}

/// Dữ liệu nhận diện của một clip (xem `docs/camera_demo/*.json`).
class DetectionData {
  const DetectionData({
    required this.video,
    required this.duration,
    required this.frames,
  });

  final String video;
  final double duration;
  final List<DetFrame> frames;

  static DetectionData parse(String source) {
    final m = jsonDecode(source) as Map<String, dynamic>;
    final frames = <DetFrame>[];
    for (final f in (m['frames'] as List)) {
      final fm = f as Map<String, dynamic>;
      final objs = <DetObject>[];
      for (final o in (fm['objs'] as List)) {
        final om = o as Map<String, dynamic>;
        final x = (om['x'] as num).toDouble();
        final y = (om['y'] as num).toDouble();
        final w = (om['w'] as num).toDouble();
        final h = (om['h'] as num).toDouble();
        objs.add(
          DetObject(
            id: (om['id'] as num).toInt(),
            label: om['label'] as String,
            rect: Rect.fromLTWH(x, y, w, h),
          ),
        );
      }
      frames.add(DetFrame(t: (fm['t'] as num).toDouble(), objects: objs));
    }
    frames.sort((a, b) => a.t.compareTo(b.t));
    return DetectionData(
      video: m['video'] as String? ?? '',
      duration:
          (m['duration'] as num?)?.toDouble() ??
          (frames.isEmpty ? 0 : frames.last.t),
      frames: frames,
    );
  }

  /// Các vật tại thời điểm [t]: nội suy vị trí giữa hai khung kề nhau theo `id`. Vật chỉ có ở một khung
  /// thì giữ nếu khung đó cách [t] không quá [holdSeconds], quá thì bỏ.
  List<DetObject> objectsAt(double t, {double holdSeconds = 0.3}) {
    if (frames.isEmpty) return const [];
    var hi = _firstAfter(t);
    if (hi == 0) {
      return frames.first.t - t <= holdSeconds ? frames.first.objects : const [];
    }
    final a = frames[hi - 1];
    if (hi >= frames.length) {
      return t - a.t <= holdSeconds ? a.objects : const [];
    }
    final b = frames[hi];
    final span = b.t - a.t;
    final f = span <= 0 ? 0.0 : ((t - a.t) / span).clamp(0.0, 1.0);
    final byIdB = {for (final o in b.objects) _key(o): o};
    final out = <DetObject>[];
    final used = <String>{};
    for (final o in a.objects) {
      final k = _key(o);
      final n = byIdB[k];
      if (n != null) {
        used.add(k);
        out.add(o.copyWith(rect: Rect.lerp(o.rect, n.rect, f)));
      } else if (t - a.t <= holdSeconds) {
        out.add(o);
      }
    }
    for (final o in b.objects) {
      if (!used.contains(_key(o)) && b.t - t <= holdSeconds) out.add(o);
    }
    return out;
  }

  int _firstAfter(double t) {
    var lo = 0, hi = frames.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (frames[mid].t <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static String _key(DetObject o) => '${o.label}#${o.id}';
}
