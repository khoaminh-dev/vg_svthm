import 'dart:math' as math;

import 'detection_data.dart';

enum PersonState { standing, sitting, lying }

/// Mức cảnh báo: thông tin (im lặng), cần chú ý (vàng, chỉ hiện trên trang), khẩn cấp (đỏ, banner + rung + âm).
enum AlertLevel { info, watch, urgent }

/// Ngưỡng tính sự kiện. Bộ [real] dùng thật; bộ [demo] rút xuống vài giây để quay được trong một vòng clip.
class AlertThresholds {
  const AlertThresholds({
    this.stableSeconds = 3,
    required this.lyingWatchSeconds,
    required this.sittingWatchSeconds,
    required this.absentUrgentSeconds,
  });

  /// Một trạng thái phải giữ ổn định ngần này mới được tính (chống chớp).
  final double stableSeconds;
  final double lyingWatchSeconds;
  final double sittingWatchSeconds;
  final double absentUrgentSeconds;

  static const real = AlertThresholds(
    lyingWatchSeconds: 3 * 3600,
    sittingWatchSeconds: 30 * 60,
    absentUrgentSeconds: 30 * 60,
  );

  static const demo = AlertThresholds(
    lyingWatchSeconds: 8,
    sittingWatchSeconds: 10,
    absentUrgentSeconds: 6,
  );
}

class CameraEvent {
  const CameraEvent({
    required this.t,
    required this.level,
    required this.text,
    this.personId,
    this.state,
  });

  /// Giây trong clip.
  final double t;
  final AlertLevel level;
  final String text;
  final int? personId;
  final PersonState? state;
}

/// Phân loại tư thế của một người so với các giường trong cùng khung hình.
/// [videoAspect] là rộng/cao của video, để đổi toạ độ chuẩn hoá về tỉ lệ điểm ảnh.
PersonState classifyPerson(
  DetObject person,
  Iterable<DetObject> beds, {
  double videoAspect = 16 / 9,
}) {
  final r = person.rect;
  if (r.width <= 0 || r.height <= 0) return PersonState.standing;
  final aspect = (r.width * videoAspect) / r.height;
  var overlap = 0.0;
  for (final b in beds) {
    final i = r.intersect(b.rect);
    if (i.width <= 0 || i.height <= 0) continue;
    overlap = math.max(overlap, (i.width * i.height) / (r.width * r.height));
  }
  if (aspect >= 1.2 && overlap >= 0.4) return PersonState.lying;
  if (aspect >= 0.55 && overlap >= 0.25) return PersonState.sitting;
  return PersonState.standing;
}

PersonState classifyAt(
  DetObject person,
  List<DetObject> frameObjects, {
  double videoAspect = 16 / 9,
}) => classifyPerson(
  person,
  frameObjects.where((o) => o.isBed),
  videoAspect: videoAspect,
);

class _Track {
  PersonState? committed;
  double committedSince = 0;
  PersonState? candidate;
  double candidateSince = 0;
  double lastSeen = -1e9;
  bool watched = false;
}

/// Kết quả phân tích cả clip: các sự kiện theo thời gian và trạng thái đã ổn định của từng người.
class CameraAnalysis {
  CameraAnalysis._(this.events, this._history);

  final List<CameraEvent> events;
  final Map<int, List<(double, PersonState)>> _history;

  /// Trạng thái đã ổn định của người [id] tại [t]; null nếu chưa đủ ổn định.
  PersonState? stateOf(int id, double t) {
    final h = _history[id];
    if (h == null) return null;
    PersonState? s;
    for (final e in h) {
      if (e.$1 <= t) {
        s = e.$2;
      } else {
        break;
      }
    }
    return s;
  }

