import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'voice_api.dart';

/// Đọc câu trả lời. Hiện mặc định dùng giọng máy (flutter_tts) cho mọi câu để phản hồi nhanh nhất.
/// Đặt [serverVoice] = true để bật lại đường ElevenLabs/cache từ máy chủ (thêm một vòng mạng trước khi đọc).
class SpeechPlayer {
  SpeechPlayer(this._api) {
    unawaited(_initTts()); // khởi tạo sớm để câu đầu tiên không bị trễ
  }

  /// Tạm tắt giọng từ máy chủ cho tới khi có giải pháp giọng tốt hơn.
  static const bool serverVoice = false;

  final VoiceApi _api;
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;
  int _gen = 0;

  /// Cache nhỏ trong bộ nhớ để câu lặp lại (cùng nội dung) không gọi lại máy chủ trong một phiên.
  final _memo = <String, Uint8List>{};

  Future<void> _initTts() async {
    if (_ttsReady) return;
    try {
      await _tts.setLanguage('vi-VN');
      await _tts.setSpeechRate(0.42); // chậm hơn mặc định cho người lớn tuổi
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
    _ttsReady = true;
  }

  /// Đọc [text] và chờ đọc xong (hoặc bị [stop] ngắt). Trả về `true` nếu đọc bằng giọng server.
  Future<bool> speak(String text, {String sayClass = 'other'}) async {
    if (text.trim().isEmpty) return false;
    final gen = ++_gen;
    await _stopInternal();
    var usedServer = false;
    try {
      Uint8List? audio = serverVoice ? _memo[text] : null;
      if (serverVoice && audio == null) {
        final r = await _api.tts(text, sayClass);
        audio = r.audio;
        if (audio != null && _memo.length < 20) _memo[text] = audio;
      }
      if (gen != _gen) return false;
      if (audio != null) {
        usedServer = await _playBytes(audio, gen);
        if (usedServer) return true;
      }
      if (gen != _gen) return false;
      await _initTts();
      await _tts.speak(text);
    } catch (_) {
      // Không đọc được thì thôi: màn hình vẫn hiển thị chữ.
    }
    return usedServer;
  }

  Future<bool> _playBytes(Uint8List audio, int gen) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/vg_tts_${audio.length}_${audio.hashCode}.mp3');
      if (!await f.exists()) await f.writeAsBytes(audio, flush: true);
      await _player.setFilePath(f.path);
      if (gen != _gen) return false;
      await _player.play(); // hoàn tất khi phát xong hoặc bị dừng
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopInternal() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Ngắt ngay (người dùng bấm mic để nói chen vào).
  Future<void> stop() async {
    _gen++;
    await _stopInternal();
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
