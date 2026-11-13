import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Âm thanh "đang nghĩ": hai tiếng bong bóng nhẹ lặp lại đều đặn, nhỏ hơn giọng nói.
/// Hiện dần khi bắt đầu, tắt dần khi dừng. Mọi lỗi âm thanh đều bị bỏ qua (không ảnh hưởng hội thoại).
class ThinkingSound {
  static const _asset = 'assets/sounds/vy_thinking.wav';
  static const _volume = 0.45;

  AudioPlayer? _player;
  bool _loaded = false;
  bool _on = false;
  int _gen = 0;

  /// Nạp sẵn tệp để lần phát đầu không bị trễ.
  Future<void> warmUp() async {
    try {
      final p = _player ??= AudioPlayer();
      if (_loaded) return;
      await p.setAsset(_asset);
      await p.setLoopMode(LoopMode.one);
      _loaded = true;
    } catch (_) {}
  }

  Future<void> start() async {
    if (_on) return;
    _on = true;
    final gen = ++_gen;
    try {
      await warmUp();
      final p = _player;
      if (p == null || !_loaded || gen != _gen) return;
      await p.seek(Duration.zero);
      await p.setVolume(0);
      unawaited(p.play());
      for (var i = 1; i <= 6 && gen == _gen; i++) {
        await p.setVolume(_volume * i / 6);
        await Future<void>.delayed(const Duration(milliseconds: 35));
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    if (!_on) return;
    _on = false;
    final gen = ++_gen;
    try {
      final p = _player;
      if (p == null) return;
      final from = p.volume;
      for (var i = 1; i <= 4 && gen == _gen; i++) {
        await p.setVolume(from * (1 - i / 4));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      if (gen == _gen) await p.pause();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _on = false;
    _gen++;
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