  static CameraAnalysis build(
    DetectionData data, {
    AlertThresholds thresholds = AlertThresholds.demo,
    double videoAspect = 16 / 9,
  }) {
    final events = <CameraEvent>[];
    final tracks = <int, _Track>{};
    final history = <int, List<(double, PersonState)>>{};
    double lastPersonAt = 0;
    var absentFlagged = false;
    final frames = data.frames;

    for (final f in frames) {
      final people = f.objects.where((o) => o.isPerson).toList();
      if (people.isNotEmpty) {
        lastPersonAt = f.t;
        absentFlagged = false;
      } else if (!absentFlagged &&
          f.t - lastPersonAt >= thresholds.absentUrgentSeconds) {
        absentFlagged = true;
        events.add(
          CameraEvent(
            t: lastPersonAt + thresholds.absentUrgentSeconds,
            level: AlertLevel.urgent,
            text: 'Không thấy ai trong phòng',
          ),
        );
      }

      for (final p in people) {
        final s = classifyAt(p, f.objects, videoAspect: videoAspect);
        final tr = tracks.putIfAbsent(p.id, _Track.new);
        if (f.t - tr.lastSeen > 1.5) tr.candidate = null;
        tr.lastSeen = f.t;

        if (s == tr.committed) {
          tr.candidate = null;
        } else if (tr.candidate != s) {
          tr.candidate = s;
          tr.candidateSince = f.t;
        } else if (f.t - tr.candidateSince >= thresholds.stableSeconds) {
          final prev = tr.committed;
          tr.committed = s;
          tr.committedSince = tr.candidateSince;
          tr.candidate = null;
          tr.watched = false;
          (history[p.id] ??= []).add((tr.candidateSince, s));
          final e = _transition(p.id, prev, s, tr.committedSince);
          if (e != null) events.add(e);
        }

        // Đã ổn định đủ lâu để cần chú ý.
        if (!tr.watched && tr.committed != null && tr.committed == s) {
          final held = f.t - tr.committedSince;
          if (s == PersonState.lying && held >= thresholds.lyingWatchSeconds) {
            tr.watched = true;
            events.add(
              CameraEvent(
                t: tr.committedSince + thresholds.lyingWatchSeconds,
                level: AlertLevel.watch,
                text: 'Người ${p.id} nằm khá lâu',
                personId: p.id,
                state: s,
              ),
            );
          } else if (s == PersonState.sitting &&
              held >= thresholds.sittingWatchSeconds) {
            tr.watched = true;
            events.add(
              CameraEvent(
                t: tr.committedSince + thresholds.sittingWatchSeconds,
                level: AlertLevel.watch,
                text: 'Người ${p.id} ngồi mép giường khá lâu',
                personId: p.id,
                state: s,
              ),
            );
          }
        }
      }
    }
    events.sort((a, b) => a.t.compareTo(b.t));
    return CameraAnalysis._(events, history);
  }

  static CameraEvent? _transition(
    int id,
    PersonState? from,
    PersonState to,
    double t,
  ) {
    if (to == PersonState.lying) {
      return CameraEvent(
        t: t,
        level: AlertLevel.info,
        text: from == null ? 'Người $id đang nằm' : 'Người $id nằm xuống',
        personId: id,
        state: to,
      );
    }
    if (from == PersonState.lying) {
      return CameraEvent(
        t: t,
        level: AlertLevel.info,
        text: 'Người $id ngồi dậy',
        personId: id,
        state: to,
      );
    }
    return null;
  }
}

/// Số người theo tư thế tại một thời điểm, để hiện ở thẻ trạng thái.
class StateSummary {
  const StateSummary({
    this.lying = 0,
    this.sitting = 0,
    this.standing = 0,
  });

  final int lying;
  final int sitting;
  final int standing;

  int get total => lying + sitting + standing;

  /// Ví dụ "1 người nằm · 2 người ngồi · 1 người đi lại"; rỗng thì "Chưa thấy ai".
  String get text {
    final parts = <String>[
      if (lying > 0) '$lying người nằm',
      if (sitting > 0) '$sitting người ngồi',
      if (standing > 0) '$standing người đi lại',
    ];
    return parts.isEmpty ? 'Chưa thấy ai' : parts.join(' · ');
  }

  static StateSummary at(
    DetectionData data,
    CameraAnalysis analysis,
    double t, {
    double videoAspect = 16 / 9,
  }) {
    final objs = data.objectsAt(t);
    var lying = 0, sitting = 0, standing = 0;
    for (final p in objs.where((o) => o.isPerson)) {
      final s =
          analysis.stateOf(p.id, t) ??
          classifyAt(p, objs, videoAspect: videoAspect);
      switch (s) {
        case PersonState.lying:
          lying++;
        case PersonState.sitting:
          sitting++;
        case PersonState.standing:
          standing++;
      }
    }
    return StateSummary(lying: lying, sitting: sitting, standing: standing);
  }
}

/// Mức cao nhất đang cần hiện tại thời điểm [t]: sự kiện vàng/đỏ xảy ra trong [window] giây gần nhất.
CameraEvent? activeAlert(
  List<CameraEvent> events,
  double t, {
  double window = 6,
}) {
  CameraEvent? best;
  for (final e in events) {
    if (e.level == AlertLevel.info) continue;
    if (e.t <= t && t - e.t <= window) {
      if (best == null || e.level.index >= best.level.index) best = e;
    }
  }
  return best;
}
