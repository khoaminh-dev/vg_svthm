import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/meds/data/med_scan_client.dart';
import 'package:vg_svthm/features/meds/domain/med_scan_models.dart';
import 'package:vg_svthm/features/meds/domain/meds_models.dart';
import 'package:vg_svthm/features/meds/presentation/med_plan_edit_screen.dart';
import 'package:vg_svthm/features/meds/presentation/med_scan_screen.dart';
import 'package:vg_svthm/features/meds/presentation/meds_providers.dart';
import 'package:vg_svthm/features/ocr/domain/ocr_models.dart';
import 'package:vg_svthm/features/ocr/domain/ocr_repositories.dart';
import 'package:vg_svthm/features/ocr/presentation/providers/ocr_providers.dart';

import 'meds_test.dart' show FakeMeds, bigScreen;
import 'package:vg_svthm/features/meds/domain/med_redact.dart';

class _Ocr implements OcrEngine {
  _Ocr(this.text);
  final String text;
  String? lastPath;
  @override
  Future<OcrScan> scan(String imagePath) async {
    lastPath = imagePath;
    return OcrScan(rawText: text, values: const []);
  }
}

class _Client extends MedScanClient {
  _Client(this.result) : super(accessToken: () => 't');
  final ScanResult result;
  String? sent;
  @override
  Future<ScanResult> parse(String redactedText) async {
    sent = redactedText;
    return result;
  }
}

const _rx = '''Họ tên: NGUYỄN VĂN HÙNG
SĐT: 0912345678
Sáng: Amlodipin 5mg x 1 viên
Tối: Metformin 500mg x 1 viên''';

const _fake = ScanResult(
  title: 'Đơn tim mạch',
  days: 30,
  slots: [
    ScanSlot(label: 'Sáng', status: ScanStatus.ok, items: [
      ScanItem(name: 'Amlodipin', strength: '5mg', status: ScanStatus.ok),
      ScanItem(name: 'Aspirin', status: ScanStatus.none),
    ]),
    ScanSlot(label: 'Tối', status: ScanStatus.fuzzy, items: [
      ScanItem(name: 'Metformin', strength: '500mg', status: ScanStatus.fuzzy),
    ]),
  ],
);

Future<(GoRouter, FakeMeds, _Ocr, _Client)> _scanHost(WidgetTester t, {String text = _rx, ScanResult result = _fake, List<MedPlan>? plans}) async {
  bigScreen(t);
  final repo = FakeMeds(plans: plans);
  final ocr = _Ocr(text);
  final client = _Client(result);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('GỐC')),
      GoRoute(path: '/scan', builder: (_, _) => const MedScanScreen(ownerId: 'me')),
      GoRoute(
        path: '/meds/plan/:owner',
        builder: (_, s) => MedPlanEditScreen(ownerId: 'me', existing: s.extra is MedPlan ? s.extra as MedPlan : null),
      ),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh')),
        medsRepositoryProvider.overrideWithValue(repo),
        ocrEngineProvider.overrideWithValue(ocr),
        medScanClientProvider.overrideWithValue(client),
        medPhotoPickerProvider.overrideWithValue(({required bool camera}) async => '/tmp/none.jpg'),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await t.pumpAndSettle();
  unawaited(router.push('/scan'));
  await t.pumpAndSettle();
  return (router, repo, ocr, client);
}

