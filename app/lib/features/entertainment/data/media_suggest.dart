import '../../voice/live/live_hybrid.dart' show foldVi;
import 'media_memory.dart';

/// Vy chủ động gợi ý nhạc/video quen nghe đúng giờ quen (kế hoạch docs/KE_HOACH_VY_GIAI_TRI.md mục D).
/// Phần QUYẾT ĐỊNH, thuần để kiểm thử; việc "có đang bận không", "đã nhắc việc quan trọng hơn chưa" do bộ nhắc chung lo
/// (`decideReminder`: thuốc > đo huyết áp > tin nhắn > gợi ý giải trí).
class MediaSuggestion {
  const MediaSuggestion({required this.key, required this.topic, required this.part});

  /// Mã chống nhắc lặp: một lần cho mỗi buổi trong ngày.
  final String key;

  /// Chủ đề hay nghe vào khung giờ này ("nhạc xưa", "tập dưỡng sinh").
  final String topic;
  final DayPart part;
}

/// Cần ít nhất chừng này lượt nghe cùng chủ đề trong cùng khung giờ mới coi là thói quen.
const minHabitPlays = 2;

/// Gợi ý trong khoảng từ [windowBefore] trước đến [windowAfter] sau giờ quen nghe.
const windowBefore = 1;
const windowAfter = 2;

/// Có nên gợi ý lúc [now] không. Trả về null nếu: ban đêm, chưa có thói quen cùng khung giờ,
/// chưa tới/đã quá giờ quen, hoặc hôm nay đã nghe gì trong khung giờ này rồi.
MediaSuggestion? suggestMedia({required DateTime now, required MediaMemory memory}) {
  final part = dayPartOf(now);
  if (part == DayPart.night) return null;

  final today = DateTime(now.year, now.month, now.day);
  bool sameDay(DateTime t) => DateTime(t.year, t.month, t.day) == today;

  final byTopic = <String, List<MediaEntry>>{};
  final shown = <String, String>{};
  for (final e in memory.entries) {
    if (e.disliked || e.topic.trim().isEmpty) continue;
    if (dayPartOf(e.playedAt) != part) continue;
    if (now.difference(e.playedAt).inDays > 45) continue;
    // Hôm nay đã nghe gì trong khung giờ này rồi thì thôi, đừng gợi ý nữa.
    if (sameDay(e.playedAt)) return null;
    final k = foldVi(e.topic);
    if (k.isEmpty) continue;
    (byTopic[k] ??= []).add(e);
    shown.putIfAbsent(k, () => e.topic.trim());
  }

  String? bestKey;
  var bestScore = 0;
  for (final en in byTopic.entries) {
    final plays = en.value.fold<int>(0, (s, e) => s + e.count);
    if (plays < minHabitPlays) continue;
    if (plays > bestScore) {
      bestScore = plays;
      bestKey = en.key;
    }
  }
  if (bestKey == null) return null;

  // Giờ quen nghe = trung vị giờ của các lần nghe chủ đề này; chỉ gợi ý quanh giờ đó.
  final hours = [for (final e in byTopic[bestKey]!) e.playedAt.hour]..sort();
  final habitHour = hours[hours.length ~/ 2];
  final nowH = now.hour + now.minute / 60;
  if (nowH < habitHour - windowBefore || nowH >= habitHour + windowAfter + 1) return null;

  return MediaSuggestion(
    key: 'media:${now.year}-${now.month}-${now.day}:${part.name}',
    topic: shown[bestKey]!,
    part: part,
  );
}
