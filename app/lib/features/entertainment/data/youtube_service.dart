import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../../voice/live/live_hybrid.dart' show foldVi;

/// Một video trong kết quả tìm kiếm.
class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    this.duration,
  });

  final String id;
  final String title;
  final String author;
  final String thumbnailUrl;
  final Duration? duration;

  String get watchUrl => 'https://www.youtube.com/watch?v=$id';

  /// Dạng 3:45 hoặc 1:02:10; rỗng nếu không rõ (video trực tiếp).
  String get durationLabel {
    final d = duration;
    if (d == null || d == Duration.zero) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}

/// Tìm video YouTube không cần khoá API (qua youtube_explode_dart, chạy ngay trên điện thoại).
abstract interface class VideoSearch {
  Future<List<VideoItem>> search(String query, {int limit = 12});
}

/// Tìm qua máy chủ Viegrand (YouTube Data API, khoá nằm ở server); lỗi hoặc hết hạn mức thì quay về [fallback].
class ApiVideoSearch implements VideoSearch {
  ApiVideoSearch({
    required this.accessToken,
    required this.fallback,
    http.Client? client,
    String? baseUrl,
  }) : _http = client ?? http.Client(),
       _baseUrl = baseUrl ?? Env.apiBaseUrl;

  final String? Function() accessToken;
  final VideoSearch fallback;
  final http.Client _http;
  final String _baseUrl;

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async {
    final token = accessToken();
    if (_baseUrl.isNotEmpty && token != null) {
      try {
        final res = await _http
            .post(
              Uri.parse('$_baseUrl/api/youtube'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'q': query, 'limit': limit}),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final items =
              (jsonDecode(utf8.decode(res.bodyBytes))['items'] as List)
                  .map((e) => e as Map<String, dynamic>)
                  .map(
                    (e) => VideoItem(
                      id: e['id'] as String,
                      title: e['title'] as String,
                      author: (e['author'] ?? '') as String,
                      thumbnailUrl:
                          'https://i.ytimg.com/vi/${e['id']}/mqdefault.jpg',
                      duration: e['duration'] is int
                          ? Duration(seconds: e['duration'] as int)
                          : null,
                    ),
                  )
                  .toList();
          if (items.isNotEmpty) return items;
        }
      } catch (_) {
        // Rơi xuống cách dự phòng.
      }
    }
    return fallback.search(query, limit: limit);
  }
}

/// Nhớ kết quả vài phút để một lệnh giọng chỉ tốn MỘT lần tìm (Vy tìm rồi màn Giải trí tìm lại cùng từ khoá).
/// Khoá theo từ khoá đã chuẩn hoá; yêu cầu ít hơn số đang có thì cắt bớt, nhiều hơn thì tìm lại.
class CachedVideoSearch implements VideoSearch {
  CachedVideoSearch(
    this._inner, {
    this.ttl = const Duration(minutes: 20),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final VideoSearch _inner;
  final Duration ttl;
  final DateTime Function() _now;
  final _cache = <String, ({DateTime at, int limit, List<VideoItem> items})>{};

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async {
    final key = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < ttl && hit.limit >= limit) {
      return hit.items.length > limit ? hit.items.sublist(0, limit) : hit.items;
    }
    final items = await _inner.search(query, limit: limit);
    // Không nhớ kết quả rỗng: lần sau cho tìm lại.
    if (items.isNotEmpty) {
      if (_cache.length >= 40) _cache.remove(_cache.keys.first);
      _cache[key] = (at: _now(), limit: limit, items: items);
    }
    return items;
  }
}

/// Tên video để Vy ĐỌC: bỏ emoji, #thẻ, "(Official MV 4K)", "[Lyrics]"... rồi cắt gọn ở ranh giới từ.
String cleanVideoTitle(String title, {int maxChars = 60}) {
  var t = title
      .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}\u{2190}-\u{2BFF}\u{FE0F}\u{200D}]', unicode: true), ' ')
      .replaceAll(RegExp(r'#\S+'), ' ');
  // Chỉ bỏ ngoặc chứa chữ "nhãn kỹ thuật"; ngoặc có tên người/vở diễn (ví dụ "(Lệ Thủy)") thì giữ.
  final noise = RegExp(
    r'official|\bmv\b|m/v|\bhd\b|\b4k\b|\b8k\b|1080p|720p|lyric|audio|karaoke|\bhq\b|full hd|video clip|clip',
    caseSensitive: false,
  );
  t = t.replaceAllMapped(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), (m) => noise.hasMatch(m[0]!) ? ' ' : m[0]!);
  t = t.replaceAll(RegExp(r'\s*[|•·]+\s*'), ' - ').replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll(RegExp(r'^[\s\-–—:]+|[\s\-–—:]+$'), '');
  if (t.isEmpty) t = title.trim();
  if (t.length <= maxChars) return t;
  final cut = t.substring(0, maxChars);
  final sp = cut.lastIndexOf(' ');
  return '${(sp > maxChars ~/ 2 ? cut.substring(0, sp) : cut).trimRight()}…';
}

