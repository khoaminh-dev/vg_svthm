import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/diagnostics/app_trace.dart';
import '../data/speech_player.dart';
import '../data/voice_actions.dart';
import '../data/vy_sounds.dart';
import '../live/live_lab_controller.dart';
import '../presentation/voice_controller.dart';
import '../../entertainment/presentation/entertainment_providers.dart';
import 'vy_card.dart';
import 'vy_context.dart';
import 'vy_cursor.dart';
import 'vy_greeting.dart';
import 'vy_settings.dart';
import 'vy_view.dart';

/// Giọng máy đọc lời chào và câu hỏi "còn cần con không". Tách ra để kiểm thử không đụng loa.
abstract class VyVoice {
  Future<void> speak(String text);
  Future<void> stop();
}

class _DeviceVyVoice implements VyVoice {
  _DeviceVyVoice(this._ref);

  final Ref _ref;
  SpeechPlayer? _p;
  SpeechPlayer get _player => _p ??= SpeechPlayer(_ref.read(voiceApiProvider));

  @override
  Future<void> speak(String text) async {
    await _player.speak(text, sayClass: 'static');
  }

  @override
  Future<void> stop() async => _p?.stop();

  Future<void> dispose() async => _p?.dispose();
}

final vyVoiceProvider = Provider<VyVoice>((ref) {
  final v = _DeviceVyVoice(ref);
  ref.onDispose(() => unawaited(v.dispose()));
  return v;
});

/// Đồng hồ (ghi đè được khi kiểm thử).
final vyNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Thời gian im lặng trước khi Vy hỏi "còn cần con không ạ?", và chờ thêm trước khi đóng (mục 6.5 của kế hoạch).
const vyIdleAsk = Duration(seconds: 30);
const vyIdleClose = Duration(seconds: 10);

/// Vy Live lỗi (chưa được bật cho tài khoản này, máy chủ tắt, mạng...): lần mở sau dùng Vy thường, không thử lại ngay.
/// Nhắc chủ động không ai trả lời thì tự đóng sau chừng này (không hỏi "còn cần con không").
const vyReminderIdle = Duration(seconds: 45);

const _liveBlockLong = Duration(minutes: 60);
const _liveBlockShort = Duration(minutes: 2);

/// Lõi điều phối Vy: MỘT điểm vào (nút Vy), MỘT trạng thái cho giao diện, hai động cơ phía sau.
///
/// - Mở: phản hồi tức thì (tiếng, rung, giọng máy chào), rồi thử Vy Live; Live không được thì dùng Vy thường
///   trong cùng giao diện (dự phòng, quyết định D21).
/// - Đóng: nút X, Back, nói "thôi" (qua Vy cũ), im lặng 30 giây, hết trần phiên, động cơ tự đóng.
/// - Giao diện chỉ đọc [VyView]; xem docs/VY_LIVE_SAN_PHAM_KE_HOACH.md mục 5, 6, 11.
class VyCore extends Notifier<VyView> {
  bool _open = false;
  bool _starting = false; // đang chờ Vy Live nối (lỗi ở giai đoạn này là để dự phòng, không phải "tự đóng")
  bool _classicStarted = false;
  bool _reminderMode = false; // panel mở vì Vy tự nhắc: Vy thường, chưa mở mic
  bool _userExpanded = false;
  bool _collapsed = false;
  bool _idlePrompt = false;
  int _run = 0; // tăng mỗi lần mở/đóng để bỏ kết quả của phiên cũ
  VyEngine _engine = VyEngine.none;
  String _honorific = 'bác';
  String _sig = '';
  String _lastUser = '';
  DateTime? _lastClosedAt;
  DateTime? _liveBlockedUntil;
  int _greetVariant = 0;
  Timer? _idleTimer;
  Timer? _closeTimer;
  Timer? _holdTimer;
  DateTime? _cardShownAt;
  ProviderSubscription<LiveLabState>? _liveSub; // chỉ tạo bộ điều khiển Live khi lần đầu dùng
  Future<void>? _greeting;

