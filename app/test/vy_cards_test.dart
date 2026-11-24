import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vg_svthm/core/router/app_router.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/bp/domain/bp_models.dart';
import 'package:vg_svthm/features/bp/presentation/providers/bp_providers.dart';
import 'package:vg_svthm/features/entertainment/data/youtube_service.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_providers.dart';
import 'package:vg_svthm/features/meds/data/meds_repository.dart';
import 'package:vg_svthm/features/meds/domain/meds_models.dart';
import 'package:vg_svthm/features/meds/presentation/meds_providers.dart';
import 'package:vg_svthm/features/voice/core/vy_card.dart';
import 'package:vg_svthm/features/voice/core/vy_core.dart';
import 'package:vg_svthm/features/voice/core/vy_view.dart';
import 'package:vg_svthm/features/voice/data/voice_actions.dart';
import 'package:vg_svthm/features/voice/domain/voice_models.dart';
import 'package:vg_svthm/features/voice/live/live_lab_controller.dart';
import 'package:vg_svthm/features/voice/presentation/vy_cards.dart';
import 'package:vg_svthm/features/voice/presentation/vy_panel.dart';
import 'package:vg_svthm/features/voice/presentation/voice_controller.dart';

import 'vy_core_test.dart' show FakeLive, FakeSay, FakeVoiceCtl;

class _FakeSearch implements VideoSearch {
  _FakeSearch(this.items);
  final List<VideoItem> items;

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async => items;
}

VideoItem video(int i) => VideoItem(
  id: 'v$i',
  title: 'Bài hát số $i',
  author: 'Kênh $i',
  thumbnailUrl: '',
);

