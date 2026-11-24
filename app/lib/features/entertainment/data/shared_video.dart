import 'youtube_service.dart';

/// Video người thân gửi cho mình qua tin nhắn (kế hoạch docs/KE_HOACH_VY_GIAI_TRI.md D3, K2).
/// Không cần bảng riêng: đó là một tin nhắn thường có đường dẫn YouTube. Vy và bong bóng chat nhận ra đường dẫn đó
/// để hiện thẻ xem được ngay thay vì chữ khó đọc, và để Vy báo "con gái gửi bác một video".
class SharedVideo {
  const SharedVideo({required this.id, required this.title});

  final String id;
  final String title;

  VideoItem toVideo() => VideoItem(
    id: id,
    title: title,
    author: '',
    thumbnailUrl: 'https://i.ytimg.com/vi/$id/mqdefault.jpg',
  );
}

/// Dạng tin nhắn khi gửi: dòng tên video rồi đường dẫn (đọc được cả khi người nhận dùng app cũ).
String encodeSharedVideo(VideoItem v) {
  final title = v.title.replaceAll(RegExp(r'\s+'), ' ').trim();
  final short = title.length > 100 ? '${title.substring(0, 100).trimRight()}…' : title;
  return '🎬 $short\nhttps://www.youtube.com/watch?v=${v.id}';
}

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Các dạng đường dẫn YouTube hay gặp: watch?v=, youtu.be/, shorts/, embed/, live/.
final _linkPattern = RegExp(
  r'(?:https?://)?(?:www\.|m\.|music\.)?(?:youtube\.com/(?:watch\?(?:[^\s]*?&)?v=|shorts/|embed/|live/)|youtu\.be/)([A-Za-z0-9_-]{11})[^\s]*',
  caseSensitive: false,
);

/// Nhận ra tin nhắn có đường dẫn YouTube. Trả về null nếu không có. Tên video lấy từ chữ đi kèm (bỏ biểu tượng 🎬).
SharedVideo? parseSharedVideo(String content) {
  final m = _linkPattern.firstMatch(content);
  if (m == null) return null;
  final id = m.group(1)!;
  if (!_idPattern.hasMatch(id)) return null;
  var title = content
      .replaceFirst(_linkPattern, ' ')
      .replaceAll('🎬', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (title.isEmpty) title = 'Video người thân gửi';
  if (title.length > 120) title = '${title.substring(0, 120).trimRight()}…';
  return SharedVideo(id: id, title: title);
}

/// Câu Vy nói khi báo có video người thân gửi.
String sharedVideoSpeech(String hon, String from, String title) {
  final h = hon.isEmpty ? 'bác' : hon;
  final cap = '${h[0].toUpperCase()}${h.substring(1)}';
  return '$from gửi $h một video: ${cleanVideoTitle(title, maxChars: 60)}. $cap xem luôn không ạ?';
}