  VyVoice get _voice => ref.read(vyVoiceProvider);
  DateTime _now() => ref.read(vyNowProvider)();
  VySettings get _settings =>
      ref.read(vySettingsProvider).value ?? const VySettings();

  @override
  VyView build() {
    ref.listen(voiceControllerProvider, (_, _) => _sync());
    ref.listen(vySettingsProvider, (_, _) => _sync());
    ref.listen(vyCardProvider, (_, next) {
      _onCard(next);
      _sync();
    });
    ref.onDispose(() {
      _holdTimer?.cancel();
      _cancelTimers();
      _liveSub?.close();
    });
    return const VyView();
  }

  // ---------- Điều khiển từ giao diện ----------

  /// Nút Vy: mở một phiên (chạm lúc đang mở thì bỏ qua).
  Future<void> open() async {
    // Đang hiện nhắc chủ động mà người dùng chạm nút Vy: nâng lên phiên đầy đủ (Live nếu được).
    if (_open && _reminderMode && !_classicStarted) await close(reason: 'reminder_upgrade');
    if (_open) return;
    final run = ++_run;
    _reminderMode = false;
    _open = true;
    _starting = false;
    _classicStarted = false;
    _engine = VyEngine.none;
    _userExpanded = false;
    _collapsed = false;
    _idlePrompt = false;
    _sig = '';
    _lastUser = '';
    _cancelTimers();
    ref.read(vyCardProvider.notifier).clear();
    HapticFeedback.lightImpact();
    if (_settings.sounds) unawaited(VySounds.on());
    Analytics.track('vy_open');
    // Chỉ bản build thử (VG_TRACE): ghi ngữ cảnh màn hình để đối chiếu với bộ kiểm thử của máy chủ.
    if (kTrace) AppTrace.line('UI_CONTEXT ${jsonEncode(ref.read(vyUiContextProvider)())}');
    _sync();

    final recent = _lastClosedAt != null && _now().difference(_lastClosedAt!) < recentWindow;
    // Chào ngay bằng cách xưng hô đã biết; lần đầu chưa biết thì "bác", không chờ mạng.
    _greeting = _greet(
      vyGreeting(now: _now(), honorific: _honorific, recent: recent, variant: _greetVariant++),
    );
    unawaited(_refreshHonorific());

    final liveOk = _liveBlockedUntil == null || !_now().isBefore(_liveBlockedUntil!);
    if (liveOk) {
      await _openLive(run);
    } else {
      await _openClassic(run);
    }
  }

  /// Đóng phiên (X, "thôi", im lặng, hết trần...). [reason] chỉ để ghi nhật ký.
  Future<void> close({String reason = 'user'}) async {
    if (!_open) return;
    _open = false;
    _run++;
    _cancelTimers();
    final engine = _engine;
    final classicStarted = _classicStarted;
    _reminderMode = false;
    _engine = VyEngine.none;
    _classicStarted = false;
    _starting = false;
    _idlePrompt = false;
    _lastClosedAt = _now();
    Analytics.track('vy_close', {'reason': reason, 'engine': engine.name});
    if (_settings.sounds) unawaited(VySounds.off());
    _holdTimer?.cancel();
    ref.read(vyCardProvider.notifier).clear();
    ref.read(videoMarksProvider.notifier).set(false);
    ref.read(vyCursorProvider).cancel(); // đóng Vy thì con trỏ dừng ngay, không bấm nữa
    state = const VyView(); // giao diện đóng ngay, việc dọn dẹp chạy sau
    await _voice.stop();
    if (engine == VyEngine.live) {
      await ref.read(liveLabProvider.notifier).end();
    }
    if (classicStarted) {
      await ref.read(voiceControllerProvider.notifier).close();
    }
  }

  /// Nút Back của Android. Trả về `true` nếu đã xử lý: thẻ lớn thu về thanh nhỏ, lần nữa mới đóng.
  bool back() {
    if (!_open) return false;
    if (state.expanded) {
      collapse();
    } else {
      unawaited(close(reason: 'back'));
    }
    return true;
  }

