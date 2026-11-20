import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Âm thanh bật/tắt/xong việc của Vy: nốt thuỷ tinh ngắn, nhỏ hơn giọng nói.
/// Phát ngay lúc chạm (trước khi kết nối xong). Mọi lỗi âm thanh đều bị bỏ qua.
class VySounds {
  VySounds._();

  static final _players = <String, AudioPlayer>{};
  static bool enabled = true;

  static Future<void> _play(String asset, double volume) async {
    if (!enabled) return;
    try {
      final p = _players[asset] ??= AudioPlayer();
      await p.setAsset(asset);
      await p.setVolume(volume);
      await p.seek(Duration.zero);
      unawaited(p.play());
    } catch (_) {}
  }

  static Future<void> on() => _play('assets/sounds/vy_on.wav', 0.5);
  static Future<void> off() => _play('assets/sounds/vy_off.wav', 0.5);
  static Future<void> done() => _play('assets/sounds/vy_done.wav', 0.4);
}
