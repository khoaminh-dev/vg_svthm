import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vg_svthm/core/router/app_router.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/bp/domain/bp_models.dart';
import 'package:vg_svthm/features/family/domain/family_models.dart';
import 'package:vg_svthm/features/family/presentation/family_providers.dart';
import 'package:vg_svthm/features/bp/domain/bp_repository.dart';
import 'package:vg_svthm/features/bp/presentation/providers/bp_providers.dart';
import 'package:vg_svthm/features/safety/domain/safety_models.dart';
import 'package:vg_svthm/features/safety/presentation/safety_providers.dart';
import 'package:vg_svthm/features/safety/presentation/sos_widgets.dart' show phoneLauncherProvider;
import 'package:vg_svthm/features/voice/core/vy_card.dart';
import 'package:vg_svthm/features/voice/data/voice_actions.dart';
import 'package:vg_svthm/features/voice/domain/voice_models.dart';
import 'package:vg_svthm/features/voice/presentation/vy_cards.dart';

class FakeBpRepo implements BpRepository {
  final added = <BpReading>[];
  bool fail = false;

  @override
  Future<void> add(BpReading r) async {
    if (fail) throw Exception('mạng');
    added.add(r);
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<BpReading>> list({int limit = 200, String? ownerId}) async => added;
}

VoiceTask task(String intent, [Map<String, String> slots = const {}]) => VoiceTask(intent: intent, slots: slots);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nhập số đo bằng giọng (recordBp)', () {
    late FakeBpRepo repo;
    late ProviderContainer c;

