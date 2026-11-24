import 'dart:convert';

import '../../voice/live/live_hybrid.dart' show foldVi;
import 'youtube_service.dart';

/// Trí nhớ nghe/xem của một người dùng (kế hoạch docs/KE_HOACH_VY_GIAI_TRI.md mục 5.3, Q2): bài đã nghe, bài thích,
/// bài không thích, chỗ xem dở. Chỉ nằm trên máy, theo tài khoản; người dùng tắt hoặc xoá được.
/// Phần thuần (không Flutter) để kiểm thử.
class MediaEntry {
  const MediaEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.topic,
    required this.playedAt,
    this.durationSec = 0,
    this.progressSec = 0,
    this.count = 1,
    this.completed = false,
    this.liked = false,
    this.disliked = false,
  });

  final String id;
  final String title;
  final String author;

  /// Từ khoá người dùng đã dùng để tìm ("nhạc xưa", "cải lương").
  final String topic;
  final DateTime playedAt;
  final int durationSec;
  final int progressSec;
  final int count;
  final bool completed;
  final bool liked;
  final bool disliked;

  MediaEntry copyWith({
    String? topic,
    DateTime? playedAt,
    int? durationSec,
    int? progressSec,
    int? count,
    bool? completed,
    bool? liked,
    bool? disliked,
  }) => MediaEntry(
    id: id,
    title: title,
    author: author,
    topic: topic ?? this.topic,
    playedAt: playedAt ?? this.playedAt,
    durationSec: durationSec ?? this.durationSec,
    progressSec: progressSec ?? this.progressSec,
    count: count ?? this.count,
    completed: completed ?? this.completed,
    liked: liked ?? this.liked,
    disliked: disliked ?? this.disliked,
  );

  VideoItem toVideo() => VideoItem(
    id: id,
    title: title,
    author: author,
    thumbnailUrl: 'https://i.ytimg.com/vi/$id/mqdefault.jpg',
    duration: durationSec > 0 ? Duration(seconds: durationSec) : null,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'topic': topic,
    'at': playedAt.millisecondsSinceEpoch,
    'dur': durationSec,
    'pos': progressSec,
    'n': count,
    if (completed) 'done': true,
    if (liked) 'like': true,
    if (disliked) 'dislike': true,
  };

  static MediaEntry? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = o['id'];
    if (id is! String || id.isEmpty) return null;
    int i(Object? v) => v is num ? v.toInt() : 0;
    return MediaEntry(
      id: id,
      title: '${o['title'] ?? ''}',
      author: '${o['author'] ?? ''}',
      topic: '${o['topic'] ?? ''}',
      playedAt: DateTime.fromMillisecondsSinceEpoch(i(o['at'])),
      durationSec: i(o['dur']),
      progressSec: i(o['pos']),
      count: i(o['n']) <= 0 ? 1 : i(o['n']),
      completed: o['done'] == true,
      liked: o['like'] == true,
      disliked: o['dislike'] == true,
    );
  }
}

enum DayPart { morning, noon, afternoon, evening, night }

DayPart dayPartOf(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 11) return DayPart.morning;
  if (h >= 11 && h < 14) return DayPart.noon;
  if (h >= 14 && h < 18) return DayPart.afternoon;
  if (h >= 18 && h < 22) return DayPart.evening;
  return DayPart.night;
}

class MediaMemory {
  const MediaMemory({this.entries = const [], this.maxEntries = 150});

  /// Mới nhất trước.
  final List<MediaEntry> entries;
  final int maxEntries;

  bool get isEmpty => entries.isEmpty;

  // ---------- ghi ----------

  /// Bắt đầu nghe/xem [v] (theo từ khoá [topic]). Đã có thì đưa lên đầu và cộng lượt nghe.
  MediaMemory recordPlay(VideoItem v, String topic, DateTime now) {
    final dur = v.duration?.inSeconds ?? 0;
    final old = _find(v.id);
    final entry = old == null
        ? MediaEntry(id: v.id, title: v.title, author: v.author, topic: topic.trim(), playedAt: now, durationSec: dur)
        : old.copyWith(
            playedAt: now,
            count: old.count + 1,
            topic: topic.trim().isEmpty ? old.topic : topic.trim(),
            durationSec: dur > 0 ? dur : old.durationSec,
          );
    return _with([entry, ...entries.where((e) => e.id != v.id)]);
  }

  /// Cập nhật chỗ đang xem. [completed] khi đã hết bài.
  MediaMemory updateProgress(String id, {required int progressSec, int? durationSec, bool completed = false}) {
    final old = _find(id);
    if (old == null) return this;
    final dur = (durationSec ?? 0) > 0 ? durationSec! : old.durationSec;
    return _replace(old.copyWith(progressSec: completed ? 0 : progressSec, durationSec: dur, completed: completed));
  }