void main() {
  group('redactMedText', () {
    test('che họ tên, ngày sinh, địa chỉ, điện thoại, BHYT, CCCD; giữ thuốc', () {
      const raw = '''PHÒNG KHÁM ĐA KHOA
Họ tên: NGUYỄN VĂN HÙNG
Ngày sinh: 12/03/1952
Địa chỉ: 12 Lê Lợi, Quận 1
SĐT: 0912 345 678
Mã BHYT: DN4797912345678
CCCD 079052001234
Sáng: Amlodipin 5mg x 1 viên sau ăn
Tối: Metformin 500mg x 1 viên''';
      final r = redactMedText(raw);
      for (final leak in ['NGUYỄN', 'HÙNG', '1952', 'Lê Lợi', '0912', 'DN4797912345678', '079052001234']) {
        expect(r.text.contains(leak), isFalse, reason: 'lộ: $leak\n${r.text}');
      }
      expect(r.text, contains('Amlodipin 5mg x 1 viên sau ăn'));
      expect(r.text, contains('Metformin 500mg x 1 viên'));
      expect(r.text, contains('Họ tên:'));
      expect(r.masked, greaterThanOrEqualTo(6));
    });

    test('nhãn đứng riêng một dòng thì che dòng kế (chữ đọc hay tách dòng)', () {
      final r = redactMedText('Bệnh nhân:\nTRẦN THỊ MAI\nSáng: Aspirin 81mg');
      expect(r.text, isNot(contains('TRẦN')));
      expect(r.text, contains('Aspirin 81mg'));
    });

    test('che số điện thoại và tuổi nằm giữa dòng, không đụng liều thuốc', () {
      final r = redactMedText('Bà 73 tuổi gọi 0987654321 để hỏi. Uống 2 viên x 30 ngày, SL: 60');
      expect(r.text, isNot(contains('0987654321')));
      expect(r.text, isNot(contains('73 tuổi')));
      expect(r.text, contains('Uống 2 viên x 30 ngày, SL: 60'));
    });

    test('đơn không có thông tin cá nhân thì giữ nguyên', () {
      const raw = 'Chiều: Losartan 50mg x 1 viên\nTrưa: Atorvastatin 20mg x 1 viên';
      final r = redactMedText(raw);
      expect(r.text, raw);
      expect(r.masked, 0);
    });
  });

  testWidgets('chụp đơn: chỉ gửi chữ đã che, hiện mức tin cậy, thuốc không có bằng chứng bị bỏ', (t) async {
    final (_, repo, _, client) = await _scanHost(t);
    await t.tap(find.byKey(const Key('scan-camera')));
    await t.pumpAndSettle();
    expect(client.sent, isNotNull);
    expect(client.sent, isNot(contains('NGUYỄN')));
    expect(client.sent, isNot(contains('0912345678')));
    expect(client.sent, contains('Amlodipin 5mg'));
    expect(find.byKey(const Key('scan-review')), findsOneWidget);
    expect(find.textContaining('Đã che 2 chỗ'), findsOneWidget);
    expect(find.text('Khớp với ảnh'), findsOneWidget);
    expect(find.text('Gần giống, hãy đối chiếu'), findsOneWidget);
    expect(find.text('Không thấy trong ảnh, đã bỏ'), findsOneWidget);
    expect(find.byKey(const Key('scan-dropped')), findsOneWidget);
    expect(repo.saved, isNull, reason: 'quét ảnh không được tự lưu lịch');
  });

  testWidgets('bấm kiểm tra: mở màn sửa đơn với bản nháp (bỏ thuốc không bằng chứng), chưa lưu gì', (t) async {
    final (_, repo, _, _) = await _scanHost(t);
    await t.tap(find.byKey(const Key('scan-camera')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('scan-use')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('plan-edit')), findsOneWidget);
    expect(find.text('Amlodipin 5mg x1 viên'), findsOneWidget);
    expect(find.text('Metformin 500mg x1 viên'), findsOneWidget);
    expect(find.textContaining('Aspirin'), findsNothing);
    expect(find.byKey(const Key('slot-0')), findsOneWidget);
    expect(find.byKey(const Key('slot-1')), findsOneWidget);
    expect(repo.saved, isNull);
  });

  testWidgets('OCR không ra chữ: báo lỗi, không gọi máy chủ; có nút nhập tay', (t) async {
    final (_, _, _, client) = await _scanHost(t, text: 'ab');
    await t.tap(find.byKey(const Key('scan-gallery')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('scan-error')), findsOneWidget);
    expect(find.textContaining('Không đọc được chữ'), findsOneWidget);
    expect(find.byKey(const Key('scan-manual')), findsOneWidget);
    expect(client.sent, isNull);
  });

  testWidgets('kết quả rỗng: không có nút dùng bản nháp', (t) async {
    await _scanHost(t, result: const ScanResult());
    await t.tap(find.byKey(const Key('scan-camera')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('scan-empty')), findsOneWidget);
    expect(find.byKey(const Key('scan-use')), findsNothing);
  });

  const allOk = ScanResult(
    title: 'Đơn huyết áp',
    days: 30,
    slots: [
      ScanSlot(label: 'Sáng', status: ScanStatus.ok, items: [
        ScanItem(name: 'Amlodipin', strength: '5mg', status: ScanStatus.ok),
      ]),
    ],
  );

  testWidgets('mọi thuốc khớp ảnh, chưa có đơn nào: có "Lưu luôn", bấm là lưu (2 bước: chụp, lưu)', (t) async {
    final (router, repo, _, _) = await _scanHost(t, result: allOk);
    await t.tap(find.byKey(const Key('scan-camera')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('scan-save')), findsOneWidget);
    expect(find.byKey(const Key('scan-use')), findsOneWidget, reason: 'vẫn có đường chỉnh trước khi lưu');
    expect(repo.saved, isNull, reason: 'chưa bấm thì chưa lưu');
    await t.tap(find.byKey(const Key('scan-save')));
    await t.pumpAndSettle();
    expect(repo.saved, isNotNull);
    expect(repo.saved!.title, 'Đơn huyết áp');
    expect(repo.saved!.slots.single.bagsRemaining, 30);
    expect(repo.savedReplace, isFalse);
    expect(find.text('GỐC'), findsOneWidget, reason: 'lưu xong quay về màn trước');
    expect(router, isNotNull);
  });

  testWidgets('có thuốc chỉ "gần giống" hoặc bị bỏ: KHÔNG có "Lưu luôn", phải kiểm tra và chỉnh', (t) async {
    await _scanHost(t);
    await t.tap(find.byKey(const Key('scan-camera')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('scan-save')), findsNothing);
    expect(find.byKey(const Key('scan-use')), findsOneWidget);
  });

  testWidgets('đang có đơn dùng: không "Lưu luôn" (phải hỏi dừng đơn cũ ở màn sửa)', (t) async {
    final old = MedPlan(title: 'Đơn cũ', startDate: DateTime.now().subtract(const Duration(days: 2)), slots: const [MedSlot(label: 'Sáng', time: '07:00')]);
    await _scanHost(t, result: allOk, plans: [old]);
    await t.tap(find.byKey(const Key('scan-camera')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('scan-save')), findsNothing);
  });

  test('toDraft: bỏ mục không bằng chứng, giờ theo tên cữ, ngày kết thúc theo số ngày', () {
    final d = _fake.toDraft(DateTime(2026, 11, 16, 9));
    expect(d.id, isNull);
    expect([for (final s in d.slots) s.time], ['07:00', '20:30']);
    expect(d.slots.first.items.map((i) => i.name), ['Amlodipin']);
    expect(d.endDate, DateTime(2026, 12, 15));
    expect(d.title, 'Đơn tim mạch');
  });
}
