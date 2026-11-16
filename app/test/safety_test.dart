import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/family/presentation/family_providers.dart';
import 'package:vg_svthm/features/meds/presentation/meds_providers.dart';
import 'package:vg_svthm/features/push/push_service.dart';
import 'package:vg_svthm/features/safety/data/safety_repository.dart';
import 'package:vg_svthm/features/safety/domain/safety_models.dart';
import 'package:vg_svthm/features/safety/presentation/emergency_card_screen.dart';
import 'package:vg_svthm/features/safety/presentation/safety_providers.dart';
import 'package:vg_svthm/features/safety/presentation/sos_screen.dart';
import 'package:vg_svthm/features/safety/presentation/sos_widgets.dart';

import 'family_test.dart' show FakeFamily, link;
import 'meds_test.dart' show FakeMeds, bigScreen;

class FakeSafety implements SafetyRepository {
  FakeSafety({this.event, this.cardData, this.failCard = false});

  SosEvent? event;
  EmergencyCard? cardData;
  bool failCard;
  final calls = <String>[];
  EmergencyCard? saved;
  String ackResult = 'ok';

  @override
  Future<String> triggerSos() async {
    calls.add('trigger');
    return 'sos1';
  }

  @override
  Future<String> ackSos(String id) async {
    calls.add('ack:$id');
    if (ackResult == 'ok' && event != null) {
      event = SosEvent(id: event!.id, ownerId: event!.ownerId, createdAt: event!.createdAt, handled: true, handledBy: 'me');
    }
    return ackResult;
  }

  @override
  Future<String> cancelSos(String id) async {
    calls.add('cancel:$id');
    event = SosEvent(id: id, ownerId: event!.ownerId, createdAt: event!.createdAt, handled: true, cancelled: true, handledBy: event!.ownerId);
    return 'ok';
  }

  @override
  Future<SosEvent?> sos(String id) async => event;

  @override
  Future<List<SosEvent>> openSos() async => [if (event != null && event!.open) event!];

  @override
  Future<EmergencyCard?> card(String ownerId) async => cardData;

  @override
  Future<void> saveCard(String ownerId, EmergencyCard c) async {
    if (failCard) throw Exception('x');
    saved = c;
  }
}

SosEvent sosEvent({String owner = 'me', bool handled = false, String? by}) => SosEvent(
  id: 's1',
  ownerId: owner,
  createdAt: DateTime(2026, 11, 16, 14, 5),
  handled: handled,
  handledBy: by,
);

Widget hostSos(Widget child, {required FakeSafety safety, required FakeFamily fam, List<String>? dialed}) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh')),
    safetyRepositoryProvider.overrideWithValue(safety),
    familyRepositoryProvider.overrideWithValue(fam),
    medsRepositoryProvider.overrideWithValue(FakeMeds()),
    phoneLauncherProvider.overrideWithValue((n) async => dialed?.add(n)),
  ],
  child: MaterialApp(theme: AppTheme.light, home: child),
);

const _card = EmergencyCard(
  bloodType: 'O+',
  allergies: 'Penicillin',
  ownPhone: '0912 345 678',
  contacts: [CardContact(name: 'Minh', phone: '0988 111 222')],
);