  MediaMemory setLiked(String id, bool v) {
    final old = _find(id);
    return old == null ? this : _replace(old.copyWith(liked: v, disliked: v ? false : old.disliked));
  }

  MediaMemory setDisliked(String id, bool v) {
    final old = _find(id);
    return old == null ? this : _replace(old.copyWith(disliked: v, liked: v ? false : old.liked));
  }

  // ---------- đọc ----------

  Set<String> get dislikedIds => {for (final e in entries) if (e.disliked) e.id};
  Set<String> get likedIds => {for (final e in entries) if (e.liked) e.id};
  List<MediaEntry> get liked => [for (final e in entries) if (e.liked) e];

  /// Bài nghe gần nhất mà người dùng không chê.
  MediaEntry? get last => entries.where((e) => !e.disliked).firstOrNull;

  /// Bài dài đang xem dở: đã xem ít nhất 1 phút, còn ít nhất 90 giây, trong 14 ngày gần đây.
  MediaEntry? resumable(DateTime now) {
    for (final e in entries) {
      if (e.disliked || e.completed) continue;
      if (now.difference(e.playedAt).inDays > 14) continue;
      if (e.durationSec >= 900 && e.progressSec >= 60 && e.progressSec <= e.durationSec - 90) return e;
    }
    return null;
  }

  /// Chủ đề hay nghe, nhiều điểm nhất trước. Lượt nghe cùng khung giờ tính gấp đôi, lượt cũ hơn 45 ngày bỏ qua.
  List<String> topTopics(DateTime now, {int limit = 3}) {
    final score = <String, double>{};
    final shown = <String, String>{};
    final plays = <String, int>{};
    final part = dayPartOf(now);
    for (final e in entries) {
      if (e.disliked || e.topic.trim().isEmpty) continue;
      if (now.difference(e.playedAt).inDays > 45) continue;
      final key = foldVi(e.topic);
      if (key.isEmpty) continue;
      shown.putIfAbsent(key, () => e.topic.trim());
      plays[key] = (plays[key] ?? 0) + e.count;
      score[key] = (score[key] ?? 0) + e.count * (dayPartOf(e.playedAt) == part ? 2.0 : 1.0);
    }
    final keys = score.keys.where((k) => (plays[k] ?? 0) >= 2).toList()
      ..sort((a, b) => score[b]!.compareTo(score[a]!));
    return [for (final k in keys.take(limit)) shown[k]!];
  }

  /// Chủ đề nên mở khi người dùng chỉ nói "mở nhạc"; null nếu chưa đủ thói quen (chưa ≥ 2 lượt).
  String? suggestedTopic(DateTime now) => topTopics(now, limit: 1).firstOrNull;

  /// Gửi lên não Vy mỗi lượt để biết nên hỏi hay đoán. Chỉ chứa chủ đề và tên bài, không có gì khác.
  Map<String, Object?> habitJson(DateTime now) {
    final topics = topTopics(now);
    final r = resumable(now);
    final l = last;
    return {
      'top': topics.firstOrNull ?? '',
      'topics': topics,
      'resume': r == null ? '' : cleanVideoTitle(r.title, maxChars: 60),
      'last': l == null ? '' : cleanVideoTitle(l.title, maxChars: 60),
    };
  }

  // ---------- lưu ----------

  String encode() => jsonEncode([for (final e in entries) e.toJson()]);

  static MediaMemory decode(String? s, {int maxEntries = 150}) {
    if (s == null || s.isEmpty) return MediaMemory(maxEntries: maxEntries);
    try {
      final raw = jsonDecode(s);
      if (raw is! List) return MediaMemory(maxEntries: maxEntries);
      final list = [for (final o in raw) ?MediaEntry.fromJson(o)];
      return MediaMemory(entries: list, maxEntries: maxEntries);
    } catch (_) {
      return MediaMemory(maxEntries: maxEntries);
    }
  }

  // ---------- nội bộ ----------

  MediaEntry? _find(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  MediaMemory _replace(MediaEntry e) => MediaMemory(
    entries: [for (final x in entries) x.id == e.id ? e : x],
    maxEntries: maxEntries,
  );

  MediaMemory _with(List<MediaEntry> list) {
    if (list.length <= maxEntries) return MediaMemory(entries: list, maxEntries: maxEntries);
    // Quá nhiều: bỏ bài cũ nhất, nhưng giữ bài thích và bài không thích (để khỏi mở lại bài người dùng đã chê).
    final keep = <MediaEntry>[];
    var room = maxEntries;
    for (final e in list) {
      if (e.liked || e.disliked) room--;
    }
    for (final e in list) {
      if (e.liked || e.disliked) {
        keep.add(e);
      } else if (room > 0) {
        keep.add(e);
        room--;
      }
    }
    return MediaMemory(entries: keep, maxEntries: maxEntries);
  }
}
