import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vg_svthm/features/voice/core/vy_core.dart';
import 'package:vg_svthm/features/voice/core/vy_settings.dart';
import 'package:vg_svthm/features/voice/core/vy_view.dart';
import 'package:vg_svthm/features/voice/domain/voice_models.dart';
import 'package:vg_svthm/features/voice/live/live_lab_controller.dart';
import 'package:vg_svthm/features/voice/presentation/voice_controller.dart';

/// Vy thường giả: không đụng micro/loa, chỉ ghi lại thao tác.
class FakeVoiceCtl extends VoiceController {
  int toggles = 0;
  int closes = 0;
  int prepares = 0;
  final taps = <String>[];

  @override
  VoiceState build() => const VoiceState();

  @override
  Future<void> toggle() async {
    toggles++;
    state = state.copyWith(panelOpen: true, status: VoiceStatus.listening);
  }

  @override
  void prepareSession() {
    prepares++;
    state = state.copyWith(panelOpen: true);
  }

  @override
  Future<void> close() async {
    closes++;
    state = const VoiceState();
  }

  @override
  Future<void> tapChip(String text) async => taps.add(text);

  void emit(VoiceState s) => state = s;
}

/// Vy Live giả: nối sau 50 ms hoặc lỗi theo [failWith].
class FakeLive extends LiveLabController {
  String? failWith;
  int starts = 0;
  int ends = 0;
  final taps = <String>[];

  @override
  LiveLabState build() => const LiveLabState();

  @override
  Future<void> start() async {
    starts++;
    state = state.copyWith(phase: LivePhase.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (failWith != null) {
      state = state.copyWith(phase: LivePhase.idle, error: failWith);
      return;
    }
    state = state.copyWith(phase: LivePhase.live);
  }

  @override
  Future<void> end() async {
    ends++;
    state = const LiveLabState();
  }

  @override
  Future<void> tapChip(String chip) async => taps.add(chip);

  void emit(LiveLabState s) => state = s;
}

class FakeSay implements VyVoice {
  final said = <String>[];
  int stops = 0;

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> stop() async => stops++;
}

class Rig {
  Rig({Map<String, Object> prefs = const {'vy_intro_seen': true, 'vy_sounds': false}}) {
    SharedPreferences.setMockInitialValues(prefs);
    c = ProviderContainer(
      overrides: [
        voiceControllerProvider.overrideWith(() => voice),
        liveLabProvider.overrideWith(() => live),
        vyVoiceProvider.overrideWithValue(say),
        vyNowProvider.overrideWithValue(() => now),
      ],
    );
    c.listen(vyCoreProvider, (_, _) {});
    c.read(vySettingsProvider);
  }

  late final ProviderContainer c;
  final voice = FakeVoiceCtl();
  final live = FakeLive();
  final say = FakeSay();
  DateTime now = DateTime(2026, 11, 20, 9, 0);