  void collapse() {
    if (!_open) return;
    _userExpanded = false;
    _collapsed = true;
    _sync();
  }

  void expand() {
    if (!_open) return;
    _userExpanded = true;
    _collapsed = false;
    _sync();
  }

  /// Nút mic của Vy thường (Live luôn mở micro nên không có nút này).
  Future<void> primary() async {
    if (_open && _reminderMode) await _startClassicFromReminder();
    if (!_open || _engine != VyEngine.classic || !_classicStarted) return;
    _noteActivity();
    ref.read(vyCardProvider.notifier).clear();
    await ref.read(voiceControllerProvider.notifier).toggle();
  }

  /// Bấm một nút gợi ý/xác nhận: coi như người dùng vừa nói chữ đó.
  Future<void> tapChip(String chip) async {
    if (!_open) return;
    _noteActivity();
    ref.read(vyCardProvider.notifier).clear();
    switch (_engine) {
      case VyEngine.live:
        await ref.read(liveLabProvider.notifier).tapChip(chip);
      case VyEngine.classic:
        await _startClassicFromReminder();
        await ref.read(voiceControllerProvider.notifier).tapChip(chip);
      case VyEngine.none:
        break;
    }
  }

  /// Người dùng gõ chữ cho Vy (người nghe kém, nơi ồn, hoặc muốn thử): đi cùng đường với lời nói đã được chép chữ.
  Future<void> sendText(String text) async {
    final t = text.trim();
    if (!_open || t.isEmpty) return;
    _noteActivity();
    ref.read(vyCardProvider.notifier).clear();
    Analytics.track('vy_text', {'len': t.length});
    switch (_engine) {
      case VyEngine.live:
        await ref.read(liveLabProvider.notifier).tapChip(t);
      case VyEngine.classic:
        await _startClassicFromReminder();
        if (_classicStarted) await ref.read(voiceControllerProvider.notifier).tapChip(t);
      case VyEngine.none:
        break;
    }
  }

  /// Chạm một nút trên thẻ: làm việc đó rồi thu panel về thanh nhỏ để người dùng thấy kết quả (màn vừa mở, video vừa chọn...).
  void runCardAction(VyCardAction a) {
    _noteActivity();
    a.run();
    if (!_open || a.keepOpen) return;
    // Nhắc chủ động: trả lời xong là đóng (không để panel treo). Thẻ thường: thu về thanh nhỏ để thấy kết quả.
    if (_reminderMode && !_classicStarted) {
      unawaited(close(reason: 'reminder_done'));
    } else {
      collapse();
    }
  }

  /// Đã đọc thẻ giải thích lần đầu.
  Future<void> dismissIntro() async {
    await ref.read(vySettingsProvider.notifier).markIntroSeen();
    _sync();
  }

  // ---------- Nhắc chủ động (D19) ----------

  /// Vy tự mở để nhắc: panel + thẻ + giọng máy nói [speech], bằng Vy thường (miễn phí), KHÔNG Live, KHÔNG tự mở mic.
  /// Trả về `false` (không làm gì) nếu Vy đang mở. Người dùng trả lời bằng nút trên thẻ, gõ chữ, hoặc bấm mic (khi đó mới mở mic).
  Future<bool> remind({required String speech, required VyCard card, String kind = ''}) async {
    if (_open) return false;
    ++_run;
    _reminderMode = true;
    _open = true;
    _starting = false;
    _classicStarted = false;
    _engine = VyEngine.classic;
    _userExpanded = false;
    _collapsed = false;
    _idlePrompt = false;
    _sig = '';
    _lastUser = '';
    _cancelTimers();
    ref.read(vyCardProvider.notifier).show(card);
    HapticFeedback.lightImpact();
    if (_settings.sounds) unawaited(VySounds.on());
    Analytics.track('vy_remind', {'kind': kind});
    _sync();
    unawaited(_greet(speech)); // giọng máy; không chờ
    return true;
  }

