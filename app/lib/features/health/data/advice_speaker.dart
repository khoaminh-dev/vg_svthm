import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Máy đọc lời khuyên sau khi đo huyết áp (giọng máy, chậm cho người lớn tuổi). Các câu đọc nối tiếp nhau.
/// Không đọc được thì im lặng: màn hình vẫn có nút xem chữ.
class AdviceSpeaker {
  AdviceSpeaker();

  FlutterTts? _tts;
  bool _ready = false;
  int _gen = 0;
  Future<void> _chain = Future.value();

  Future<FlutterTts?> _engine() async {
    if (_ready) return _tts;
    try {
      final t = FlutterTts();
      await t.setLanguage('vi-VN');
      await t.setSpeechRate(0.42);
      await t.setPitch(1.0);
      await t.awaitSpeakCompletion(true);
      _tts = t;
    } catch (_) {
      _tts = null;
    }
    _ready = true;
    return _tts;
  }

  /// Đọc [text] sau các câu đang đọc dở (xếp hàng). [stop] sẽ ngắt cả hàng.
  Future<void> say(String text) {
    final gen = _gen;
    final line = text.trim();
    if (line.isEmpty) return _chain;
    _chain = _chain.then((_) async {
      if (gen != _gen) return;
      try {
        final t = await _engine();
        if (gen != _gen) return;
        await t?.speak(line);
      } catch (_) {}
    });
    return _chain;
  }

  /// Đọc lại từ đầu: ngắt những gì đang đọc rồi đọc [text].
  Future<void> replace(String text) async {
    await stop();
    return say(text);
  }

  Future<void> stop() async {
    _gen++;
    _chain = Future.value();
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

final adviceSpeakerProvider = Provider<AdviceSpeaker>((ref) {
  final s = AdviceSpeaker();
  ref.onDispose(() => unawaited(s.stop()));
  return s;
});

/// Công tắc "Đọc lời khuyên sau khi đo" (bảng `voice_prefs`, mặc định bật). Lỗi mạng thì coi như bật.
class SpeakAdviceNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    try {
      final c = ref.read(supabaseClientProvider);
      final uid = c.auth.currentUser?.id;
      if (uid == null) return true;
      final row = await c
          .from('voice_prefs')
          .select('speak_advice')
          .eq('user_id', uid)
          .maybeSingle();
      return row?['speak_advice'] as bool? ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> set(bool value) async {
    final before = state;
    state = AsyncData(value);
    try {
      final c = ref.read(supabaseClientProvider);
      final uid = c.auth.currentUser?.id;
      if (uid == null) return;
      await c.from('voice_prefs').upsert({
        'user_id': uid,
        'speak_advice': value,
      });
    } catch (_) {
      state = before; // không lưu được thì trả công tắc về như cũ
    }
  }
}

final speakAdviceProvider = AsyncNotifierProvider<SpeakAdviceNotifier, bool>(
  SpeakAdviceNotifier.new,
);