  VyCore get core => c.read(vyCoreProvider.notifier);
  VyView get view => c.read(vyCoreProvider);
}

void tick(FakeAsync a, [int ms = 100]) {
  a.flushMicrotasks();
  a.elapse(Duration(milliseconds: ms));
  a.flushMicrotasks();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mở: chào ngay, thử Vy Live ở chế độ lai, sẵn sàng khi nối xong', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      a.flushMicrotasks();
      // Đang nối: panel đã hiện và Vy đã chào (không chờ mạng).
      expect(r.view.phase, VyPhase.opening);
      expect(r.view.engine, VyEngine.live);
      expect(r.say.said, ['Dạ, con nghe bác ạ']);
      tick(a, 100);
      expect(r.view.phase, VyPhase.ready);
      expect(r.live.state.mode, 'C');
      expect(r.live.state.sendReal, isTrue);
      expect(r.voice.toggles, 0);
      expect(r.view.hasMic, isFalse);
    });
  });

  test('Live không được bật cho tài khoản: dùng Vy thường trong cùng giao diện, lần sau không thử lại ngay', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      r.live.failWith = 'Exception: live_not_allowed (403)';
      unawaited(r.core.open());
      tick(a, 200);
      expect(r.live.starts, 1);
      expect(r.voice.toggles, 1);
      expect(r.view.engine, VyEngine.classic);
      expect(r.view.phase, VyPhase.listening);
      expect(r.view.hasMic, isTrue);

      unawaited(r.core.close());
      tick(a);
      expect(r.view.isOpen, isFalse);
      expect(r.voice.closes, 1);

      // Mở lần nữa: vẫn Vy thường, không gọi Live.
      unawaited(r.core.open());
      tick(a, 200);
      expect(r.live.starts, 1);
      expect(r.voice.toggles, 2);
      unawaited(r.core.close());
      tick(a);

      // Sau hơn một giờ thử lại Live.
      r.now = r.now.add(const Duration(minutes: 61));
      r.live.failWith = null;
      unawaited(r.core.open());
      tick(a, 200);
      expect(r.live.starts, 2);
      expect(r.view.engine, VyEngine.live);
    });
  });

  test('Live lỗi thoáng qua: chỉ tránh Live vài phút', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      r.live.failWith = 'Exception: mạng chập chờn';
      unawaited(r.core.open());
      tick(a, 200);
      unawaited(r.core.close());
      tick(a);
      r.now = r.now.add(const Duration(minutes: 3));
      r.live.failWith = null;
      unawaited(r.core.open());
      tick(a, 200);
      expect(r.live.starts, 2);
      expect(r.view.engine, VyEngine.live);
    });
  });

  test('nút X: đóng ngay, kết thúc Live, ngắt giọng chào', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      unawaited(r.core.close());
      a.flushMicrotasks();
      expect(r.view.isOpen, isFalse);
      tick(a);
      expect(r.live.ends, 1);
      expect(r.say.stops, greaterThan(0));
    });
  });

  test('đóng khi đang nối: Vy không bật lại sau khi người dùng đã đóng', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      a.flushMicrotasks();
      expect(r.view.phase, VyPhase.opening);
      unawaited(r.core.close());
      tick(a, 200);
      expect(r.view.isOpen, isFalse);
      expect(r.voice.toggles, 0);
    });
  });

  test('Back: thẻ lớn thu về thanh nhỏ, bấm lần nữa mới đóng; đóng rồi thì Back không xử lý', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      // Đang chờ xác nhận: thẻ lớn tự mở.
      r.live.emit(
        r.live.state.copyWith(
          confirmSay: 'Gửi cho Minh: mẹ khoẻ, đúng không ạ?',
          confirmChips: const ['Gửi', 'Sửa', 'Hủy'],
        ),
      );
      tick(a, 10);
      expect(r.view.phase, VyPhase.confirming);
      expect(r.view.expanded, isTrue);
      expect(r.core.back(), isTrue);
      tick(a, 10);
      expect(r.view.isOpen, isTrue);
      expect(r.view.expanded, isFalse);
      expect(r.core.back(), isTrue);
      tick(a, 10);
      expect(r.view.isOpen, isFalse);
      expect(r.core.back(), isFalse);
    });
  });

  test('bấm nút xác nhận đi tới đúng động cơ', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      unawaited(r.core.tapChip('Gửi'));
      tick(a, 10);
      expect(r.live.taps, ['Gửi']);
    });
  });

  test('im lặng 30 giây: hỏi "còn cần con không", thêm 10 giây thì đóng', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      a.elapse(const Duration(seconds: 29));
      a.flushMicrotasks();
      expect(r.view.idlePrompt, isFalse);
      a.elapse(const Duration(seconds: 2));
      a.flushMicrotasks();
      expect(r.view.idlePrompt, isTrue);
      expect(r.say.said.last, 'Bác còn cần con không ạ?');
      expect(r.view.isOpen, isTrue);
      a.elapse(const Duration(seconds: 11));
      a.flushMicrotasks();
      expect(r.view.isOpen, isFalse);
      expect(r.live.ends, 1);
    });
  });

  test('có người nói thì đếm lại từ đầu, và câu hỏi biến mất', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      a.elapse(const Duration(seconds: 25));
      r.live.emit(r.live.state.copyWith(userText: 'mở nhạc xưa'));
      a.flushMicrotasks();
      a.elapse(const Duration(seconds: 25));
      a.flushMicrotasks();
      expect(r.view.idlePrompt, isFalse); // 50 giây từ lúc mở nhưng mới 25 giây từ lúc nói
      a.elapse(const Duration(seconds: 6));
      a.flushMicrotasks();
      expect(r.view.idlePrompt, isTrue);
      r.live.emit(r.live.state.copyWith(userText: 'mở nhạc xưa nữa'));
      a.flushMicrotasks();
      expect(r.view.idlePrompt, isFalse);
      expect(r.view.isOpen, isTrue);
    });
  });

  test('không tự đóng khi đang chờ xác nhận, khẩn cấp hoặc lỗi', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      r.live.emit(r.live.state.copyWith(confirmSay: 'Gửi cho Minh?', confirmChips: const ['Gửi', 'Hủy']));
      a.flushMicrotasks();
      a.elapse(const Duration(minutes: 2));
      expect(r.view.isOpen, isTrue);
      r.live.emit(r.live.state.copyWith(confirmSay: null, confirmChips: const [], emergency: true));
      a.flushMicrotasks();
      a.elapse(const Duration(minutes: 2));
      expect(r.view.phase, VyPhase.emergency);
      expect(r.view.isOpen, isTrue);
    });
  });

  test('động cơ tự dừng (hết trần phiên): Vy đóng theo, không treo panel', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      r.live.emit(const LiveLabState()); // Live tự về rảnh
      tick(a, 10);
      expect(r.view.isOpen, isFalse);
    });
  });

  test('Vy thường điều hướng sang màn khác (tự đóng bảng): Vy đóng theo', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      r.live.failWith = 'live_not_allowed 403';
      unawaited(r.core.open());
      tick(a, 200);
      expect(r.view.engine, VyEngine.classic);
      r.voice.emit(const VoiceState()); // panelOpen = false
      tick(a, 10);
      expect(r.view.isOpen, isFalse);
    });
  });

  test('mở lại trong 5 phút: chỉ "Dạ?"; lâu hơn thì chào đầy đủ và đổi câu', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      unawaited(r.core.close());
      tick(a);
      r.now = r.now.add(const Duration(minutes: 2));
      unawaited(r.core.open());
      tick(a, 100);
      expect(r.say.said, ['Dạ, con nghe bác ạ', 'Dạ?']);
      unawaited(r.core.close());
      tick(a);
      r.now = r.now.add(const Duration(minutes: 10));
      unawaited(r.core.open());
      tick(a, 100);
      expect(r.say.said.last, isNot('Dạ?'));
      expect(r.say.said.last, contains('bác'));
    });
  });

  test('người dùng bắt đầu nói thì ngắt giọng máy đang chào', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      final before = r.say.stops;
      r.live.emit(r.live.state.copyWith(userText: 'nhắn cho con'));
      a.flushMicrotasks();
      expect(r.say.stops, greaterThan(before));
    });
  });

  test('thẻ giải thích chỉ hiện lần đầu, bấm "Đã hiểu" thì không hiện nữa', () {
    fakeAsync((a) {
      final r = Rig(prefs: const {'vy_sounds': false});
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      expect(r.view.showIntro, isTrue);
      expect(r.view.expanded, isTrue);
      unawaited(r.core.dismissIntro());
      tick(a, 10);
      expect(r.view.showIntro, isFalse);
      unawaited(r.core.close());
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      expect(r.view.showIntro, isFalse);
    });
  });

  test('gõ chữ cho Vy: đi tới động cơ đang chạy, câu rỗng hoặc khi đã đóng thì bỏ qua', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.sendText('mở thuốc')); // chưa mở
      tick(a, 10);
      expect(r.live.taps, isEmpty);
      unawaited(r.core.open());
      tick(a, 100);
      unawaited(r.core.sendText('  '));
      unawaited(r.core.sendText('tôi uống rồi'));
      tick(a, 10);
      expect(r.live.taps, ['tôi uống rồi']);
      unawaited(r.core.close());
      tick(a);
      unawaited(r.core.sendText('xin chào'));
      tick(a, 10);
      expect(r.live.taps, ['tôi uống rồi']);

      // Vy thường
      r.live.failWith = 'live_not_allowed 403';
      unawaited(r.core.open());
      tick(a, 300);
      unawaited(r.core.sendText('mở nhạc xưa'));
      tick(a, 10);
      expect(r.voice.taps, ['mở nhạc xưa']);
    });
  });

  test('gõ chữ làm người dùng "đang hoạt động": đếm lại 30 giây im lặng', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 100);
      a.elapse(const Duration(seconds: 25));
      unawaited(r.core.sendText('mở thuốc'));
      a.flushMicrotasks();
      a.elapse(const Duration(seconds: 25));
      a.flushMicrotasks();
      expect(r.view.idlePrompt, isFalse);
    });
  });

  test('mở hai lần liền: lần hai bị bỏ qua', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      unawaited(r.core.open());
      tick(a, 200);
      expect(r.live.starts, 1);
      expect(r.say.said.length, 1);
    });
  });
}
