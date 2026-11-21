import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../domain/voice_models.dart';

class VoiceApiException implements Exception {
  const VoiceApiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Kết quả xin giọng đọc: có audio (ElevenLabs/cache) hoặc `null` nghĩa là dùng giọng máy.
class TtsReply {
  const TtsReply(this.audio, this.reason);
  final Uint8List? audio;
  final String? reason;
}

class VoiceApi {
  VoiceApi({required this.accessToken, http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Env.apiBaseUrl;

  final String? Function() accessToken;
  final http.Client _client;
  final String _baseUrl;

  Map<String, String> _headers(String? token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  DateTime? _lastWarm;

  /// Làm ấm máy chủ giọng nói (khởi động nguội tốn 0,3-0,8 giây ở lượt đầu). Tối đa 1 lần / 3 phút, nuốt mọi lỗi.
  Future<void> warm() async {
    final now = DateTime.now();
    final last = _lastWarm;
    if (last != null && now.difference(last) < const Duration(minutes: 3)) return;
    _lastWarm = now;
    try {
      await _client
          .post(Uri.parse('$_baseUrl/api/voice/turn'), headers: {'Content-Type': 'application/json'}, body: '{"mode":"ping"}')
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Một lượt hội thoại: gửi âm thanh (hoặc chữ) + trạng thái, nhận quyết định.
  Future<VoiceTurnResult> turn({
    required String sessionId,
    required int turnNo,
    Uint8List? audio,
    String mime = 'audio/mp4',
    int durationMs = 0,
    String? text,
    required VoiceDialog dialog,
    required String screen,
    String? roomId,
    required List<VoiceContact> contacts,
    required String honorific,
    Map<String, Object?>? uiContext,
  }) async {
    final token = accessToken();
    if (_baseUrl.isEmpty)
      throw const VoiceApiException('config', 'Chưa cấu hình máy chủ');
    if (token == null)
      throw const VoiceApiException('auth', 'Phiên đăng nhập đã hết hạn');
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$_baseUrl/api/voice/turn'),
            headers: _headers(token),
            body: jsonEncode({
              'session_id': sessionId,
              'turn_no': turnNo,
              'input': audio != null
                  ? {
                      'audio_b64': base64Encode(audio),
                      'mime': mime,
                      'duration_ms': durationMs,
                    }
                  : {'text': text ?? ''},
              'state': dialog.toJson(),
              'ui': {
                'screen': screen,
                'room_id': roomId,
                'honorific': honorific,
                'contacts': [for (final c in contacts) c.toJson()],
                if (uiContext != null) 'context': uiContext,
              },
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const VoiceApiException('network', 'Không kết nối được máy chủ');
    }
    if (res.statusCode == 429)
      throw const VoiceApiException(
        'rate',
        'Bạn nói nhanh quá, chờ một chút nhé',
      );
    if (res.statusCode == 503)
      throw const VoiceApiException(
        'disabled',
        'Tính năng giọng nói đang tạm tắt',
      );
    if (res.statusCode == 401)
      throw const VoiceApiException('auth', 'Phiên đăng nhập đã hết hạn');
    if (res.statusCode != 200)
      throw const VoiceApiException('server', 'Máy chủ đang bận');
    try {
      return VoiceTurnResult.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const VoiceApiException(
        'server',
        'Máy chủ trả dữ liệu không hợp lệ',
      );
    }
  }

  /// Thử nghiệm Vy Live: gửi SDP offer, nhận SDP answer của OpenAI qua máy chủ (khoá OpenAI không xuống app).
  Future<({String sessionId, String sdp, String mode, int serverMs, int ackMs})> liveStart({
    required String sdp,
    required String liveMode,
    required String honorific,
  }) async {
    final token = accessToken();
    if (_baseUrl.isEmpty)
      throw const VoiceApiException('config', 'Chưa cấu hình máy chủ');
    if (token == null)
      throw const VoiceApiException('auth', 'Phiên đăng nhập đã hết hạn');
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$_baseUrl/api/voice/turn'),
            headers: _headers(token),
            body: jsonEncode({
              'mode': 'live_start',
              'sdp': sdp,
              'live_mode': liveMode,
              'honorific': honorific,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const VoiceApiException('network', 'Không kết nối được máy chủ');
    }
    if (res.statusCode != 201) {
      var code = '';
      var upstream = '';
      try {
        final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        code = (m['error'] as String?) ?? '';
        if (m['status'] != null) upstream = ' từ OpenAI ${m['status']}';
      } catch (_) {}
      throw VoiceApiException(
        'live_${code.isEmpty ? res.statusCode : code}',
        switch (code) {
          'live_disabled' => 'Vy Live đang tắt (bật công tắc trong trang admin)',
          'live_not_allowed' => 'Tài khoản này chưa có trong danh sách thử Live',
          'live_not_configured' => 'Chưa có key OpenAI (thêm trong trang admin)',
          'live_keys_failed' => 'Mọi key OpenAI đều đang lỗi hoặc hết hạn mức',
          'live_rate' => 'Mở Live quá nhiều lần, chờ vài phút',
          'live_busy' => 'OpenAI đang bận, thử lại sau',
          _ => 'Máy chủ từ chối (${res.statusCode}${code.isEmpty ? '' : ' $code'}$upstream)',
        },
      );
    }
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return (
        sessionId: j['session_id'] as String,
        sdp: j['sdp'] as String,
        mode: (j['mode'] as String?) ?? liveMode,
        serverMs: (j['server_ms'] as num?)?.toInt() ?? 0,
        ackMs: (j['ack_ms'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      throw const VoiceApiException('server', 'Máy chủ trả dữ liệu không hợp lệ');
    }
  }

  /// Xin giọng đọc cho một câu; lỗi/hết hạn mức → `audio == null` (app dùng giọng máy).
  Future<TtsReply> tts(String text, String sayClass) async {
    final token = accessToken();
    if (_baseUrl.isEmpty || token == null)
      return const TtsReply(null, 'no_api');
    try {
      final res = await _client
          .post(
            Uri.parse('$_baseUrl/api/voice/tts'),
            headers: _headers(token),
            body: jsonEncode({'text': text, 'class': sayClass}),
          )
          .timeout(const Duration(seconds: 9));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return TtsReply(res.bodyBytes, res.headers['x-tts-mode']);
      }
      return TtsReply(null, res.headers['x-tts-reason']);
    } catch (_) {
      return const TtsReply(null, 'network');
    }
  }
}
