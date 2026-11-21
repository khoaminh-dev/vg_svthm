import '../domain/voice_models.dart';
import 'vy_card.dart';
import '../live/live_lab_controller.dart';
import '../presentation/voice_controller.dart';

/// Pha của một phiên Vy, gộp từ hai động cơ (Vy Live và Vy thường) để giao diện chỉ cần biết một thứ.
/// Xem docs/VY_LIVE_SAN_PHAM_KE_HOACH.md mục 5.
enum VyPhase {
  closed,
  opening,
  ready,
  listening,
  thinking,
  speaking,
  confirming,
  emergency,
  error,
  closing,
}

/// Động cơ đang chạy phiên: Live (giọng GPT-Live, não Vy cũ) hoặc Vy thường (Groq, giọng máy).
enum VyEngine { none, live, classic }

/// Ảnh chụp trạng thái Vy cho giao diện. Bất biến; do [deriveVyView] tạo ra.
class VyView {
  const VyView({
    this.phase = VyPhase.closed,
    this.engine = VyEngine.none,
    this.userText = '',
    this.vyText = '',
    this.chips = const [],
    this.level = 0,
    this.error,
    this.idlePrompt = false,
    this.showIntro = false,
    this.userExpanded = false,
    this.collapsed = false,
    this.captions = true,
    this.card,
  });

  final VyPhase phase;
  final VyEngine engine;

  /// Lời người dùng (phiên âm) và lời Vy.
  final String userText;
  final String vyText;

  /// Nút gợi ý/xác nhận (Gửi, Sửa, Hủy...).
  final List<String> chips;
  final double level;
  final String? error;

  /// Vy vừa hỏi "còn cần con không ạ?" vì người dùng im lặng.
  final bool idlePrompt;

  /// Hiện thẻ giải thích lần đầu.
  final bool showIntro;

  /// Người dùng chủ động mở rộng / thu gọn thẻ.
  final bool userExpanded;
  final bool collapsed;

  /// Cài đặt "Hiện chữ khi Vy nói".
  final bool captions;

  /// Thẻ kết quả đang hiện (huyết áp, thuốc, danh sách video, đã gửi) hoặc null.
  final VyCard? card;

  bool get isOpen => phase != VyPhase.closed;

  /// Có việc cần thẻ lớn: xác nhận, khẩn cấp, lỗi, gợi ý bấm được, thẻ giải thích.
  bool get needsCard =>
      phase == VyPhase.confirming ||
      phase == VyPhase.emergency ||
      error != null ||
      chips.isNotEmpty ||
      card != null ||
      showIntro;

  /// Thẻ lớn (L2) đang mở: có việc cần thẻ hoặc người dùng mở, trừ khi người dùng vừa thu gọn.
  bool get expanded => isOpen && !collapsed && (userExpanded || needsCard);

  /// Vy thường cần nút mic của riêng nó; Live luôn mở micro nên không cần.
  bool get hasMic => engine == VyEngine.classic;

  /// Dòng trạng thái ngắn, luôn hiện (người nghe kém, nơi ồn).
  String get statusText {
    if (idlePrompt) return 'Vy đang chờ bạn';
    switch (phase) {
      case VyPhase.closed:
        return '';
      case VyPhase.opening:
        return 'Vy đang kết nối…';
      case VyPhase.ready:
        return engine == VyEngine.classic
            ? 'Bấm mic để nói'
            : 'Vy đang nghe…';
      case VyPhase.listening:
        return 'Vy đang nghe…';
      case VyPhase.thinking:
        return 'Vy đang nghĩ…';
      case VyPhase.speaking:
        return 'Vy đang nói';
      case VyPhase.confirming:
        return 'Vy đang chờ bạn';
      case VyPhase.emergency:
        return 'Khẩn cấp';
      case VyPhase.error:
        return 'Vy gặp trục trặc';
      case VyPhase.closing:
        return 'Đang kết thúc…';
    }
  }

  VyView copyWith({
    VyPhase? phase,
    VyEngine? engine,
    String? userText,
    String? vyText,
    List<String>? chips,
    double? level,
    Object? error = _keep,
    bool? idlePrompt,
    bool? showIntro,
    bool? userExpanded,
    bool? collapsed,
    bool? captions,
    Object? card = _keep,
  }) => VyView(
    phase: phase ?? this.phase,
    engine: engine ?? this.engine,
    userText: userText ?? this.userText,
    vyText: vyText ?? this.vyText,
    chips: chips ?? this.chips,
    level: level ?? this.level,
    error: identical(error, _keep) ? this.error : error as String?,
    idlePrompt: idlePrompt ?? this.idlePrompt,
    showIntro: showIntro ?? this.showIntro,
    userExpanded: userExpanded ?? this.userExpanded,
    collapsed: collapsed ?? this.collapsed,
    captions: captions ?? this.captions,
    card: identical(card, _keep) ? this.card : card as VyCard?,
  );