void main() {
  group('nút SOS giữ 3 giây', () {
    testWidgets('giữ đủ 3 giây thì gửi; thả sớm thì không và nhắc giữ đủ', (t) async {
      var n = 0;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SosHoldButton(onTriggered: () => n++))));
      // Thả sau 1 giây
      var g = await t.startGesture(t.getCenter(find.byKey(const Key('sos-button'))));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('Giữ thêm'), findsOneWidget);
      await g.up();
      await t.pump();
      expect(n, 0);
      expect(find.text('Giữ đủ 3 giây để gọi SOS'), findsOneWidget);
      // Chạm nhanh cũng không gửi
      await t.tap(find.byKey(const Key('sos-button')));
      await t.pump(const Duration(seconds: 4));
      expect(n, 0);
      // Giữ đủ
      g = await t.startGesture(t.getCenter(find.byKey(const Key('sos-button'))));
      await t.pump(); // khung hình đầu tiên đặt mốc bắt đầu của bộ đếm
      await t.pump(const Duration(milliseconds: 3100));
      expect(n, 1);
      await g.up();
      await t.pump();
      expect(n, 1, reason: 'chỉ gửi một lần');
    });
  });

  testWidgets('màn SOS của chủ: báo cho ai, gọi 115, huỷ bấm nhầm', (t) async {
    bigScreen(t);
    final dialed = <String>[];
    final safety = FakeSafety(event: sosEvent(), cardData: _card);
    final fam = FakeFamily(links: [link('l1', role: 'owner', other: 'c1', name: 'Minh')]);
    await t.pumpWidget(hostSos(const SosScreen(sosId: 's1'), safety: safety, fam: fam, dialed: dialed));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('sos-owner')), findsOneWidget);
    expect(find.text('Đã báo cho Minh'), findsOneWidget);
    expect(find.text('Penicillin'), findsOneWidget);
    expect(find.byKey(const Key('sos-ack')), findsNothing, reason: 'chủ không tự nhận');

    await t.tap(find.byKey(const Key('call-115')));
    await t.tap(find.byKey(const Key('call-contact-0')));
    expect(dialed, ['115', '0988 111 222']);

    await t.ensureVisible(find.byKey(const Key('sos-cancel')));
    await t.tap(find.byKey(const Key('sos-cancel')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sos-cancel-ok')));
    await t.pumpAndSettle();
    expect(safety.calls, contains('cancel:s1'));
    expect(find.byKey(const Key('sos-status-cancelled')), findsOneWidget);
    expect(find.byKey(const Key('sos-cancel')), findsNothing);
  });

  testWidgets('chủ chưa có người thân liên kết: nói rõ chưa báo được cho ai', (t) async {
    bigScreen(t);
    await t.pumpWidget(hostSos(const SosScreen(sosId: 's1'), safety: FakeSafety(event: sosEvent()), fam: FakeFamily()));
    await t.pumpAndSettle();
    expect(find.text('Chưa báo được cho ai'), findsOneWidget);
    expect(find.byKey(const Key('call-115')), findsOneWidget);
  });

  testWidgets('màn SOS của con: bấm "Tôi đã nhận" thì đổi trạng thái; có nút gọi người thân', (t) async {
    bigScreen(t);
    final dialed = <String>[];
    final safety = FakeSafety(event: sosEvent(owner: 'p1'), cardData: _card);
    final fam = FakeFamily(links: [link('l1')]); // carer của p1 "Nguyễn Thị Lan"
    await t.pumpWidget(hostSos(const SosScreen(sosId: 's1'), safety: safety, fam: fam, dialed: dialed));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('sos-carer')), findsOneWidget);
    expect(find.textContaining('Nguyễn Thị Lan vừa bấm SOS lúc 14:05'), findsOneWidget);
    await t.tap(find.byKey(const Key('call-owner')));
    expect(dialed, ['0912 345 678']);
    expect(find.byKey(const Key('sos-cancel')), findsNothing, reason: 'con không huỷ hộ');

    await t.tap(find.byKey(const Key('sos-ack')));
    await t.pumpAndSettle();
    expect(safety.calls, contains('ack:s1'));
    expect(find.byKey(const Key('sos-status-handled')), findsOneWidget);
    expect(find.text('Bạn đã nhận SOS này'), findsOneWidget);
    expect(find.byKey(const Key('sos-ack')), findsNothing);
  });

  testWidgets('đã có người khác nhận: con thấy tên người đó, không có nút nhận', (t) async {
    bigScreen(t);
    final safety = FakeSafety(event: sosEvent(owner: 'p1', handled: true, by: 'c2'));
    final fam = FakeFamily(links: [link('l1'), link('l2', other: 'c2', name: 'Anh Nam')]);
    await t.pumpWidget(hostSos(const SosScreen(sosId: 's1'), safety: safety, fam: fam));
    await t.pumpAndSettle();
    expect(find.text('Anh Nam đã nhận SOS này'), findsOneWidget);
    expect(find.byKey(const Key('sos-ack')), findsNothing);
  });

  testWidgets('gửi SOS thất bại (mất mạng): vẫn có nút gọi 115 và thử lại', (t) async {
    bigScreen(t);
    await t.pumpWidget(hostSos(const SosScreen(sosId: sosFailedId), safety: FakeSafety(), fam: FakeFamily()));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('sos-failed')), findsOneWidget);
    expect(find.text('Chưa gửi được cho người thân'), findsOneWidget);
    expect(find.byKey(const Key('call-115')), findsOneWidget);
    expect(find.byKey(const Key('sos-retry')), findsOneWidget);
  });

  testWidgets('thẻ y tế khẩn cấp: lưu bỏ liên hệ không có số; lỗi thì báo, không mất dữ liệu đã nhập', (t) async {
    bigScreen(t);
    final safety = FakeSafety();
    await t.pumpWidget(hostSos(const EmergencyCardScreen(ownerId: 'me'), safety: safety, fam: FakeFamily()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('blood-O+')));
    await t.enterText(find.byKey(const Key('card-allergies')), 'Penicillin');
    await t.enterText(find.byKey(const Key('card-contact-name-0')), 'Minh');
    await t.enterText(find.byKey(const Key('card-contact-phone-0')), '0988 111 222');
    await t.enterText(find.byKey(const Key('card-contact-name-1')), 'Bỏ');
    await t.ensureVisible(find.byKey(const Key('card-save')));
    safety.failCard = true;
    await t.tap(find.byKey(const Key('card-save')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('card-error')), findsOneWidget);
    expect(find.text('Penicillin'), findsOneWidget);

    safety.failCard = false;
    await t.tap(find.byKey(const Key('card-save')));
    await t.pumpAndSettle();
    expect(safety.saved?.bloodType, 'O+');
    expect(safety.saved?.allergies, 'Penicillin');
    expect(safety.saved?.contacts.length, 1);
    expect(safety.saved?.contacts.first.phone, '0988 111 222');
  });

  group('thông báo', () {
    test('PushPrefs: giờ yên tĩnh và công tắc mới', () {
      const p = PushPrefs();
      expect(p.doseAlerts, isTrue);
      expect(p.digest, isFalse);
      expect(p.hasQuiet, isFalse);
      final q = p.copyWith(quiet: (start: '22:00', end: '06:00'), digest: true);
      expect(q.hasQuiet, isTrue);
      expect(q.quietStart, '22:00');
      expect(q.copyWith(doseAlerts: false).quietEnd, '06:00', reason: 'đổi công tắc khác không mất giờ yên tĩnh');
      expect(q.copyWith(quiet: (start: null, end: null)).hasQuiet, isFalse);
    });

    test('bấm thông báo SOS mở đúng màn; "meds" mở tab Sức khoẻ', () {
      expect(PushService.pathFor({'type': 'sos', 'sos_id': 'abc', 'owner_id': 'o'}), '/sos/abc');
      expect(PushService.pathFor({'type': 'sos'}), isNull);
      expect(PushService.pathFor({'type': 'meds'}), '/bp');
    });
  });

  test('dialable bỏ khoảng trắng, chấm, gạch', () {
    expect(dialable('0912 345.678'), '0912345678');
    expect(dialable('+84 90-123-4567'), '+84901234567');
  });
}