  /// Từ chế độ nhắc sang phiên Vy thường thật (người dùng gõ chữ, chạm gợi ý hoặc bấm mic).
  Future<void> _startClassicFromReminder() async {
    if (!_open || !_reminderMode || _classicStarted) return;
    _reminderMode = false;
    _classicStarted = true;
    _cancelTimers();
    await _voice.stop();
    ref.read(voiceControllerProvider.notifier).prepareSession();
    _sync();
  }

  // ---------- Mở bằng từng động cơ ----------

  Future<void> _openLive(int run) async {
    _liveSub ??= ref.listen(liveLabProvider, (_, _) => _sync());
    final live = ref.read(liveLabProvider.notifier);
    live
      ..setMode('C') // giọng GPT-Live, lệnh đi qua Vy cũ (đã đo ở Giai đoạn 0)
      ..setExecReal(true)
      ..setSendReal(true)
      ..setAutoSend(true);
    _engine = VyEngine.live;
    _starting = true;
    _sync();
    try {
      await live.start();
    } finally {
      if (run == _run) _starting = false;
    }
    if (run != _run || !_open) return; // đã đóng trong lúc chờ nối
    final s = ref.read(liveLabProvider);
    if (s.phase == LivePhase.idle) {
      final why = s.error ?? '';
      _blockLive(why);
      Analytics.track('vy_live_fallback', {'why': why.length > 120 ? why.substring(0, 120) : why});
      _engine = VyEngine.none;
      await _openClassic(run);
      return;
    }
    _sync();
  }

  Future<void> _openClassic(int run) async {
    _engine = VyEngine.classic;
    _sync();
    // Vy thường mở micro ngay, nên chờ chào xong để micro không thu lời chào.
    await _greeting;
    if (run != _run || !_open) return;
    // `toggle` đặt panelOpen = true ngay (đồng bộ) rồi mới đợi mic.
    unawaited(ref.read(voiceControllerProvider.notifier).toggle());
    _classicStarted = true;
    _sync();
  }

  void _blockLive(String why) {
    final permanent = why.contains('live_not_allowed') ||
        why.contains('live_disabled') ||
        why.contains('403') ||
        why.contains('503');
    _liveBlockedUntil = _now().add(permanent ? _liveBlockLong : _liveBlockShort);
  }

  Future<void> _refreshHonorific() async {
    try {
      final h = await ref.read(voiceActionsProvider).loadHonorific();
      if (h.trim().isNotEmpty) _honorific = h.trim();
    } catch (_) {}
  }

  Future<void> _greet(String text) async {
    try {
      await _voice.speak(text);
    } catch (_) {}
  }

  // ---------- Đồng bộ trạng thái và bộ đếm im lặng ----------

