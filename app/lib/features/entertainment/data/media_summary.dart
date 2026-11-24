import 'package:supabase_flutter/supabase_flutter.dart';

import '../../voice/live/live_hybrid.dart' show foldVi;

/// Một dòng tóm tắt: thể loại, ngày, số giây nghe, số lượt. KHÔNG có tên bài (kế hoạch Q2: người thân chỉ xem thể loại và thời lượng).
class MediaDay {
  const MediaDay({required this.day, required this.topic, required this.seconds, required this.plays});

  final DateTime day;
  final String topic;
  final int seconds;
  final int plays;
}

/// Gửi và đọc tóm tắt nghe/xem. Gửi chỉ do chính chủ; đọc do chính chủ hoặc người thân được cấp quyền `vy_history`.
abstract interface class MediaSummaryRepository {
  /// Cộng dồn [seconds] giây nghe chủ đề [topic] cho hôm nay.
  Future<void> addTime(String topic, int seconds, {int plays = 0});

  /// Tóm tắt [days] ngày gần nhất của [ownerId] (rỗng nếu không có quyền hoặc chưa có gì).
  Future<List<MediaDay>> recent(String ownerId, {int days = 7});
}

class SupabaseMediaSummaryRepository implements MediaSummaryRepository {
  SupabaseMediaSummaryRepository(this._c);

  final SupabaseClient _c;

  @override
  Future<void> addTime(String topic, int seconds, {int plays = 0}) async {
    await _c.rpc('add_media_time', params: {'p_topic': topic, 'p_seconds': seconds, 'p_plays': plays});
  }

  @override
  Future<List<MediaDay>> recent(String ownerId, {int days = 7}) async {
    final since = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await _c
        .from('media_daily')
        .select('day, topic, seconds, plays')
        .eq('user_id', ownerId)
        .gte('day', '${since.year}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}')
        .order('day', ascending: false);
    return [
      for (final r in rows)
        MediaDay(
          day: DateTime.parse(r['day'] as String),
          topic: r['topic'] as String,
          seconds: (r['seconds'] as num).toInt(),
          plays: (r['plays'] as num).toInt(),
        ),
    ];
  }
}

/// Tóm tắt để hiện cho người thân.
class MediaSummary {
  const MediaSummary({required this.today, required this.weekSeconds, required this.topTopic, required this.activeDays});

  /// Hôm nay: thể loại và số giây, nghe nhiều nhất trước.
  final List<({String topic, int seconds})> today;
  final int weekSeconds;
  final String? topTopic;
  final int activeDays;

  bool get isEmpty => weekSeconds <= 0;
}

/// Gộp các dòng thô thành tóm tắt. Thuần để kiểm thử.
MediaSummary summarizeMedia(List<MediaDay> rows, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final todayBy = <String, int>{};
  final weekBy = <String, int>{};
  final shown = <String, String>{};
  final days = <DateTime>{};
  var week = 0;
  for (final r in rows) {
    if (r.seconds <= 0) continue;
    final d = DateTime(r.day.year, r.day.month, r.day.day);
    final key = foldVi(r.topic);
    shown.putIfAbsent(key, () => r.topic);
    week += r.seconds;
    days.add(d);
    weekBy[key] = (weekBy[key] ?? 0) + r.seconds;
    if (d == today) todayBy[key] = (todayBy[key] ?? 0) + r.seconds;
  }
  final todayList = [
    for (final e in (todayBy.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) (topic: shown[e.key]!, seconds: e.value),
  ];
  String? top;
  var best = 0;
  for (final e in weekBy.entries) {
    if (e.value > best) {
      best = e.value;
      top = shown[e.key];
    }
  }
  return MediaSummary(today: todayList, weekSeconds: week, topTopic: top, activeDays: days.length);
}

/// "40 phút", "1 giờ 5 phút", "dưới 1 phút".
String durationText(int seconds) {
  if (seconds < 60) return 'dưới 1 phút';
  final m = (seconds / 60).round();
  if (m < 60) return '$m phút';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h giờ' : '$h giờ $r phút';
}
