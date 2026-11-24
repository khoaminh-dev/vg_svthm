import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/entertainment/presentation/media_audio.dart';
import 'package:vg_svthm/features/voice/core/vy_card.dart';
import 'package:vg_svthm/features/voice/core/vy_core.dart';
import 'package:vg_svthm/features/voice/core/vy_view.dart';

class _FakeVy extends VyCore {
  @override
  VyView build() => const VyView();

  void show(VyView v) => state = v;
}

VyView view(VyPhase p, {VyEngine e = VyEngine.classic, VyCard? card}) => VyView(phase: p, engine: e, card: card);

void main() {
  group('chế độ âm thanh theo Vy', () {
    test('Vy đóng: nhạc phát bình thường', () {
      expect(mediaAudioFor(const VyView(), {}), MediaAudio.normal);
    });

    test('Vy mở (nghe, nghĩ, nói, chờ, kết nối, Live): hạ tiếng để micro không thu nhầm', () {
      for (final p in [VyPhase.opening, VyPhase.ready, VyPhase.listening, VyPhase.thinking, VyPhase.speaking, VyPhase.confirming]) {
        expect(mediaAudioFor(view(p), {}), MediaAudio.duck, reason: '$p classic');
        expect(mediaAudioFor(view(p, e: VyEngine.live), {}), MediaAudio.duck, reason: '$p live');
      }
    });

    test('Vy đang đóng thì trả lại âm lượng', () {
      expect(mediaAudioFor(view(VyPhase.closing), {}), MediaAudio.normal);
    });

    test('khẩn cấp và thẻ SOS: dừng hẳn, không tự phát lại', () {
      expect(mediaAudioFor(view(VyPhase.emergency), {}), MediaAudio.stop);
      expect(mediaAudioFor(view(VyPhase.ready, card: SosCard(seconds: 5, onFire: () {})), {}), MediaAudio.stop);
    });

    test('màn SOS mở: dừng hẳn kể cả khi Vy đóng', () {
      expect(mediaAudioFor(const VyView(), {'sos'}), MediaAudio.stop);
      expect(mediaAudioFor(view(VyPhase.listening), {'sos'}), MediaAudio.stop);
    });
  });

  group('chuyển chế độ (thuần, không đụng trình phát)', () {
    ({List<MixOp> ops, bool paused}) go(MediaAudio from, MediaAudio to, {bool paused = false, bool playing = true}) {
      final r = mixStep(from: from, to: to, pausedByMixer: paused, isPlaying: playing);
      return (ops: r.ops, paused: r.pausedByMixer);
    }

    test('không đổi thì không làm gì', () {
      expect(go(MediaAudio.duck, MediaAudio.duck).ops, isEmpty);
    });

    test('Vy mở rồi đóng: hạ tiếng rồi trả đúng âm lượng, không phát thừa', () {
      expect(go(MediaAudio.normal, MediaAudio.duck).ops, [MixOp.duckVolume]);
      final back = go(MediaAudio.duck, MediaAudio.normal);
      expect(back.ops, [MixOp.restoreVolume]);
      expect(back.paused, isFalse);
    });

    test('Vy nói dài: tạm dừng, xong thì trả tiếng và phát tiếp', () {
      final p = go(MediaAudio.duck, MediaAudio.pause);
      expect(p.ops, [MixOp.pause]);
      expect(p.paused, isTrue);
      // Vy chuyển sang nghe: vẫn im lặng
      final listen = go(MediaAudio.pause, MediaAudio.duck, paused: true, playing: false);
      expect(listen.ops, [MixOp.duckVolume]);
      expect(listen.paused, isTrue);
      final done = go(MediaAudio.duck, MediaAudio.normal, paused: true, playing: false);
      expect(done.ops, [MixOp.restoreVolume, MixOp.play]);
      expect(done.paused, isFalse);
    });

    test('người dùng đã tự dừng thì Vy nói xong không tự phát hộ', () {
      final p = go(MediaAudio.duck, MediaAudio.pause, playing: false);
      expect(p.ops, isEmpty);
      expect(p.paused, isFalse);
      final done = go(MediaAudio.duck, MediaAudio.normal, paused: false, playing: false);
      expect(done.ops, [MixOp.restoreVolume]);
    });

    test('SOS: dừng hẳn, xong SOS không tự phát lại', () {
      final s = go(MediaAudio.duck, MediaAudio.stop);
      expect(s.ops, [MixOp.pause]);
      expect(s.paused, isFalse);
      final after = go(MediaAudio.stop, MediaAudio.normal, paused: false, playing: false);
      expect(after.ops, [MixOp.restoreVolume]);
      expect(after.ops.contains(MixOp.play), isFalse);
    });

    test('SOS khi đang tạm dừng vì Vy: bỏ cờ phát tiếp', () {
      final s = go(MediaAudio.pause, MediaAudio.stop, paused: true, playing: false);
      expect(s.paused, isFalse);
    });
  });

  test('âm lượng hạ còn 20%, tối thiểu 5, và nguyên bản khi bình thường', () {
    expect(effectiveVolume(100, MediaAudio.normal), 100);
    expect(effectiveVolume(100, MediaAudio.duck), 20);
    expect(effectiveVolume(40, MediaAudio.duck), 8);
    expect(effectiveVolume(10, MediaAudio.duck), 5);
  });

  group('bộ điều phối theo thời gian', () {
    ProviderContainer make() {
      final c = ProviderContainer(overrides: [vyCoreProvider.overrideWith(_FakeVy.new)]);
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('Vy mở → hạ tiếng; nói quá 8 giây → tạm dừng; đóng → bình thường', (t) async {
      final c = make();
      c.listen(mediaAudioProvider, (_, _) {});
      final vy = c.read(vyCoreProvider.notifier) as _FakeVy;
      expect(c.read(mediaAudioProvider), MediaAudio.normal);
      vy.show(view(VyPhase.listening));
      expect(c.read(mediaAudioProvider), MediaAudio.duck);
      vy.show(view(VyPhase.speaking));
      expect(c.read(mediaAudioProvider), MediaAudio.duck);
      await t.pump(const Duration(seconds: 7));
      expect(c.read(mediaAudioProvider), MediaAudio.duck);
      await t.pump(const Duration(seconds: 2));
      expect(c.read(mediaAudioProvider), MediaAudio.pause);
      vy.show(view(VyPhase.listening));
      expect(c.read(mediaAudioProvider), MediaAudio.duck);
      vy.show(const VyView());
      expect(c.read(mediaAudioProvider), MediaAudio.normal);
    });

    testWidgets('Vy nói ngắn (dưới 8 giây) rồi chuyển sang nghe thì không dừng video', (t) async {
      final c = make();
      c.listen(mediaAudioProvider, (_, _) {});
      final vy = c.read(vyCoreProvider.notifier) as _FakeVy;
      vy.show(view(VyPhase.speaking));
      await t.pump(const Duration(seconds: 5));
      vy.show(view(VyPhase.listening));
      await t.pump(const Duration(seconds: 20));
      expect(c.read(mediaAudioProvider), MediaAudio.duck);
    });

    testWidgets('Live không có pha "nói" nên chỉ hạ tiếng, không tự dừng', (t) async {
      final c = make();
      c.listen(mediaAudioProvider, (_, _) {});
      final vy = c.read(vyCoreProvider.notifier) as _FakeVy;
      vy.show(view(VyPhase.ready, e: VyEngine.live));
      await t.pump(const Duration(seconds: 30));
      expect(c.read(mediaAudioProvider), MediaAudio.duck);
    });

    testWidgets('màn SOS mở rồi đóng: dừng hẳn rồi trở lại bình thường (chỉ trạng thái, không phát lại)', (t) async {
      final c = make();
      c.listen(mediaAudioProvider, (_, _) {});
      c.read(mediaInterruptsProvider.notifier).add('sos');
      expect(c.read(mediaAudioProvider), MediaAudio.stop);
      c.read(mediaInterruptsProvider.notifier).remove('sos');
      expect(c.read(mediaAudioProvider), MediaAudio.normal);
    });
  });
}
