import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/shared/widgets/brand_paths.dart';
import 'package:vg_svthm/shared/widgets/logo_intro.dart';

Widget app({bool enabled = true, bool reduce = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: LogoIntro(enabled: enabled, child: const Scaffold(body: Text('NỘI DUNG'))),
  ),
);

void main() {
  setUp(() => LogoIntro.played = false);

  test('đường nét logo đọc đúng: khung bao khớp ảnh gốc', () {
    final b = parseBrandPath(brandSwoosh).getBounds();
    expect(b.left, closeTo(184, 3));
    expect(b.top, closeTo(63, 3));
    expect(b.right, closeTo(643, 3));
    expect(b.bottom, closeTo(531, 3));
    final w = parseBrandPath(brandWordmark).getBounds();
    expect(w.left, greaterThan(90));
    expect(w.right, lessThan(760));
    expect(w.top, greaterThan(540));
    expect(w.bottom, lessThan(700));
    final t = parseBrandPath(brandTagline).getBounds();
    expect(t.top, greaterThan(675));
  });

  testWidgets('chạy rồi tự biến mất, để lộ màn hình bên dưới; chỉ chạy một lần', (t) async {
    await t.pumpWidget(app());
    expect(find.byKey(const Key('logo-intro')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const Key('logo-intro')), findsOneWidget, reason: 'đang chạy');
    await t.pump(const Duration(milliseconds: 1200));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('logo-intro')), findsNothing);
    expect(find.text('NỘI DUNG'), findsOneWidget);

    // Dựng lại trong cùng lần mở app: không chạy nữa.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app());
    expect(find.byKey(const Key('logo-intro')), findsNothing);
  });

  testWidgets('chạm để bỏ qua', (t) async {
    await t.pumpWidget(app());
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const Key('logo-intro')));
    await t.pump();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('logo-intro')), findsNothing);
    expect(find.text('NỘI DUNG'), findsOneWidget);
  });

  testWidgets('tắt hiệu ứng chuyển động của hệ thống thì không chạy', (t) async {
    await t.pumpWidget(app(reduce: true));
    expect(find.byKey(const Key('logo-intro')), findsNothing);
  });

  testWidgets('BrandLogo vẽ được không lỗi', (t) async {
    await t.pumpWidget(const MaterialApp(home: Center(child: BrandLogo(width: 200))));
    expect(tester(t), isNull);
  });
}

Object? tester(WidgetTester t) => t.takeException();
