import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/push/push_service.dart';
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
}