  void _sync() {
    if (!_open) {
      if (state.isOpen) state = const VyView();
      return;
    }
    final classic = ref.read(voiceControllerProvider);
    final live = _liveSub == null ? const LiveLabState() : ref.read(liveLabProvider);

    // Động cơ tự dừng (hết trần phiên, mất kết nối, Vy thường điều hướng sang màn khác...): đóng phiên.
    if (_engine == VyEngine.live && !_starting && live.phase == LivePhase.idle) {
      unawaited(close(reason: 'live_ended'));
      return;
    }
    if (_engine == VyEngine.classic && _classicStarted && !classic.panelOpen) {
      unawaited(close(reason: 'classic_closed'));
      return;
    }

    final settings = _settings;
    final view = deriveVyView(
      engine: _engine,
      classic: classic,
      live: live,
      classicStarted: _classicStarted,
      closing: false,
      idlePrompt: _idlePrompt,
      showIntro: !settings.introSeen && !_reminderMode,
      userExpanded: _userExpanded,
      collapsed: _collapsed,
      captions: settings.captions,
      reminderMode: _reminderMode,
    ).copyWith(card: ref.read(vyCardProvider));

    // Người dùng bắt đầu nói thì ngắt lời chào/câu hỏi của giọng máy ngay (không để Vy nói chen lên người dùng).
    if (view.userText.isNotEmpty && view.userText != _lastUser) {
      unawaited(_voice.stop());
      // Người dùng nói việc mới thì thẻ cũ hết ý nghĩa (thẻ vừa hiện sau lời nói này thì giữ: chữ chép về có thể đến sau thẻ).
      final shown = _cardShownAt;
      if (ref.read(vyCardProvider) != null && shown != null && _now().difference(shown) > const Duration(milliseconds: 800)) {
        ref.read(vyCardProvider.notifier).clear();
      }
    }
    _lastUser = view.userText;

    // Có nội dung mới thì thẻ tự mở lại (người dùng đã thu gọn trước đó chỉ áp dụng cho nội dung cũ).
    final sig = '${view.phase.name}|${view.userText}|${view.vyText}|${view.chips.join(',')}|${view.error}|${view.card == null ? 0 : identityHashCode(view.card)}';
    if (sig != _sig) {
      final first = _sig.isEmpty;
      _sig = sig;
      if (!first) {
        _collapsed = false;
        _noteActivity();
      }
    }
    _armIdle(view);
    state = view.copyWith(collapsed: _collapsed, idlePrompt: _idlePrompt);
  }

  /// Thẻ mới hiện: thẻ chỉ để xem lướt (có `hold`) thì tự thu về thanh nhỏ sau thời gian giữ, trừ khi người dùng đã tự mở rộng.
  void _onCard(VyCard? card) {
    _holdTimer?.cancel();
    _holdTimer = null;
    _cardShownAt = card == null ? null : _now();
    final hold = card?.hold;
    if (card == null || hold == null || !_open) return;
    _holdTimer = Timer(hold, () {
      _holdTimer = null;
      if (_open && !_userExpanded && ref.read(vyCardProvider) == card) collapse();
    });
  }

  void _noteActivity() {
    _idleTimer?.cancel();
    _closeTimer?.cancel();
    _idleTimer = _closeTimer = null;
    if (_idlePrompt) _idlePrompt = false;
  }

  /// Chỉ đếm giờ im lặng khi Vy đang "sẵn sàng". Không đếm khi chờ xác nhận, khẩn cấp, lỗi, đang nối hay đang làm việc.
  void _armIdle(VyView v) {
    // Nhắc chủ động không ai trả lời: tự đóng êm sau [vyReminderIdle], không hỏi.
    if (_reminderMode) {
      _idleTimer ??= Timer(vyReminderIdle, () {
        _idleTimer = null;
        if (_open && _reminderMode) {
          Analytics.track('vy_remind_ignored');
          unawaited(close(reason: 'reminder_ignored'));
        }
      });
      return;
    }
    final idle = v.phase == VyPhase.ready && !v.showIntro;
    if (!idle) {
      _idleTimer?.cancel();
      _idleTimer = null;
      if (v.phase != VyPhase.ready) {
        _closeTimer?.cancel();
        _closeTimer = null;
        _idlePrompt = false;
      }
      return;
    }
    if (_idleTimer != null || _closeTimer != null) return;
    _idleTimer = Timer(vyIdleAsk, _askStillThere);
  }

  void _askStillThere() {
    _idleTimer = null;
    if (!_open || state.phase != VyPhase.ready) return;
    _idlePrompt = true;
    Analytics.track('vy_idle_ask');
    unawaited(_greet(vyStillThere(_honorific)));
    _closeTimer = Timer(vyIdleClose, () {
      _closeTimer = null;
      unawaited(close(reason: 'idle'));
    });
    _sync();
  }

  void _cancelTimers() {
    _idleTimer?.cancel();
    _closeTimer?.cancel();
    _idleTimer = _closeTimer = null;
  }
}

final vyCoreProvider = NotifierProvider<VyCore, VyView>(VyCore.new);