    setUp(() {
      repo = FakeBpRepo();
      c = ProviderContainer(overrides: [
        bpRepositoryProvider.overrideWithValue(repo),
        routerProvider.overrideWithValue(GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())])),
      ]);
    });
    tearDown(() => c.dispose());

    test('ghi đúng số, nguồn "manual" kèm ghi chú, hiện thẻ Huyết áp và nói mức', () async {
      final say = await c.read(voiceActionsProvider).execute(
        task('record_bp', {'systolic': '130', 'diastolic': '80', 'pulse': '72'}),
        const [],
        'bác',
      );
      expect(repo.added.length, 1);
      final r = repo.added.single;
      expect([r.systolic, r.diastolic, r.pulse], [130, 80, 72]);
      expect(r.source, 'manual'); // cột source chỉ nhận ocr_ai/ocr_local/manual
      expect(r.note, 'Nhập bằng giọng nói');
      expect(say, contains('130 trên 80, mạch 72'));
      final card = c.read(vyCardProvider)! as BpCard;
      expect([card.systolic, card.diastolic, card.pulse], [130, 80, 72]);
      expect(card.when, 'vừa ghi xong');
    });

    test('không có mạch thì ghi không mạch', () async {
      await c.read(voiceActionsProvider).execute(task('record_bp', {'systolic': '118', 'diastolic': '76', 'pulse': ''}), const [], 'bác');
      expect(repo.added.single.pulse, isNull);
    });

    test('app kiểm tra lại: số vô lý hoặc thiếu thì KHÔNG ghi', () async {
      final a = c.read(voiceActionsProvider);
      for (final slots in [
        {'systolic': '80', 'diastolic': '130', 'pulse': ''},
        {'systolic': '300', 'diastolic': '100', 'pulse': ''},
        {'systolic': '130', 'diastolic': '30', 'pulse': ''},
        {'systolic': '130', 'diastolic': '130', 'pulse': ''},
        {'systolic': 'abc', 'diastolic': '80', 'pulse': ''},
        <String, String>{},
      ]) {
        final say = await a.execute(task('record_bp', slots), const [], 'bác');
        expect(say, isNotNull);
        expect(say, anyOf(contains('chưa hợp lý'), contains('chưa ghi được')));
      }
      expect(repo.added, isEmpty);
      expect(c.read(vyCardProvider), isNull);
    });

    test('mạch ngoài khoảng bị bỏ nhưng vẫn ghi số đo; lỗi mạng thì báo và không hiện thẻ', () async {
      await c.read(voiceActionsProvider).execute(task('record_bp', {'systolic': '130', 'diastolic': '80', 'pulse': '400'}), const [], 'bác');
      expect(repo.added.single.pulse, isNull);
      repo.added.clear();
      c.read(vyCardProvider.notifier).clear();
      repo.fail = true;
      final say = await c.read(voiceActionsProvider).execute(task('record_bp', {'systolic': '130', 'diastolic': '80', 'pulse': ''}), const [], 'bác');
      expect(say, contains('chưa được'));
      expect(c.read(vyCardProvider), isNull);
    });
  });

  group('Đọc tin nhắn', () {
    ProviderContainer make(List<IncomingMsg> msgs) => ProviderContainer(overrides: [
      recentIncomingMessagesProvider.overrideWith((ref) async => msgs),
      routerProvider.overrideWithValue(GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())])),
    ]);

    test('đọc tối đa 2 tin mới nhất, thẻ có tối đa 3 dòng, nói số tin còn lại', () async {
      final now = DateTime.now();
      final c = make([
        for (var i = 1; i <= 5; i++) IncomingMsg(roomId: 'r$i', from: 'Giang $i', text: 'Tin số $i', at: now),
      ]);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('read_messages'), const [], 'bác');
      expect(say, contains('có 5 tin nhắn'));
      expect(say, contains('Giang 1 nhắn: Tin số 1'));
      expect(say, contains('Giang 2 nhắn: Tin số 2'));
      expect(say, isNot(contains('Tin số 3')));
      expect(say, contains('Còn 3 tin nữa'));
      final card = c.read(vyCardProvider)! as MsgCard;
      expect(card.rows.length, 3);
      expect(card.replacesSpeech, isFalse);
      // hỏi trả lời, kèm nút "Trả lời <người gửi>" và "Dạ" (đi qua luồng gửi tin có xác nhận)
      expect(say, contains('muốn trả lời Giang 1 không ạ?'));
      expect(card.actions.map((a) => a.label), ['Trả lời Giang 1', 'Dạ']);
      expect(card.actions.every((a) => a.keepOpen), isTrue);
    });

    test('không có tin nào: nói rõ, không hiện thẻ', () async {
      final c = make(const []);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).execute(task('read_messages'), const [], 'bác');
      expect(say, contains('không có tin nhắn mới'));
      expect(c.read(vyCardProvider), isNull);
    });
  });

  group('Gọi điện (callContact)', () {
    final calls = <String>[];
    ProviderContainer make(List<CardContact> contacts) {
      calls.clear();
      return ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(const AuthUser(id: 'me', role: AppRole.elder)),
        emergencyCardProvider('me').overrideWith((ref) async => EmergencyCard(contacts: contacts)),
        phoneLauncherProvider.overrideWithValue((n) async => calls.add(n)),
      ]);
    }

    const people = [
      CardContact(name: 'Minh (con trai)', phone: '0901 234 567'),
      CardContact(name: 'Hoa', phone: '0912345678'),
      CardContact(name: 'Cô Lan', phone: '0988111222'),
      CardContact(name: 'Lan Anh', phone: '0977333444'),
      CardContact(name: 'Không số', phone: ''),
    ];

    test('khớp một người: thẻ đếm ngược 3 giây, chưa gọi ngay', () async {
      final c = make(people);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).callContact('con trai', 'bác');
      expect(say, contains('sau 3 giây'));
      final card = c.read(vyCardProvider)! as CallCard;
      expect([card.name, card.number, card.seconds], ['Minh (con trai)', '0901 234 567', 3]);
      expect(calls, isEmpty); // việc gọi chỉ xảy ra khi hết đếm ngược
    });

    test('115: đếm ngược 2 giây, không cần danh bạ', () async {
      final c = make(const []);
      addTearDown(c.dispose);
      await c.read(voiceActionsProvider).callContact('115', 'bác');
      final card = c.read(vyCardProvider)! as CallCard;
      expect([card.number, card.seconds], ['115', 2]);
    });

    test('không thấy, trùng tên, người không có số, hoặc không nói ai: KHÔNG hiện thẻ gọi', () async {
      final c = make(people);
      addTearDown(c.dispose);
      final a = c.read(voiceActionsProvider);
      expect(await a.callContact('bà nội', 'bác'), contains('chưa thấy số'));
      expect(await a.callContact('lan', 'bác'), contains('nhiều người'));
      expect(await a.callContact('không số', 'bác'), contains('chưa thấy số'));
      expect(await a.callContact('', 'bác'), contains('gọi cho ai'));
      expect(c.read(vyCardProvider), isNull);
    });

    test('matchContacts: tên chứa cụm, cụm chứa tên, mọi từ của cụm có trong tên', () {
      expect(VoiceActions.matchContacts('hoa', people).map((p) => p.name), ['Hoa']);
      expect(VoiceActions.matchContacts('co lan', people).map((p) => p.name), ['Cô Lan']);
      expect(VoiceActions.matchContacts('anh lan', people).map((p) => p.name), ['Lan Anh']);
      expect(VoiceActions.matchContacts('bo', people), isEmpty);
    });

    Future<void> showCall(WidgetTester t, CallCard card) async {
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: VyCardView(card: card, onAction: (a) => a.run())),
        ),
      );
    }

    testWidgets('đếm ngược 3 → 2 → 1 rồi gọi ĐÚNG MỘT LẦN, hiện "Đang gọi"', (t) async {
      var called = 0;
      await showCall(t, CallCard(name: 'Minh', number: '0901', seconds: 3, onCall: () => called++));
      expect(find.byKey(const Key('vy-call-count')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
      expect(called, 0);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
      expect(called, 0);
      await t.pump(const Duration(seconds: 1));
      expect(called, 1);
      expect(find.text('Đang gọi…'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      expect(called, 1);
    });

    testWidgets('bấm Huỷ giữa chừng hoặc thẻ bị gỡ (đóng Vy) thì KHÔNG gọi', (t) async {
      var called = 0;
      var cancelled = 0;
      final card = CallCard(
        name: 'Minh',
        number: '0901',
        seconds: 3,
        onCall: () => called++,
        actions: [VyCardAction(label: 'Huỷ', primary: true, run: () => cancelled++)],
      );
      await showCall(t, card);
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Huỷ'));
      expect(cancelled, 1);
      // gỡ thẻ khỏi màn hình (như Vy đóng): bộ đếm bị huỷ
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
      expect(called, 0);
    });
  });

  group('Gọi theo quan hệ của người thân liên kết', () {
    FamilyLink link(String name, String rel, {bool owner = true, String status = 'active'}) => FamilyLink(
      linkId: name,
      role: owner ? 'owner' : 'carer',
      otherId: 'id-$name',
      otherName: name,
      relation: Relation.of(rel),
      perms: const {},
      status: status,
      createdAt: DateTime(2026),
    );

    ProviderContainer make(List<CardContact> contacts, List<FamilyLink> links) => ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(const AuthUser(id: 'me', role: AppRole.elder)),
      emergencyCardProvider('me').overrideWith((ref) async => EmergencyCard(contacts: contacts)),
      familyLinksProvider.overrideWith((ref) async => links),
      phoneLauncherProvider.overrideWithValue((n) async {}),
      routerProvider.overrideWithValue(GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())])),
    ]);

    const minh = CardContact(name: 'Minh', phone: '0901234567');

    test('"con trai" khớp người thân có quan hệ "con" rồi lấy số theo tên trong thẻ', () async {
      final c = make([minh, const CardContact(name: 'Hoa', phone: '0912345678')], [link('Minh', 'con'), link('Hoa', 'khac')]);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).callContact('con trai', 'bác');
      expect(say, contains('Minh'));
      final card = c.read(vyCardProvider)! as CallCard;
      expect([card.name, card.number], ['Minh', '0901234567']);
    });

    test('người thân có quan hệ phù hợp nhưng thẻ y tế chưa có số: nói rõ và đưa nút mở thẻ y tế', () async {
      final c = make(const [], [link('Minh', 'con')]);
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).callContact('con trai', 'bác');
      expect(say, contains('Minh'));
      expect(say, contains('chưa có số điện thoại'));
      final card = c.read(vyCardProvider)! as NoticeCard;
      expect(card.title, 'Chưa có số của Minh');
      expect(card.actions.single.label, 'Mở thẻ y tế');
    });

    test('hai người con đều có số: hỏi rõ tên; chỉ liên kết đang hoạt động và do mình làm chủ mới tính', () async {
      final c = make(
        [minh, const CardContact(name: 'Lan', phone: '0988111222')],
        [link('Minh', 'con'), link('Lan', 'con'), link('Bao', 'con', owner: false), link('Tuan', 'con', status: 'revoked')],
      );
      addTearDown(c.dispose);
      final say = await c.read(voiceActionsProvider).callContact('con', 'bác');
      expect(say, contains('nhiều người'));
      expect(c.read(vyCardProvider), isNull);
    });

    test('gọi theo tên trực tiếp vẫn ưu tiên thẻ y tế; không khớp gì thì báo không thấy', () async {
      final c = make([minh], [link('Minh', 'con')]);
      addTearDown(c.dispose);
      await c.read(voiceActionsProvider).callContact('minh', 'bác');
      expect((c.read(vyCardProvider)! as CallCard).number, '0901234567');
      c.read(vyCardProvider.notifier).clear();
      final say = await c.read(voiceActionsProvider).callContact('bà nội', 'bác');
      expect(say, contains('chưa thấy số'));
      expect(c.read(vyCardProvider), isNull);
    });
  });

  testWidgets('thẻ Tin nhắn: người gửi, giờ, nội dung; chạm dòng mở cuộc trò chuyện', (t) async {
    final opened = <String>[];
    final card = MsgCard(rows: [
      MsgRow(from: 'Giang', time: 'hôm nay 07:05', text: 'Mai con về sớm', onOpen: () => opened.add('giang')),
      const MsgRow(from: 'Hoa', time: 'hôm qua 19:30', text: 'gửi một hình ảnh'),
    ]);
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: VyCardView(card: card, onAction: (a) => a.run()))),
    );
    expect(find.text('Giang'), findsOneWidget);
    expect(find.text('Mai con về sớm'), findsOneWidget);
    expect(find.text('hôm qua 19:30'), findsOneWidget);
    await t.tap(find.byKey(const Key('vy-msg-0')));
    expect(opened, ['giang']);
  });
}
