import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/vy_sounds.dart';

/// Cài đặt của người dùng cho Vy (lưu trên máy).
class VySettings {
  const VySettings({
    this.captions = true,
    this.sounds = true,
    this.introSeen = false,
    this.remindDose = true,
    this.remindBp = true,
    this.remindMessages = true,
    this.textInput = false,
    this.rememberMedia = true,
    this.remindMedia = true,
  });

  /// "Vy gợi ý nhạc, video quen nghe" đúng giờ quen (tối đa một lần mỗi buổi). Mặc định bật; tắt bằng "đừng gợi ý nữa".
  final bool remindMedia;

  /// "Nhớ những gì tôi đã nghe/xem" để lần sau Vy mở đúng ý (lịch sử nằm trên máy, xoá được). Mặc định bật.
  final bool rememberMedia;

  /// Hiện chữ khi Vy nói (cho người nghe kém hoặc nơi ồn). Mặc định bật.
  final bool captions;

  /// Tiếng "ting" khi bật/tắt Vy.
  final bool sounds;

  /// Đã xem thẻ giải thích lần đầu.
  final bool introSeen;

  /// "Vy tự nhắc" từng loại (bật sẵn): đến giờ uống thuốc, đo huyết áp, tin nhắn mới.
  final bool remindDose;
  final bool remindBp;
  final bool remindMessages;

  /// Ô gõ chữ cho Vy trên panel (cho người nghe kém, nơi ồn, hoặc để thử). Mặc định TẮT cho gọn với người cao tuổi.
  final bool textInput;

  VySettings copyWith({
    bool? captions,
    bool? sounds,
    bool? introSeen,
    bool? remindDose,
    bool? remindBp,
    bool? remindMessages,
    bool? textInput,
    bool? rememberMedia,
    bool? remindMedia,
  }) => VySettings(
    rememberMedia: rememberMedia ?? this.rememberMedia,
    remindMedia: remindMedia ?? this.remindMedia,
    captions: captions ?? this.captions,
    sounds: sounds ?? this.sounds,
    introSeen: introSeen ?? this.introSeen,
    remindDose: remindDose ?? this.remindDose,
    remindBp: remindBp ?? this.remindBp,
    remindMessages: remindMessages ?? this.remindMessages,
    textInput: textInput ?? this.textInput,
  );
}

class VySettingsNotifier extends AsyncNotifier<VySettings> {
  static const _kCaptions = 'vy_captions';
  static const _kSounds = 'vy_sounds';
  static const _kIntro = 'vy_intro_seen';
  static const _kRDose = 'vy_remind_dose';
  static const _kRBp = 'vy_remind_bp';
  static const _kRMsg = 'vy_remind_msg';
  static const _kText = 'vy_text_input';
  static const _kMedia = 'vy_remember_media';
  static const _kRMedia = 'vy_remind_media';

  @override
  Future<VySettings> build() async {
    final p = await SharedPreferences.getInstance();
    final s = VySettings(
      captions: p.getBool(_kCaptions) ?? true,
      sounds: p.getBool(_kSounds) ?? true,
      introSeen: p.getBool(_kIntro) ?? false,
      remindDose: p.getBool(_kRDose) ?? true,
      remindBp: p.getBool(_kRBp) ?? true,
      remindMessages: p.getBool(_kRMsg) ?? true,
      textInput: p.getBool(_kText) ?? false,
      rememberMedia: p.getBool(_kMedia) ?? true,
      remindMedia: p.getBool(_kRMedia) ?? true,
    );
    VySounds.enabled = s.sounds;
    return s;
  }

  Future<void> setRememberMedia(bool v) async {
    state = AsyncData(_now.copyWith(rememberMedia: v));
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kMedia, v);
  }

  VySettings get _now => state.value ?? const VySettings();

  Future<void> setCaptions(bool v) async {
    state = AsyncData(_now.copyWith(captions: v));
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCaptions, v);
  }

  Future<void> setTextInput(bool v) async {
    state = AsyncData(_now.copyWith(textInput: v));
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kText, v);
  }

  Future<void> setSounds(bool v) async {
    VySounds.enabled = v;
    state = AsyncData(_now.copyWith(sounds: v));
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSounds, v);
  }

  Future<void> setRemind({bool? dose, bool? bp, bool? messages, bool? media}) async {
    state = AsyncData(_now.copyWith(remindDose: dose, remindBp: bp, remindMessages: messages, remindMedia: media));
    final p = await SharedPreferences.getInstance();
    if (media != null) await p.setBool(_kRMedia, media);
    if (dose != null) await p.setBool(_kRDose, dose);
    if (bp != null) await p.setBool(_kRBp, bp);
    if (messages != null) await p.setBool(_kRMsg, messages);
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
