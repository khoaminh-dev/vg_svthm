import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/vy_sounds.dart';

/// Cài đặt của người dùng cho Vy (lưu trên máy).
class VySettings {
  const VySettings({
    this.captions = true,
    this.sounds = true,
    this.introSeen = false,
  });

  /// Hiện chữ khi Vy nói (cho người nghe kém hoặc nơi ồn). Mặc định bật.
  final bool captions;

  /// Tiếng "ting" khi bật/tắt Vy.
  final bool sounds;

  /// Đã xem thẻ giải thích lần đầu.
  final bool introSeen;

  VySettings copyWith({bool? captions, bool? sounds, bool? introSeen}) =>
      VySettings(
        captions: captions ?? this.captions,
        sounds: sounds ?? this.sounds,
        introSeen: introSeen ?? this.introSeen,
      );
}

class VySettingsNotifier extends AsyncNotifier<VySettings> {
  static const _kCaptions = 'vy_captions';
  static const _kSounds = 'vy_sounds';
  static const _kIntro = 'vy_intro_seen';

  @override
  Future<VySettings> build() async {
    final p = await SharedPreferences.getInstance();
    final s = VySettings(
      captions: p.getBool(_kCaptions) ?? true,
      sounds: p.getBool(_kSounds) ?? true,
      introSeen: p.getBool(_kIntro) ?? false,
    );
    VySounds.enabled = s.sounds;
    return s;
  }

  VySettings get _now => state.value ?? const VySettings();

  Future<void> setCaptions(bool v) async {
    state = AsyncData(_now.copyWith(captions: v));
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCaptions, v);
  }

  Future<void> setSounds(bool v) async {
    VySounds.enabled = v;
    state = AsyncData(_now.copyWith(sounds: v));
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSounds, v);
  }

  Future<void> markIntroSeen() async {
    if (_now.introSeen) return;
    state = AsyncData(_now.copyWith(introSeen: true));
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kIntro, true);
  }
}

final vySettingsProvider =
    AsyncNotifierProvider<VySettingsNotifier, VySettings>(
      VySettingsNotifier.new,
    );
