import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';

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
  ApiVideoSearch({required this.accessToken, required this.fallback, http.Client? client, String? baseUrl})
    : _http = client ?? http.Client(),
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
              headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
              body: jsonEncode({'q': query, 'limit': limit}),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final items = (jsonDecode(utf8.decode(res.bodyBytes))['items'] as List)
              .map((e) => e as Map<String, dynamic>)
              .map(
                (e) => VideoItem(
                  id: e['id'] as String,
                  title: e['title'] as String,
                  author: (e['author'] ?? '') as String,
                  thumbnailUrl: 'https://i.ytimg.com/vi/${e['id']}/mqdefault.jpg',
                  duration: e['duration'] is int ? Duration(seconds: e['duration'] as int) : null,
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
    final uri = Uri.https('www.youtube.com', '/results', {'search_query': q, 'sp': 'EgIQAQ=='});
    final res = await _http
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
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
  if (runs is List) return runs.map((r) => r is Map ? '${r['text'] ?? ''}' : '').join();
  return '';
}

VideoItem? _videoFrom(Map v) {
  final id = v['videoId'] as String;
  final title = _text(v['title']);
  if (title.isEmpty) return null;
  final author = _text(v['ownerText']).isNotEmpty ? _text(v['ownerText']) : _text(v['longBylineText']);
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
  if (parts.isEmpty || parts.any((p) => p == null) || parts.length > 3) return null;
  var secs = 0;
  for (final p in parts) {
    secs = secs * 60 + p!;
  }
  return secs == 0 ? null : Duration(seconds: secs);
}

/// Từ khoá chung chung: nên cho người dùng chọn trong danh sách thay vì tự phát kết quả đầu tiên.
/// "nhạc xưa", "tin tức", "hài" là chung chung; "Nối vòng tay lớn" là một tên bài cụ thể.
bool isVagueVideoQuery(String query) {
  final text = ' ${query.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ')} ';
  final words = text.trim().split(' ');
  if (words.length > 3) return false;
  const vague = [
    'nhạc', 'nhac', 'xưa', 'xua', 'vàng', 'vang', 'trẻ', 'tre', 'thiền', 'thien',
    'hài', 'hai', 'phim', 'tin', 'tức', 'tuc', 'cải', 'cai', 'lương', 'luong',
  ];
  // Mọi từ đều là từ chung chung (ví dụ "nhạc xưa", "tin tức", "cải lương") thì coi là mơ hồ.
  return words.every(vague.contains);
}
