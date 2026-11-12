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
  }) async {
    final token = accessToken();
    if (_baseUrl.isEmpty) throw const VoiceApiException('config', 'Chưa cấu hình máy chủ');
    if (token == null) throw const VoiceApiException('auth', 'Phiên đăng nhập đã hết hạn');
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
                  ? {'audio_b64': base64Encode(audio), 'mime': mime, 'duration_ms': durationMs}
                  : {'text': text ?? ''},
              'state': dialog.toJson(),
              'ui': {
                'screen': screen,
                'room_id': roomId,
                'honorific': honorific,
                'contacts': [for (final c in contacts) c.toJson()],
              },
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const VoiceApiException('network', 'Không kết nối được máy chủ');
    }
    if (res.statusCode == 429) throw const VoiceApiException('rate', 'Bạn nói nhanh quá, chờ một chút nhé');
    if (res.statusCode == 503) throw const VoiceApiException('disabled', 'Tính năng giọng nói đang tạm tắt');
    if (res.statusCode == 401) throw const VoiceApiException('auth', 'Phiên đăng nhập đã hết hạn');
    if (res.statusCode != 200) throw const VoiceApiException('server', 'Máy chủ đang bận');
    try {
      return VoiceTurnResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    } catch (_) {
      throw const VoiceApiException('server', 'Máy chủ trả dữ liệu không hợp lệ');
    }
  }

  /// Xin giọng đọc cho một câu; lỗi/hết hạn mức → `audio == null` (app dùng giọng máy).
  Future<TtsReply> tts(String text, String sayClass) async {
    final token = accessToken();
    if (_baseUrl.isEmpty || token == null) return const TtsReply(null, 'no_api');
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