  @override
  bool operator ==(Object other) =>
      other is VyView &&
      other.phase == phase &&
      other.engine == engine &&
      other.userText == userText &&
      other.vyText == vyText &&
      _listEq(other.chips, chips) &&
      other.level == level &&
      other.error == error &&
      other.idlePrompt == idlePrompt &&
      other.showIntro == showIntro &&
      other.userExpanded == userExpanded &&
      other.collapsed == collapsed &&
      other.captions == captions &&
      identical(other.card, card);

  @override
  int get hashCode => Object.hash(
    phase,
    engine,
    userText,
    vyText,
    Object.hashAll(chips),
    level,
    error,
    idlePrompt,
    showIntro,
    userExpanded,
    collapsed,
    captions,
    card == null ? 0 : identityHashCode(card),
  );
}

const _keep = Object();

bool _listEq(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Giữ lại phần cuối của chữ dài (Live cộng dồn chữ Vy nói) để thẻ không tràn.
String tailText(String s, {int max = 220}) {
  final t = s.trim();
  if (t.length <= max) return t;
  final cut = t.substring(t.length - max);
  final sp = cut.indexOf(' ');
  return '…${sp > 0 && sp < 30 ? cut.substring(sp + 1) : cut}';
}

/// Gộp trạng thái của động cơ đang chạy thành [VyView].
///
/// [classicStarted] là cờ "đã giao việc cho Vy thường": trước đó phiên vẫn đang mở (chào, chờ nối).
VyView deriveVyView({
  required VyEngine engine,
  required VoiceState classic,
  required LiveLabState live,
  required bool classicStarted,
  required bool closing,
  required bool idlePrompt,
  required bool showIntro,
  required bool userExpanded,
  required bool collapsed,
  required bool captions,
  bool reminderMode = false,
}) {
  VyView base(VyPhase phase) => VyView(
    phase: phase,
    engine: engine,
    idlePrompt: idlePrompt,
    showIntro: showIntro,
    userExpanded: userExpanded,
    collapsed: collapsed,
    captions: captions,
  );

  if (closing) return base(VyPhase.closing);

  switch (engine) {
    case VyEngine.none:
      return base(VyPhase.opening);
    case VyEngine.live:
      if (live.phase == LivePhase.closing) return base(VyPhase.closing);
      if (live.phase != LivePhase.live) return base(VyPhase.opening);
      final VyPhase phase;
      if (live.emergency) {
        phase = VyPhase.emergency;
      } else if (live.confirmSay != null) {
        phase = VyPhase.confirming;
      } else if (live.error != null) {
        phase = VyPhase.error;
      } else {
        phase = VyPhase.ready;
      }
      return base(phase).copyWith(
        userText: tailText(live.userText),
        vyText: live.confirmSay != null
            ? live.confirmSay!
            : tailText(live.assistantText),
        chips: live.confirmSay != null ? live.confirmChips : const [],
        error: live.error,
      );
    case VyEngine.classic:
      // Đang ở chế độ nhắc (chưa mở mic/chưa nói chuyện): sẵn sàng chờ người dùng trả lời bằng nút.
      if (!classicStarted) return base(reminderMode ? VyPhase.ready : VyPhase.opening);
      final confirming =
          classic.dialog.expects == VoiceExpect.yesNo && classic.chips.isNotEmpty;
      final VyPhase phase;
      switch (classic.status) {
        case VoiceStatus.listening:
          phase = VyPhase.listening;
        case VoiceStatus.thinking:
          phase = VyPhase.thinking;
        case VoiceStatus.speaking:
          phase = VyPhase.speaking;
        case VoiceStatus.idle:
          phase = confirming
              ? VyPhase.confirming
              : classic.error != null
              ? VyPhase.error
              : VyPhase.ready;
      }
      return base(phase).copyWith(
        userText: classic.transcript,
        vyText: classic.say,
        chips: classic.chips,
        level: classic.level,
        error: classic.error,
      );
  }
}
