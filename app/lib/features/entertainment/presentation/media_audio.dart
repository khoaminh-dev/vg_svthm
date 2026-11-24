import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../voice/core/vy_card.dart';
import '../../voice/core/vy_core.dart';
import '../../voice/core/vy_view.dart';

/// Nhạc/video phải nhường chỗ cho Vy và cho việc quan trọng (kế hoạch docs/KE_HOACH_VY_GIAI_TRI.md mục 5.6,
/// ưu tiên âm thanh đã chốt 20/11: SOS > nhắc thuốc > cuộc gọi > nhắc đo > Vy nói > nhạc).
enum MediaAudio {
  /// Phát bình thường ở âm lượng người dùng chọn.
  normal,

  /// Hạ nhỏ để micro không thu nhầm tiếng video và để nghe rõ Vy.
  duck,

  /// Tạm dừng (Vy nói dài); khi xong thì tự phát tiếp.
  pause,

  /// Dừng hẳn và KHÔNG tự phát tiếp (SOS, khẩn cấp): người dùng phải nói "tiếp tục".
  stop,
}

/// Các lý do khác (ngoài Vy) đang chiếm âm thanh. Hiện có: `sos` (màn SOS đang mở).
class MediaInterruptsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String reason) {
    if (!state.contains(reason)) state = {...state, reason};
  }

  void remove(String reason) {
    if (state.contains(reason)) state = {...state}..remove(reason);
  }
}

final mediaInterruptsProvider = NotifierProvider<MediaInterruptsNotifier, Set<String>>(MediaInterruptsNotifier.new);

/// Quy tắc thuần: chế độ âm thanh của trình phát theo trạng thái Vy và các lý do khác.
MediaAudio mediaAudioFor(VyView v, Set<String> interrupts) {
  if (interrupts.contains('sos')) return MediaAudio.stop;
  if (!v.isOpen) return MediaAudio.normal;
  if (v.phase == VyPhase.emergency || v.card is SosCard) return MediaAudio.stop;
  if (v.phase == VyPhase.closing) return MediaAudio.normal;
  // Vy đang mở: micro mở hoặc Vy sắp/đang nói, nên hạ tiếng video.
  return MediaAudio.duck;
}

/// Vy thường nói liên tục quá lâu (đọc tin, đọc danh sách) thì tạm dừng hẳn thay vì chỉ hạ tiếng.
const longSpeechAfter = Duration(seconds: 8);

class MediaAudioNotifier extends Notifier<MediaAudio> {
  Timer? _longSpeech;

  @override
  MediaAudio build() {
    ref.onDispose(() => _longSpeech?.cancel());
    ref.listen<VyView>(vyCoreProvider, (_, _) => _recompute());
    ref.listen<Set<String>>(mediaInterruptsProvider, (_, _) => _recompute());
    return _compute();
  }

  MediaAudio _compute() => mediaAudioFor(ref.read(vyCoreProvider), ref.read(mediaInterruptsProvider));

  void _recompute() {
    final v = ref.read(vyCoreProvider);
    final base = _compute();
    final speaking = base == MediaAudio.duck && v.engine == VyEngine.classic && v.phase == VyPhase.speaking;
    if (!speaking) {
      _longSpeech?.cancel();
      _longSpeech = null;
      state = base;
      return;
    }
    state = base;
    _longSpeech ??= Timer(longSpeechAfter, () {
      _longSpeech = null;
      final now = ref.read(vyCoreProvider);
      if (now.engine == VyEngine.classic && now.phase == VyPhase.speaking && state == MediaAudio.duck) {
        state = MediaAudio.pause;
      }
    });
  }
}

final mediaAudioProvider = NotifierProvider.autoDispose<MediaAudioNotifier, MediaAudio>(MediaAudioNotifier.new);

/// Việc cần làm với trình phát khi chế độ đổi.
enum MixOp { duckVolume, restoreVolume, pause, play }

/// Chuyển chế độ âm thanh: trả về các việc cần làm và cờ "mình đã tạm dừng nên phải phát tiếp".
/// Thuần (không đụng trình phát) để kiểm thử được.
///
/// [pausedByMixer] là cờ cũ; [isPlaying] là trình phát đang chạy thật (người dùng tự dừng thì không tự phát tiếp).
({List<MixOp> ops, bool pausedByMixer}) mixStep({
  required MediaAudio from,
  required MediaAudio to,
  required bool pausedByMixer,
  required bool isPlaying,
}) {
  if (from == to) return (ops: const [], pausedByMixer: pausedByMixer);
  switch (to) {
    case MediaAudio.normal:
      return (
        ops: [MixOp.restoreVolume, if (pausedByMixer) MixOp.play],
        pausedByMixer: false,
      );
    case MediaAudio.duck:
      // Đang tạm dừng vì Vy nói dài mà Vy chuyển sang nghe: giữ im lặng, chỉ hạ sẵn âm lượng.
      return (ops: const [MixOp.duckVolume], pausedByMixer: pausedByMixer);
    case MediaAudio.pause:
      return isPlaying
          ? (ops: const [MixOp.pause], pausedByMixer: true)
          : (ops: const [], pausedByMixer: pausedByMixer);
    case MediaAudio.stop:
      return (
        ops: [if (isPlaying) MixOp.pause],
        pausedByMixer: false,
      );
  }
}

/// Âm lượng thật gửi cho trình phát: hạ còn 20% (tối thiểu 5) khi không ở chế độ bình thường.
int effectiveVolume(int userVolume, MediaAudio mode) {
  if (mode == MediaAudio.normal) return userVolume;
  final d = (userVolume * 0.2).round();
  return d < 5 ? 5 : d;
}
