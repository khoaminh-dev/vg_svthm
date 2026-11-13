import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/update/data/update_repository.dart';
import 'package:vg_svthm/features/update/domain/app_update.dart';
import 'package:vg_svthm/features/update/presentation/update_gate.dart';
import 'package:vg_svthm/features/update/presentation/update_providers.dart';

Map<String, dynamic> row({int latest = 5, int min = 1, String? url = 'https://x.test/a.apk', String? sha}) => {
  'latest_build': latest,
  'latest_name': '1.0.$latest',
  'min_supported_build': min,
  'apk_url': url,
  'apk_sha256': sha,
  'notes': 'Thêm gửi ảnh',
};

class FakeInstaller implements ApkInstaller {
  FakeInstaller(this.events);
  final List<InstallEvent> events;
  int calls = 0;

  @override
  Stream<InstallEvent> install(AppUpdate update) {
    calls++;
    return Stream.fromIterable(events);
  }
}

Widget host(AppUpdate? update, ApkInstaller installer) => ProviderScope(
  overrides: [
    updateCheckProvider.overrideWith((ref) async => update),
    apkInstallerProvider.overrideWithValue(installer),
  ],
  child: const MaterialApp(home: UpdateGate(child: Scaffold(body: Text('trang chủ')))),
);

void main() {
  group('evaluateUpdate', () {
    test('đã mới nhất thì không có cập nhật', () {
      expect(evaluateUpdate(currentBuild: 5, row: row()), isNull);
      expect(evaluateUpdate(currentBuild: 6, row: row()), isNull);
    });

    test('thấp hơn latest nhưng >= min là nhắc nhẹ', () {
      final u = evaluateUpdate(currentBuild: 3, row: row(min: 2))!;
      expect(u.level, UpdateLevel.optional);
      expect(u.latestBuild, 5);
      expect(u.notes, 'Thêm gửi ảnh');
    });

    test('thấp hơn min là bắt buộc', () {
      expect(evaluateUpdate(currentBuild: 1, row: row(min: 2))!.isRequired, isTrue);
    });

    test('thiếu hoặc sai link tải thì bỏ qua để không khoá người dùng', () {
      expect(evaluateUpdate(currentBuild: 1, row: row(url: null)), isNull);
      expect(evaluateUpdate(currentBuild: 1, row: row(url: 'http://x.test/a.apk')), isNull);
    });

    test('sha256 rỗng thì coi như không có', () {
      expect(evaluateUpdate(currentBuild: 1, row: row(sha: ''))!.sha256, isNull);
    });
  });

  group('UpdateGate', () {
    testWidgets('không có cập nhật thì không hiện gì', (t) async {
      await t.pumpWidget(host(null, FakeInstaller(const [])));
      await t.pumpAndSettle();
      expect(find.text('trang chủ'), findsOneWidget);
      expect(find.text('Cập nhật'), findsNothing);
    });

    testWidgets('bản nhắc nhẹ: có thể bấm Để sau', (t) async {
      await t.pumpWidget(host(evaluateUpdate(currentBuild: 3, row: row(min: 2)), FakeInstaller(const [])));
      await t.pumpAndSettle();
      expect(find.text('Có bản mới'), findsOneWidget);
      expect(find.text('Thêm gửi ảnh'), findsOneWidget);
      await t.tap(find.text('Để sau'));
      await t.pumpAndSettle();
      expect(find.text('Có bản mới'), findsNothing);
    });

    testWidgets('bản bắt buộc: không có nút Để sau', (t) async {
      await t.pumpWidget(host(evaluateUpdate(currentBuild: 1, row: row(min: 2)), FakeInstaller(const [])));
      await t.pumpAndSettle();
      expect(find.text('Cần cập nhật để tiếp tục'), findsOneWidget);
      expect(find.text('Để sau'), findsNothing);
    });

    testWidgets('bấm Cập nhật thì tải rồi nhắc bấm xác nhận của hệ thống', (t) async {
      final installer = FakeInstaller(const [
        InstallEvent(InstallPhase.downloading, progress: 40),
        InstallEvent(InstallPhase.installing),
      ]);
      await t.pumpWidget(host(evaluateUpdate(currentBuild: 3, row: row(min: 2)), installer));
      await t.pumpAndSettle();
      await t.tap(find.text('Cập nhật'));
      await t.pumpAndSettle();
      expect(installer.calls, 1);
      expect(find.textContaining('trên màn hình hệ thống'), findsOneWidget);
    });

    testWidgets('lỗi tải thì hiện thông báo và cho Thử lại', (t) async {
      final installer = FakeInstaller(const [
        InstallEvent(InstallPhase.failed, message: 'Không tải được bản mới, hãy kiểm tra mạng và thử lại.'),
      ]);
      await t.pumpWidget(host(evaluateUpdate(currentBuild: 3, row: row(min: 2)), installer));
      await t.pumpAndSettle();
      await t.tap(find.text('Cập nhật'));
      await t.pumpAndSettle();
      expect(find.textContaining('Không tải được'), findsOneWidget);
      await t.tap(find.text('Thử lại'));
      await t.pumpAndSettle();
      expect(installer.calls, 2);
    });
  });
}
