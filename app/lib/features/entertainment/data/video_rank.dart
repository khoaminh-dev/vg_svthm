import '../../voice/live/live_hybrid.dart' show foldVi;
import 'media_curation.dart';
import 'youtube_service.dart';

/// Chọn video thông minh hơn "lấy kết quả đầu của YouTube" (kế hoạch docs/KE_HOACH_VY_GIAI_TRI.md mục 5.2):
/// bỏ Shorts, video quá ngắn/quá dài so với điều người dùng muốn, bản karaoke/cover/remix khi không xin,
/// loại trùng, rồi xếp theo độ khớp tiêu đề. Chạy trên máy nên dùng được cho cả đường máy chủ lẫn đường dự phòng.

enum VideoKind {
  /// Một bài hát (hoặc tên ca sĩ): vài phút.
  song,

  /// Vở diễn, phim, truyện, kinh, tin tức, thiền, tập luyện: dài là bình thường.
  long,

  /// Chưa biết: chỉ bỏ Shorts và video quá ngắn.
  any,
}

const _longTopics = [
  'cai luong', 'tuong', 'cheo', 'phim', 'truyen', 'sach noi', 'kinh', 'thien', 'duong sinh', 'the duc', 'yoga',
  'thai cuc', 'tin tuc', 'thoi su', 'ban tin', 'bong da', 'hai', 'hai kich', 'tieu pham', 'radio', 'dai phat thanh',
  'nau an', 'hoat hinh', 'karaoke', 'v league', 'ngoai hang anh', 'world cup',
];

/// Từ chỉ thể loại/mô tả, không phải tên bài hay ca sĩ: truy vấn chỉ gồm các từ này thì là "nghe nhạc theo thể loại".
const _genreWords = {
  'nhac', 'xua', 'vang', 'tru', 'tinh', 'bolero', 'que', 'huong', 'cach', 'mang', 'thieu', 'nhi', 'khong', 'loi',
  'ru', 'ngu', 'thien', 'nhe', 'nhang', 'thu', 'gian', 'hay', 'nhat', 'tuyen', 'chon', 'lien', 'khuc', 'bai', 'hat',
  'piano', 'guitar', 'hoa', 'tau', 'de', 'cho', 'loc',
};

const _stopWords = {
  'nhac', 'bai', 'hat', 'video', 'clip', 'xem', 'nghe', 'mo', 'cho', 'cua', 'va', 'la', 'cai', 'mot', 'nhung',
  'hay', 'nhat', 'tuyen', 'chon', 'loc', 'hom', 'nay',
};

VideoKind inferVideoKind(String query) {
  final f = ' ${foldVi(query)} ';
  for (final t in _longTopics) {
    if (f.contains(' $t ')) return VideoKind.long;
  }
  if (RegExp(r' (nhac|bai|hat|ca khuc|bolero) ').hasMatch(f)) return VideoKind.song;
  return VideoKind.any;
}

/// Truy vấn chỉ nói thể loại nhạc ("nhạc xưa", "nhạc vàng"), chưa nêu bài hay ca sĩ.
bool isGenericMusicQuery(String query) {
  final words = foldVi(query).split(' ').where((w) => w.isNotEmpty);
  return words.isNotEmpty && words.every(_genreWords.contains);
}

/// Mở rộng nhẹ vài từ khoá chung chung để YouTube trả về bản tuyển chọn dài, hợp phát liên tục.
/// Từ khoá cụ thể (tên bài, ca sĩ) giữ nguyên.
String refineVideoQuery(String query) {
  const map = {
    'tin tuc': 'tin tức hôm nay',
    'thoi su': 'tin tức hôm nay',
    'thien': 'thiền thư giãn',
    'hai': 'hài kịch tiểu phẩm',
    'hai kich': 'hài kịch tiểu phẩm',
    'duong sinh': 'bài tập dưỡng sinh người lớn tuổi',
    'bong da': 'bóng đá highlights',
    'nhac xua': 'nhạc xưa tuyển chọn',
    'nhac vang': 'nhạc vàng tuyển chọn',
    'nhac tru tinh': 'nhạc trữ tình tuyển chọn',
    'bolero': 'bolero tuyển chọn',
    'cai luong': 'cải lương hay nhất',
    'nhac khong loi': 'nhạc không lời thư giãn',
    'nhac ru ngu': 'nhạc ru ngủ nhẹ nhàng',
    'truyen dem khuya': 'truyện đêm khuya đọc',
  };
  return map[foldVi(query)] ?? query;
}

/// Hẹn giờ tắt mặc định (phút) cho yêu cầu để ngủ ("nhạc ru ngủ", "mở gì cho dễ ngủ"); null nếu không phải. Mặc định đã duyệt: 30 phút.
int? defaultSleepMinutesFor(String query) {
  final f = ' ${foldVi(query)} ';
  return (f.contains(' ru ngu ') || f.contains(' de ngu ') || f.contains(' ngu ngon ')) ? 30 : null;
}

final _noisy = RegExp(r'\b(karaoke|beat|instrumental|remix|cover|reaction|nhac chuong|nhac cho|dj|tutorial|huong dan)\b');
final _shorts = RegExp(r'(#shorts?\b|\bshorts?\b)');

