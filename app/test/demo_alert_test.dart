import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/push/push_service.dart';
import 'package:vg_svthm/features/safety/presentation/demo_alert_optin.dart';
import 'package:vg_svthm/features/safety/presentation/demo_alert_screen.dart';
import 'package:vg_svthm/features/safety/presentation/sos_widgets.dart';

DemoAlert alert({bool acked = false, bool byMe = false, String kind = 'fall'}) => DemoAlert(
  id: 'a1',
  kind: kind,
  message: 'Phát hiện người ngã',
  camera: 'Phòng ngủ',
  createdAt: DateTime(2026, 11, 26, 14, 5),
  acked: acked,
  ackedByMe: byMe,
  ackedByName: acked && !byMe ? 'Lan' : null,
);

Widget host({required DemoAlert? Function() current, List<String>? acks, List<String>? dialed}) => ProviderScope(
  overrides: [
    demoAlertProvider.overrideWith((ref, id) async => current()),
    demoAlertAckProvider.overrideWithValue((id) async => acks?.add(id)),
    phoneLauncherProvider.overrideWithValue((n) async => dialed?.add(n)),
  ],
  child: MaterialApp(theme: AppTheme.light, home: const DemoAlertScreen(alertId: 'a1')),
);

void main() {
  testWidgets('cảnh báo đang mở: hiện nội dung, nút nhận và gọi 115', (t) async {
    final dialed = <String>[];
    await t.pumpWidget(host(current: () => alert(), dialed: dialed));
    await t.pump();
    expect(find.byKey(const Key('demo-alert-open')), findsOneWidget);
    expect(find.text('Phát hiện người ngã'), findsNWidgets(2)); // tiêu đề + nội dung
    expect(find.textContaining('Phòng ngủ'), findsOneWidget);
    expect(find.textContaining('DEMO'), findsOneWidget);
    await t.tap(find.byKey(const Key('demo-alert-call')));
    expect(dialed, ['115']);
    await t.pumpWidget(const SizedBox()); // huỷ bộ hẹn giờ
  });

  testWidgets('bấm "Tôi đã nhận" gửi đúng mã và màn chuyển sang đã nhận', (t) async {
    final acks = <String>[];
    var acked = false;
    await t.pumpWidget(host(
      current: () => alert(acked: acked, byMe: acked),
      acks: acks,
    ));
    await t.pump();
    // Bấm nhận: giả lập máy chủ đã ghi.
    acked = true;
    await t.tap(find.byKey(const Key('demo-alert-ack')));
    await t.pump();
    await t.pump();
    expect(acks, ['a1']);
    expect(find.byKey(const Key('demo-alert-acked')), findsOneWidget);
    expect(find.byKey(const Key('demo-alert-ack')), findsNothing);
    expect(find.textContaining('Bạn đã nhận'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('người khác đã nhận: hiện tên, không còn nút nhận', (t) async {
    await t.pumpWidget(host(current: () => alert(acked: true)));
    await t.pump();
    expect(find.textContaining('Lan đã nhận'), findsOneWidget);
    expect(find.byKey(const Key('demo-alert-ack')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('không phải người nhận: báo không tìm thấy', (t) async {
    await t.pumpWidget(host(current: () => null));
    await t.pump();
    expect(find.text('Không tìm thấy cảnh báo này.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  test('tiêu đề theo loại cảnh báo', () {
    expect(alert(kind: 'fall').title, 'Phát hiện người ngã');
    expect(alert(kind: 'danger').title, contains('Nguy hiểm'));
    expect(alert(kind: 'test').title, contains('Thử'));
    expect(alert(kind: 'sos').title, 'Cảnh báo khẩn cấp');
  });

  test('DemoAlert.fromJson đọc đúng kết quả từ máy chủ', () {
    final a = DemoAlert.fromJson({
      'id': 'x', 'kind': 'fall', 'message': 'm', 'camera': 'c',
      'created_at': '2026-11-26T07:05:00Z', 'acked': true, 'acked_by_me': false, 'acked_by_name': 'Lan',
    });
    expect(a.acked, isTrue);
    expect(a.ackedByName, 'Lan');
    expect(DemoAlert.fromJson({'id': 'y'}).kind, 'danger');
  });

  test('bấm thông báo cảnh báo DEMO mở đúng màn', () {
    expect(PushService.pathFor({'type': 'demo_alert', 'alert_id': 'abc'}), '/alert/abc');
    expect(PushService.pathFor({'type': 'demo_alert'}), isNull);
  });

  group('công tắc nhận cảnh báo DEMO', () {
    ProviderContainer make(DemoOptInApi api, {bool signedIn = true}) {
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(signedIn ? const AuthUser(id: 'me', username: 'minh') : null),
        demoOptInApiProvider.overrideWithValue(api),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('fromJson: bật có nhãn, tắt, dữ liệu lạ', () {
      final a = DemoOptIn.fromJson({'on': true, 'label': 'lan'});
      expect(a.on, isTrue);
      expect(a.label, 'lan');
      expect(DemoOptIn.fromJson({'on': false, 'label': null}).on, isFalse);
      expect(DemoOptIn.fromJson(null).on, isFalse);
    });

    test('đọc trạng thái từ máy chủ; chưa đăng nhập thì tắt và không gọi máy chủ', () async {
      var reads = 0;
      final api = DemoOptInApi(
        read: () async { reads++; return const DemoOptIn(on: true, label: 'minh'); },
        write: (on) async => DemoOptIn(on: on),
      );
      final c = make(api);
      expect((await c.read(demoOptInProvider.future)).on, isTrue);
      expect(reads, 1);
      final out = make(api, signedIn: false);
      expect((await out.read(demoOptInProvider.future)).on, isFalse);
      expect(reads, 1);
    });

    test('đọc lỗi (chưa chạy migration, mất mạng) thì coi như tắt', () async {
      final c = make(DemoOptInApi(read: () async => throw Exception('x'), write: (on) async => DemoOptIn(on: on)));
      expect((await c.read(demoOptInProvider.future)).on, isFalse);
    });

    test('bật gửi đúng giá trị và nhận nhãn từ máy chủ; tắt lại được', () async {
      final sent = <bool>[];
      final c = make(DemoOptInApi(
        read: () async => const DemoOptIn(),
        write: (on) async { sent.add(on); return DemoOptIn(on: on, label: 'minh'); },
      ));
      await c.read(demoOptInProvider.future);
      expect(await c.read(demoOptInProvider.notifier).set(true), isNull);
      expect(c.read(demoOptInProvider).value?.on, isTrue);
      expect(c.read(demoOptInProvider).value?.label, 'minh');
      expect(await c.read(demoOptInProvider.notifier).set(false), isNull);
      expect(c.read(demoOptInProvider).value?.on, isFalse);
      expect(sent, [true, false]);
    });

    test('ghi lỗi: trả thông báo và công tắc về như cũ', () async {
      final c = make(DemoOptInApi(read: () async => const DemoOptIn(), write: (on) async => throw Exception('x')));
      await c.read(demoOptInProvider.future);
      final err = await c.read(demoOptInProvider.notifier).set(true);
      expect(err, isNotNull);
      expect(c.read(demoOptInProvider).value?.on, isFalse);
    });
  });
}