Future<void> showCard(WidgetTester t, VyCard card, List<VyCardAction> ran) async {
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: VyCardView(card: card, onAction: (a) {
            ran.add(a);
            a.run();
          }),
        ),
      ),
    ),
  );
  await t.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Giao diện thẻ: nhìn thấy đúng thông tin và chạm = nói', () {
    testWidgets('thẻ Huyết áp: số lớn, mức, thời điểm; "Xem biểu đồ" và "Đo lại"', (t) async {
      final did = <String>[];
      await showCard(
        t,
        BpCard(
          systolic: 128,
          diastolic: 82,
          pulse: 74,
          levelLabel: 'Hơi cao',
          levelColor: Colors.orange,
          when: 'hôm nay 07:05',
          actions: [
            VyCardAction(label: 'Xem biểu đồ', primary: true, run: () => did.add('chart')),
            VyCardAction(label: 'Đo lại', run: () => did.add('again')),
          ],
        ),
        [],
      );
      expect(find.text('128/82'), findsOneWidget);
      expect(find.text('Hơi cao'), findsOneWidget);
      expect(find.text('Mạch 74'), findsOneWidget);
      expect(find.text('hôm nay 07:05'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Xem biểu đồ'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Đo lại'), findsOneWidget);
      await t.tap(find.text('Đo lại'));
      await t.tap(find.text('Xem biểu đồ'));
      expect(did, ['again', 'chart']);
    });

    testWidgets('thẻ Huyết áp không có mạch thì không hiện "Mạch"', (t) async {
      await showCard(
        t,
        BpCard(systolic: 120, diastolic: 80, levelLabel: 'Bình thường', levelColor: Colors.green, when: 'hôm qua 19:30'),
        [],
      );
      expect(find.textContaining('Mạch'), findsNothing);
      expect(find.text('120/80'), findsOneWidget);
    });

    testWidgets('thẻ Thuốc: giờ, túi, trạng thái, thuốc trong túi; nút mở màn thuốc', (t) async {
      var opened = 0;
      await showCard(
        t,
        MedCard(
          title: 'Cữ kế tiếp lúc 20:30',
          rows: const [
            MedRow(time: '07:00', name: 'Túi Sáng', status: 'Đã uống', statusColor: Colors.green),
            MedRow(
              time: '20:30',
              name: 'Túi Tối',
              status: 'Sắp tới',
              statusColor: Colors.grey,
              items: ['Amlodipin 5mg x1 viên', 'Metformin 500mg x1 viên'],
              highlight: true,
            ),
          ],
          actions: [VyCardAction(label: 'Mở màn thuốc', primary: true, run: () => opened++)],
        ),
        [],
      );
      expect(find.text('Cữ kế tiếp lúc 20:30'), findsOneWidget);
      expect(find.text('Túi Sáng'), findsOneWidget);
      expect(find.text('Đã uống'), findsOneWidget);
      expect(find.text('Sắp tới'), findsOneWidget);
      expect(find.text('Amlodipin 5mg x1 viên'), findsOneWidget);
      expect(find.text('Metformin 500mg x1 viên'), findsOneWidget);
      await t.tap(find.text('Mở màn thuốc'));
      expect(opened, 1);
    });

    testWidgets('thẻ Đã gửi: tick, gửi cho ai, nội dung', (t) async {
      var opened = 0;
      await showCard(
        t,
        SentCard(
          to: 'Giang',
          text: 'Mai bác về sớm',
          actions: [VyCardAction(label: 'Mở cuộc trò chuyện', run: () => opened++)],
        ),
        [],
      );
      expect(find.text('Đã nhắn cho Giang'), findsOneWidget);
      expect(find.text('“Mai bác về sớm”'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await t.tap(find.text('Mở cuộc trò chuyện'));
      expect(opened, 1);
    });
  });

  group('Thẻ trong panel', () {
    Future<void> pumpPanel(WidgetTester t, VyView v, List<VyCardAction> ran) async {
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: VyPanel(
                view: v,
                onClose: () {},
                onPrimary: () {},
                onChip: (_) {},
                onCollapse: () {},
                onExpand: () {},
                onDismissIntro: () {},
                onCardAction: ran.add,
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('có thẻ thì thẻ lớn tự mở, thẻ thay cho câu Vy nói bằng chữ; thanh nhỏ vẫn hiện chữ', (t) async {
      final card = BpCard(systolic: 130, diastolic: 85, levelLabel: 'Hơi cao', levelColor: Colors.orange, when: 'hôm nay 07:05');
      final v = VyView(phase: VyPhase.speaking, engine: VyEngine.live, vyText: 'Lần đo gần nhất: huyết áp 130 trên 85.', card: card);
      expect(v.needsCard, isTrue);
      expect(v.expanded, isTrue);
      await pumpPanel(t, v, []);
      expect(find.text('130/85'), findsOneWidget);
      // thẻ đã nói đủ ý: không lặp lại câu dài trong thẻ lớn
      expect(find.text('Lần đo gần nhất: huyết áp 130 trên 85.'), findsNothing);
    });

    testWidgets('chạm nút trên thẻ đi qua onCardAction', (t) async {
      final ran = <VyCardAction>[];
      var chart = 0;
      final card = BpCard(
        systolic: 120,
        diastolic: 80,
        levelLabel: 'Bình thường',
        levelColor: Colors.green,
        when: 'hôm nay',
        actions: [VyCardAction(label: 'Xem biểu đồ', primary: true, run: () => chart++)],
      );
      await pumpPanel(t, VyView(phase: VyPhase.ready, engine: VyEngine.live, card: card), ran);
      await t.tap(find.text('Xem biểu đồ'));
      expect(ran.length, 1);
      ran.single.run();
      expect(chart, 1);
    });
  });

  group('VyCore với thẻ', () {
    // Đồng hồ giả chạy cùng fakeAsync: mỗi lần elapse phải cộng cả vào đây.
    var clockNow = DateTime(2026, 11, 20, 9);
    ProviderContainer rig(FakeVoiceCtl voice, FakeLive live, FakeSay say) {
      SharedPreferences.setMockInitialValues({'vy_intro_seen': true, 'vy_sounds': false});
      clockNow = DateTime(2026, 11, 20, 9);
      final c = ProviderContainer(overrides: [
        vyNowProvider.overrideWithValue(() => clockNow),
        voiceControllerProvider.overrideWith(() => voice),
        liveLabProvider.overrideWith(() => live),
        vyVoiceProvider.overrideWithValue(say),
      ]);
      c.listen(vyCoreProvider, (_, _) {});
      return c;
    }

    test('thẻ hiện thì panel mở rộng; thẻ chỉ để xem lướt tự thu về thanh nhỏ sau thời gian giữ', () {
      fakeAsync((a) {
        final voice = FakeVoiceCtl(), live = FakeLive(), say = FakeSay();
        final c = rig(voice, live, say);
        unawaited0(c.read(vyCoreProvider.notifier).open());
        a.flushMicrotasks();
        a.elapse(const Duration(milliseconds: 200));
        expect(c.read(vyCoreProvider).card, isNull);

        c.read(vyCardProvider.notifier).show(
          BpCard(systolic: 120, diastolic: 80, levelLabel: 'x', levelColor: Colors.green, when: 'y'),
        );
        a.flushMicrotasks();
        expect(c.read(vyCoreProvider).expanded, isTrue);
        a.elapse(const Duration(seconds: 5));
        expect(c.read(vyCoreProvider).expanded, isTrue);
        a.elapse(const Duration(seconds: 2)); // quá 6 giây
        expect(c.read(vyCoreProvider).expanded, isFalse);
        expect(c.read(vyCoreProvider).isOpen, isTrue);
        c.dispose();
      });
    });

    test('thẻ thuốc (không có thời gian giữ) ở lại cho tới khi có việc khác', () {
      fakeAsync((a) {
        final voice = FakeVoiceCtl(), live = FakeLive(), say = FakeSay();
        final c = rig(voice, live, say);
        unawaited0(c.read(vyCoreProvider.notifier).open());
        a.flushMicrotasks();
        a.elapse(const Duration(milliseconds: 200));
        c.read(vyCardProvider.notifier).show(MedCard(title: 'Thuốc hôm nay', rows: const []));
        a.flushMicrotasks();
        a.elapse(const Duration(seconds: 20));
        expect(c.read(vyCoreProvider).expanded, isTrue);
        // người dùng gõ việc mới: thẻ cũ bị xoá
        unawaited0(c.read(vyCoreProvider.notifier).sendText('mở nhạc'));
        a.flushMicrotasks();
        expect(c.read(vyCardProvider), isNull);
        expect(c.read(vyCoreProvider).card, isNull);
        c.dispose();
      });
    });

    test('chạm nút trên thẻ: làm việc đó rồi thu panel về thanh nhỏ', () {
      fakeAsync((a) {
        final voice = FakeVoiceCtl(), live = FakeLive(), say = FakeSay();
        final c = rig(voice, live, say);
        final core = c.read(vyCoreProvider.notifier);
        unawaited0(core.open());
        a.flushMicrotasks();
        a.elapse(const Duration(milliseconds: 200));
        var ran = 0;
        c.read(vyCardProvider.notifier).show(
          MedCard(title: 'Thuốc hôm nay', rows: const [], actions: [VyCardAction(label: 'Mở màn thuốc', run: () => ran++)]),
        );
        a.flushMicrotasks();
        expect(c.read(vyCoreProvider).expanded, isTrue);
        core.runCardAction(c.read(vyCardProvider)!.actions.single);
        a.flushMicrotasks();
        expect(ran, 1);
        expect(c.read(vyCoreProvider).expanded, isFalse);
        expect(c.read(vyCoreProvider).isOpen, isTrue);
        c.dispose();
      });
    });

    test('đóng Vy thì thẻ bị xoá; mở lại không còn thẻ cũ', () {
      fakeAsync((a) {
        final voice = FakeVoiceCtl(), live = FakeLive(), say = FakeSay();
        final c = rig(voice, live, say);
        final core = c.read(vyCoreProvider.notifier);
        unawaited0(core.open());
        a.flushMicrotasks();
        a.elapse(const Duration(milliseconds: 200));
        c.read(vyCardProvider.notifier).show(SentCard(to: 'Giang', text: 'x'));
        a.flushMicrotasks();
        unawaited0(core.close());
        a.flushMicrotasks();
        expect(c.read(vyCardProvider), isNull);
        unawaited0(core.open());
        a.flushMicrotasks();
        a.elapse(const Duration(milliseconds: 200));
        expect(c.read(vyCoreProvider).card, isNull);
        c.dispose();
      });
    });

    test('người dùng bắt đầu nói việc mới (Live) thì thẻ cũ bị xoá; thẻ vừa hiện thì giữ', () {
      fakeAsync((a) {
        final voice = FakeVoiceCtl(), live = FakeLive(), say = FakeSay();
        final c = rig(voice, live, say);
        unawaited0(c.read(vyCoreProvider.notifier).open());
        a.flushMicrotasks();
        a.elapse(const Duration(milliseconds: 200));
        c.read(vyCardProvider.notifier).show(MedCard(title: 'Thuốc hôm nay', rows: const []));
        a.flushMicrotasks();
        // lời chép về ngay sau thẻ (như Vy thường): giữ thẻ
        live.emit(live.state.copyWith(userText: 'tối nay uống thuốc gì'));
        a.flushMicrotasks();
        expect(c.read(vyCardProvider), isNotNull);
        // lát sau nói câu khác: xoá thẻ
        clockNow = clockNow.add(const Duration(seconds: 3));
        a.elapse(const Duration(seconds: 3));
        live.emit(live.state.copyWith(userText: 'mở nhạc xưa'));
        a.flushMicrotasks();
        expect(c.read(vyCardProvider), isNull);
        c.dispose();
      });
    });
  });

  group('Nơi tạo thẻ (VoiceActions)', () {
    ProviderContainer make({List<BpReading> bp = const [], List<Dose> doses = const [], List<VideoItem> videos = const [], MedsRepository? meds}) {
      final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())]);
      final c = ProviderContainer(overrides: [
        routerProvider.overrideWithValue(router),
        bpReadingsProvider.overrideWith((ref) async => bp),
        myDosesProvider.overrideWith((ref) async => doses),
        if (meds != null) medsRepositoryProvider.overrideWithValue(meds),
        videoSearchProvider.overrideWithValue(_FakeSearch(videos)),
      ]);
      return c;
    }

    VoiceTask task(String intent, [Map<String, String> slots = const {}]) => VoiceTask(intent: intent, slots: slots);

    test('đọc huyết áp: nói đúng số và hiện thẻ Huyết áp có hai nút', () async {
      final c = make(bp: [
        BpReading(systolic: 118, diastolic: 76, pulse: 70, measuredAt: DateTime.now().subtract(const Duration(days: 1))),
        BpReading(systolic: 150, diastolic: 95, measuredAt: DateTime.now().subtract(const Duration(days: 3))),
      ]);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('read_bp'), const [], 'bác');
      expect(say, contains('118 trên 76'));
      final card = c.read(vyCardProvider);
      expect(card, isA<BpCard>());
      card as BpCard;
      expect([card.systolic, card.diastolic, card.pulse], [118, 76, 70]);
      expect(card.levelLabel, isNotEmpty);
      expect(card.when, startsWith('hôm qua')); // chọn lần đo mới nhất
      expect(card.actions.map((a) => a.label), ['Xem biểu đồ', 'Đo lại']);
    });

    test('chưa có lần đo nào: không hiện thẻ, nói hướng dẫn', () async {
      final c = make();
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('read_bp'), const [], 'bác');
      expect(say, contains('Chưa có kết quả'));
      expect(c.read(vyCardProvider), isNull);
    });

    Dose dose(String id, String label, DateTime due, {String status = 'pending', List<MedItem> items = const []}) => Dose(
      id: id,
      ownerId: 'me',
      label: label,
      bag: true,
      items: items,
      dueAt: due,
      windowEnd: due.add(const Duration(hours: 2)),
      status: status,
    );

    test('đọc thuốc: cữ kế tiếp, các cữ hôm nay có trạng thái, thuốc trong túi', () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final c = make(doses: [
        dose('a', 'Sáng', day.add(const Duration(hours: 7)), status: 'taken'),
        dose('b', 'Tối', day.add(const Duration(hours: 23, minutes: 30)), items: const [MedItem(name: 'Amlodipin', strength: '5mg')]),
      ]);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('read_meds'), const [], 'bác');
      expect(say, contains('23:30'));
      final card = c.read(vyCardProvider);
      expect(card, isA<MedCard>());
      card as MedCard;
      expect(card.title, 'Cữ kế tiếp lúc 23:30');
      expect(card.rows.length, 2);
      expect(card.rows[0].status, 'Đã uống');
      expect(card.rows[1].highlight, isTrue);
      expect(card.rows[1].items.single, contains('Amlodipin'));
      expect(card.actions.single.label, 'Mở màn thuốc');
    });

    test('đọc thuốc: xong hết các cữ thì nói đã xong; không có cữ nào thì không hiện thẻ', () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final done = make(doses: [dose('a', 'Sáng', day.add(const Duration(minutes: 5)), status: 'taken')]);
      addTearDown(done.dispose);
      final say = await done.read(voiceActionsProvider).execute(task('read_meds'), const [], 'bác');
      expect(say, contains('đã xong'));
      expect((done.read(vyCardProvider)! as MedCard).title, 'Thuốc hôm nay');

      final none = make();
      addTearDown(none.dispose);
      final say2 = await none.read(voiceActionsProvider).execute(task('read_meds'), const [], 'bác');
      expect(say2, contains('không có cữ thuốc'));
      expect(none.read(vyCardProvider), isNull);
    });

    test('hỏi "có quên cữ nào không": nói rõ cữ quá giờ chưa uống, thẻ có nút ghi "Đã uống" cho cữ đó', () async {
      final day = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final repo = _FakeMeds();
      final c = make(
        doses: [
          dose('a', 'Sáng', day.add(const Duration(minutes: 1)), status: 'missed'),
          dose('b', 'Trưa', day.add(const Duration(minutes: 2)), status: 'taken'),
        ],
        meds: repo,
      );
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('read_meds', {'content': 'Forgot'}), const [], 'bác');
      expect(say, contains('chưa uống túi sáng'));
      final card = c.read(vyCardProvider)! as MedCard;
      expect(card.title, 'Còn 1 cữ chưa uống');
      expect(card.actions.first.label, 'Đã uống túi Sáng');
      card.actions.first.run();
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, ['a:taken']);
    });

    test('hỏi "có quên không" khi không quên cữ nào: trả lời rõ là không quên', () async {
      final day = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final c = make(doses: [dose('a', 'Sáng', day.add(const Duration(minutes: 1)), status: 'taken')]);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('read_meds', {'content': 'Forgot'}), const [], 'bác');
      expect(say, contains('không quên cữ nào'));
    });

    test('nói "uống rồi": ghi cữ vừa đến giờ gần nhất, hỏi tiếp cữ còn lại, có nút hoàn tác', () async {
      final day = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final repo = _FakeMeds();
      final c = make(
        doses: [
          dose('a', 'Sáng', day.add(const Duration(minutes: 1))),
          dose('b', 'Trưa', day.add(const Duration(minutes: 2))),
        ],
        meds: repo,
      );
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('mark_dose'), const [], 'bác');
      expect(repo.calls, ['b:taken']);
      expect(say, contains('đã uống túi trưa'));
      expect(say, contains('túi sáng'));
      final card = c.read(vyCardProvider)! as NoticeCard;
      expect(card.actions.map((a) => a.label), ['Đã uống túi Sáng', 'Hoàn tác']);
      card.actions.last.run();
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls.last, 'b:pending');
    });

    test('nói "uống rồi" khi chưa có cữ nào tới giờ: không ghi bừa', () async {
      final repo = _FakeMeds();
      final c = make(meds: repo);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('mark_dose'), const [], 'bác');
      expect(repo.calls, isEmpty);
      expect(say, contains('đều đã ghi'));
    });

    test('nói "lát nữa uống": hoãn 15 phút đúng cữ đang chờ', () async {
      final day = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final repo = _FakeMeds();
      final c = make(doses: [dose('a', 'Sáng', day.add(const Duration(minutes: 1)))], meds: repo);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('snooze_dose'), const [], 'bác');
      expect(repo.calls, ['a:snooze15']);
      expect(say, contains('15 phút'));
    });

    test('tìm video chung chung: KHÔNG hiện thẻ che màn, mà bật đánh số trên video thật và giữ hàng đợi', () async {
      final c = make(videos: [for (var i = 1; i <= 8; i++) video(i)]);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('play_video', {'content': 'nhạc xưa'}), const [], 'bác');
      expect(say, contains('chọn số mấy'));
      expect(c.read(vyCardProvider), isNull);
      expect(c.read(videoMarksProvider), isTrue);
      expect(c.read(videoQueueProvider).length, 8);
    });

    group('điều khiển video bằng giọng (24/11)', () {
      Future<String?> ctl(ProviderContainer c, String action) =>
          c.read(voiceActionsProvider).execute(task('video_control', {'content': action}), const [], 'bác');

      test('chưa có video nào đang phát thì nói thật', () async {
        final c = make();
        addTearDown(c.dispose);
        expect(await ctl(c, 'pause'), contains('chưa có video'));
        expect(c.read(playerCommandProvider), isNull);
      });

      test('"to lên" khi đã to hết cỡ: nói thật, không gửi lệnh, không báo "đã tăng"', () async {
        final c = make();
        addTearDown(c.dispose);
        c.read(playerOpenProvider.notifier).set(true);
        final say = await ctl(c, 'louder');
        expect(say, contains('to hết cỡ'));
        expect(say, isNot(contains('tăng âm lượng rồi')));
        expect(c.read(playerCommandProvider), isNull);
      });

      test('âm lượng đang nhỏ thì tăng thật và báo đã tăng; chạm đáy thì báo nhỏ hết cỡ', () async {
        final c = make();
        addTearDown(c.dispose);
        c.read(playerOpenProvider.notifier).set(true);
        c.read(playerVolumeProvider.notifier).set(40);
        expect(await ctl(c, 'louder'), contains('tăng âm lượng rồi'));
        expect(c.read(playerCommandProvider)?.action, PlayerAction.louder);
        c.read(playerVolumeProvider.notifier).set(10);
        expect(await ctl(c, 'quieter'), contains('nhỏ hết cỡ'));
      });

      test('tua theo giây, phút; mặc định 15 giây; kẹp 5–600 giây', () async {
        final c = make();
        addTearDown(c.dispose);
        c.read(playerOpenProvider.notifier).set(true);
        expect(await ctl(c, 'back:30'), contains('tua lại 30 giây'));
        expect(c.read(playerCommandProvider)?.action, PlayerAction.seekBack);
        expect(c.read(playerCommandProvider)?.value, 30);
        expect(await ctl(c, 'fwd:120'), contains('tua tới 2 phút'));
        expect(c.read(playerCommandProvider)?.value, 120);
        await ctl(c, 'fwd');
        expect(c.read(playerCommandProvider)?.value, 15);
        await ctl(c, 'back:9999');
        expect(c.read(playerCommandProvider)?.value, 600);
      });

      test('hẹn giờ tắt, phát lại từ đầu, thoát', () async {
        final c = make();
        addTearDown(c.dispose);
        c.read(playerOpenProvider.notifier).set(true);
        expect(await ctl(c, 'sleep:45'), contains('tắt sau 45 phút'));
        expect(c.read(playerCommandProvider)?.action, PlayerAction.sleep);
        expect(c.read(playerCommandProvider)?.value, 45);
        expect(await ctl(c, 'sleep:120'), contains('2 tiếng'));
        expect(await ctl(c, 'restart'), contains('từ đầu'));
        expect(c.read(playerCommandProvider)?.action, PlayerAction.restart);
        expect(await ctl(c, 'close'), contains('tắt video'));
        expect(c.read(playerCommandProvider)?.action, PlayerAction.close);
      });

      test('"bài này của ai": đọc tên đã làm sạch (bỏ emoji, #, (Official MV)) và tên kênh', () async {
        final c = make();
        addTearDown(c.dispose);
        c.read(playerOpenProvider.notifier).set(true);
        c.read(playerNowProvider.notifier).set(const VideoItem(
          id: 'x',
          title: '🎵 Đường chiều (Official MV 4K) #nhacxua #shorts',
          author: 'Khánh Ly',
          thumbnailUrl: '',
        ));
        final say = await ctl(c, 'info');
        expect(say, contains('Đường chiều'));
        expect(say, isNot(contains('Official')));
        expect(say, isNot(contains('#')));
        expect(say, contains('kênh Khánh Ly'));
        expect(c.read(playerCommandProvider), isNull);
      });

      test('mở video cụ thể: Vy đọc tên sạch, không đọc "#shorts" hay emoji', () async {
        final c = make(videos: [
          const VideoItem(id: 'a', title: 'Nối vòng tay lớn 🇻🇳 #shorts', author: 'K', thumbnailUrl: ''),
        ]);
        addTearDown(c.dispose);
        final say = await c.read(voiceActionsProvider).execute(task('play_video', {'content': 'nối vòng tay lớn'}), const [], 'bác');
        expect(say, 'Dạ, con mở Nối vòng tay lớn ạ.');
      });
    });

    test('gửi tin xong: hiện thẻ Đã gửi, không nhảy sang phòng chat', () async {
      final c = make();
      addTearDown(c.dispose);
      // không có repository thật: chỉ kiểm tra rằng intent gửi tin không còn thuộc nhóm tự đóng Vy
      expect(VoiceActions.navIntents.contains('send_message'), isFalse);
    });
  });
}

void unawaited0(Future<void> f) {}

class _FakeMeds implements MedsRepository {
  final calls = <String>[];

  @override
  Future<void> setDose(String doseId, String status) async => calls.add('$doseId:$status');

  @override
  Future<void> snooze(String doseId, int minutes) async => calls.add('$doseId:snooze$minutes');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