class YoutubeExplodeSearch implements VideoSearch {
  YoutubeExplodeSearch({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    Object? last;
    // YouTube thỉnh thoảng trả trang thiếu dữ liệu: thử lại vài lần trước khi báo lỗi.
    for (var i = 0; i < 3; i++) {
      try {
        final items = await _fetch(q, limit);
        if (items.isNotEmpty) return items;
        last = StateError('empty');
      } catch (e) {
        last = e;
      }
    }
    throw last ?? StateError('search failed');
  }

  Future<List<VideoItem>> _fetch(String q, int limit) async {
    final uri = Uri.https('www.youtube.com', '/results', {
      'search_query': q,
      'sp': 'EgIQAQ==',
    });
    final res = await _http
        .get(
          uri,
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
            'Accept-Language': 'vi-VN,vi;q=0.9',
            'Cookie': 'CONSENT=YES+1; SOCS=CAI',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw StateError('YouTube ${res.statusCode}');
    return parseSearchHtml(utf8.decode(res.bodyBytes), limit: limit);
  }
}

/// Lấy danh sách video từ HTML trang kết quả YouTube (đọc lỏng tay: thiếu trường nào bỏ trường đó).
List<VideoItem> parseSearchHtml(String html, {int limit = 12}) {
  final start = html.indexOf('ytInitialData = ');
  if (start < 0) throw StateError('no data');
  final from = html.indexOf('{', start);
  final end = html.indexOf(';</script>', from);
  if (from < 0 || end < 0) throw StateError('no data');
  final data = jsonDecode(html.substring(from, end));
  final out = <VideoItem>[];
  void walk(Object? n) {
    if (out.length >= limit) return;
    if (n is Map) {
      final v = n['videoRenderer'];
      if (v is Map && v['videoId'] is String) {
        final item = _videoFrom(v);
        if (item != null) out.add(item);
      } else {
        n.values.forEach(walk);
      }
    } else if (n is List) {
      n.forEach(walk);
    }
  }

  walk(data);
  return out;
}

String _text(Object? o) {
  if (o is! Map) return '';
  final t = o['simpleText'];
  if (t is String) return t;
  final runs = o['runs'];
  if (runs is List)
    return runs.map((r) => r is Map ? '${r['text'] ?? ''}' : '').join();
  return '';
}

VideoItem? _videoFrom(Map v) {
  final id = v['videoId'] as String;
  final title = _text(v['title']);
  if (title.isEmpty) return null;
  final author = _text(v['ownerText']).isNotEmpty
      ? _text(v['ownerText'])
      : _text(v['longBylineText']);
  return VideoItem(
    id: id,
    title: title,
    author: author,
    thumbnailUrl: 'https://i.ytimg.com/vi/$id/mqdefault.jpg',
    duration: _parseDuration(_text(v['lengthText'])),
  );
}

/// "3:45" hoặc "1:02:10" thành Duration; rỗng/không hiểu thì null.
Duration? _parseDuration(String s) {
  final parts = s.split(':').map(int.tryParse).toList();
  if (parts.isEmpty || parts.any((p) => p == null) || parts.length > 3)
    return null;
  var secs = 0;
  for (final p in parts) {
    secs = secs * 60 + p!;
  }
  return secs == 0 ? null : Duration(seconds: secs);
}

/// Từ khoá chung chung: nên cho người dùng chọn trong danh sách thay vì tự phát kết quả đầu tiên.
/// "nhạc xưa", "tin tức", "hài" là chung chung; "Nối vòng tay lớn" là một tên bài cụ thể.
bool isVagueVideoQuery(String query) {
  final words = foldVi(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty || words.length > 3) return false;
  // Mọi từ đều là từ chỉ thể loại/chủ đề (đã bỏ dấu) thì coi là mơ hồ.
  const vague = {
    'nhac', 'xua', 'vang', 'tre', 'thien', 'hai', 'phim', 'tin', 'tuc', 'cai', 'luong', 'bolero', 'que', 'huong',
    'cach', 'mang', 'thieu', 'nhi', 'khong', 'loi', 'ru', 'ngu', 'nhe', 'tru', 'tinh', 'kinh', 'phat', 'truyen',
    'dem', 'khuya', 'duong', 'sinh', 'bong', 'da', 'tuong', 'cheo', 'co', 'the', 'duc', 'sach', 'noi', 'dai',
    'radio', 'karaoke', 'hoat', 'hinh', 'yoga', 'thu', 'gian', 'kich', 'kenh',
  };
  return words.every(vague.contains);
}