/// Xếp lại danh sách video theo mức hợp ý. Không bao giờ trả rỗng nếu đầu vào có video (lọc quá tay thì lùi về bản chỉ bỏ Shorts).
List<VideoItem> rankVideos(
  List<VideoItem> items,
  String query, {
  int? limit,
  Set<String> excluded = const {},
  Set<String> liked = const {},
}) {
  final health = isHealthQuery(query);
  final news = isNewsQuery(query);
  final kind = inferVideoKind(query);
  final generic = kind == VideoKind.song && isGenericMusicQuery(query);
  final qf = foldVi(query);
  final tokens = qf.split(' ').where((w) => w.length > 1 && !_stopWords.contains(w)).toList();
  final wantsShorts = qf.contains('shorts');

  bool isShort(VideoItem v) => !wantsShorts && _shorts.hasMatch(v.title.toLowerCase());

  ({double score, bool ok}) judge(VideoItem v, int index) {
    final title = foldVi(v.title);
    final author = foldVi(v.author);
    final secs = v.duration?.inSeconds;
    var ok = !isShort(v) && !excluded.contains(v.id);
    // Sức khoẻ: bỏ video hứa chữa khỏi/khuyên bỏ thuốc; khi đã có danh sách duyệt (healthStrictAllowlist) chỉ lấy nguồn tin cậy.
    if (health) {
      if (hasRiskyHealthClaim(v.title)) ok = false;
      if (healthStrictAllowlist && !isTrustedHealthSource(v.title, v.author)) ok = false;
    }
    if (secs == null) {
      if (kind == VideoKind.song) ok = false;
    } else {
      final (min, max) = switch (kind) {
        VideoKind.song => generic ? (120, 10800) : (90, 3600),
        VideoKind.long => (120, 43200),
        VideoKind.any => (30, 43200),
      };
      if (secs < min || secs > max) ok = false;
    }
    var score = -0.05 * index;
    if (tokens.isNotEmpty) {
      final hit = tokens.where((t) => title.contains(t) || author.contains(t)).length;
      score += 3 * hit / tokens.length;
    }
    if (_noisy.hasMatch(title)) {
      final asked = _noisy.allMatches(title).any((m) => qf.contains(m[0]!));
      if (!asked) score -= 3;
    }
    if (title.contains('official') || author.contains('official') || author.contains('vevo')) score += 0.5;
    if (liked.contains(v.id)) score += 2; // bài người dùng đã bảo hay
    if (health && isTrustedHealthSource(v.title, v.author)) score += 2;
    if (news && isTrustedNewsSource(v.author)) score += 2;
    if (secs != null) {
      if (generic && secs >= 900) score += 1.5; // bản tuyển chọn dài hợp nghe liên tục
      if (kind == VideoKind.song && !generic && secs >= 120 && secs <= 480) score += 0.5;
    }
    return (score: score, ok: ok);
  }

  final seen = <String>{};
  final scored = <({VideoItem v, double score})>[];
  for (var i = 0; i < items.length; i++) {
    final j = judge(items[i], i);
    if (!j.ok) continue;
    final key = foldVi(cleanVideoTitle(items[i].title, maxChars: 200));
    if (!seen.add(key)) continue;
    scored.add((v: items[i], score: j.score));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  var out = [for (final s in scored) s.v];
  // Lọc quá tay thì lùi về bản chỉ bỏ Shorts, nhưng KHÔNG BAO GIỜ lùi qua video đã bị chê hoặc video sức khoẻ nguy hiểm.
  bool safe(VideoItem v) =>
      !excluded.contains(v.id) &&
      !(health && (hasRiskyHealthClaim(v.title) || (healthStrictAllowlist && !isTrustedHealthSource(v.title, v.author))));
  if (out.isEmpty) out = items.where((v) => !isShort(v) && safe(v)).toList();
  if (out.isEmpty) out = items.where(safe).toList();
  return limit != null && out.length > limit ? out.sublist(0, limit) : out;
}

/// Khoá tên để so trùng (bỏ dấu, bỏ nhãn kỹ thuật).
String videoTitleKey(String title) => foldVi(cleanVideoTitle(title, maxChars: 200));

/// Tìm rồi xếp lại: xin nhiều hơn số cần (tối đa 20) để còn có chỗ lọc.
class RankedVideoSearch implements VideoSearch {
  /// [excluded] = bài người dùng đã chê (không bao giờ mở lại); [liked] = bài người dùng đã khen (được ưu tiên).
  RankedVideoSearch(this._inner, {Set<String> Function()? excluded, Set<String> Function()? liked})
    : _excluded = excluded,
      _liked = liked;

  final VideoSearch _inner;
  final Set<String> Function()? _excluded;
  final Set<String> Function()? _liked;

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async {
    final raw = await _inner.search(refineVideoQuery(query), limit: 20);
    return rankVideos(raw, query, limit: limit, excluded: _excluded?.call() ?? const {}, liked: _liked?.call() ?? const {});
  }
}

/// Lấy thêm video cho hàng đợi khi sắp hết: thử các cách nói khác của cùng chủ đề, bỏ video đã có.
/// [step] là cách nói đã thử tới đâu; trả về [step] mới để lần sau thử cách kế tiếp.
Future<({List<VideoItem> items, int step})> nextBatch({
  required VideoSearch search,
  required String topic,
  required Set<String> have,
  Set<String> haveTitles = const {},
  int step = 0,
  int limit = 12,
}) async {
  final variants = [topic, '$topic hay nhất', '$topic liên khúc', '$topic mới nhất'];
  final seenTitles = {...haveTitles};
  for (var i = step; i < variants.length; i++) {
    final found = await search.search(variants[i], limit: 20);
    final fresh = <VideoItem>[];
    for (final v in found) {
      if (have.contains(v.id)) continue;
      final key = foldVi(cleanVideoTitle(v.title, maxChars: 200));
      if (!seenTitles.add(key)) continue;
      fresh.add(v);
    }
    if (fresh.isNotEmpty) {
      return (items: fresh.length > limit ? fresh.sublist(0, limit) : fresh, step: i + 1);
    }
  }
  return (items: const <VideoItem>[], step: variants.length);
}
