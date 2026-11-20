import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vg_svthm/core/router/app_router.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/safety/data/safety_repository.dart';
import 'package:vg_svthm/features/safety/presentation/safety_providers.dart';
import 'package:vg_svthm/features/safety/presentation/sos_widgets.dart' show phoneLauncherProvider;
import 'package:vg_svthm/features/voice/core/vy_card.dart';
import 'package:vg_svthm/features/voice/data/direct_caller.dart';
import 'package:vg_svthm/features/voice/data/voice_actions.dart';
import 'package:vg_svthm/features/voice/presentation/vy_cards.dart';

class FakeSafety implements SafetyRepository {
  int triggers = 0;
  bool fail = false;

  @override
  Future<String> triggerSos() async {
    triggers++;
    if (fail) throw Exception('mạng');
    return 'sos-1';
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vg.call');

  group('Gọi thẳng (directCallProvider)', () {
    late List<String> dialed;
    late List<MethodCall> native;

    ProviderContainer make() => ProviderContainer(overrides: [
      phoneLauncherProvider.overrideWithValue((n) async => dialed.add(n)),
    ]);

    void mock(Future<Object?>? Function(MethodCall) h) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
        native.add(c);
        return h(c);
      });
    }

    setUp(() {
      dialed = [];
      native = [];
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    test('gọi thẳng: gửi số đã bỏ khoảng trắng cho phần Android, không mở bàn phím gọi', () async {
      mock((_) async => 'calling');
      final c = make();
      addTearDown(c.dispose);
      await c.read(directCallProvider)('0901 234.567');
      expect(native.single.method, 'call');
      expect((native.single.arguments as Map)['number'], '0901234567');
      expect(dialed, isEmpty);
    });

    test('lần đầu xin quyền ("asking"): không mở bàn phím (Android tự gọi sau khi cho phép)', () async {
      mock((_) async => 'asking');
      final c = make();
      addTearDown(c.dispose);
      await c.read(directCallProvider)('115');
      expect(dialed, isEmpty);
    });

    test('máy không có điện thoại, lỗi kênh hoặc chưa có phần Android: dự phòng mở bàn phím gọi có số sẵn', () async {
      mock((_) async => 'no_telephony');
      var c = make();
      await c.read(directCallProvider)('115');
      c.dispose();
      expect(dialed, ['115']);

      dialed.clear();
      mock((_) async => throw PlatformException(code: 'bad_number'));
      c = make();
      await c.read(directCallProvider)('0988111222');
      c.dispose();
      expect(dialed, ['0988111222']);

      dialed.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      c = make();
      await c.read(directCallProvider)('0912345678');
      c.dispose();
      expect(dialed, ['0912345678']);
    });

    test('số lạ (chữ, quá ngắn, ký tự điều khiển) thì KHÔNG gọi và không mở gì', () async {
      mock((_) async => 'calling');
      final c = make();
      addTearDown(c.dispose);
      for (final bad in ['abc', '12', '*123#', '09012345678901234567', '']) {
        await c.read(directCallProvider)(bad);
      }
      expect(native, isEmpty);
      expect(dialed, isEmpty);
    });
  });

  group('SOS bằng giọng', () {
    late FakeSafety safety;
    late GoRouter router;
    late ProviderContainer c;

    setUp(() {
      SharedPreferences.setMockInitialValues({'vy_intro_seen': true});
      safety = FakeSafety();
      router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/sos/:id', builder: (_, s) => Text('sos ${s.pathParameters['id']}')),
      ]);
      c = ProviderContainer(overrides: [
        safetyRepositoryProvider.overrideWithValue(safety),
        routerProvider.overrideWithValue(router),
      ]);
    });
    tearDown(() => c.dispose());

    test('nói rõ "gọi SOS": hiện thẻ đếm ngược 5 giây có Huỷ, CHƯA báo gì', () async {
      final say = await c.read(voiceActionsProvider).startSos('bác');
      expect(say, contains('sau 5 giây'));
      expect(say, contains('Huỷ'));
      final card = c.read(vyCardProvider)! as SosCard;
      expect(card.seconds, 5);
      expect(card.actions.single.label, 'Huỷ');
      expect(safety.triggers, 0);
    });

    Future<void> mountRouter(WidgetTester t) async {
      await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp.router(routerConfig: router)));
      await t.pump();
    }

    testWidgets('Huỷ: gỡ thẻ, không báo; hết giờ (onFire) mới báo và mở màn SOS', (t) async {
      await mountRouter(t);
      final a = c.read(voiceActionsProvider);
      await t.runAsync(() => a.startSos('bác'));
      c.read(vyCardProvider)!.actions.single.run(); // bấm Huỷ
      expect(c.read(vyCardProvider), isNull);
      expect(safety.triggers, 0);

      await t.runAsync(() => a.startSos('bác'));
      (c.read(vyCardProvider)! as SosCard).onFire(); // hết giờ
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(safety.triggers, 1);
      expect(c.read(vyCardProvider), isNull);
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/sos/sos-1');
    });

    testWidgets('mất mạng: vẫn mở màn SOS (có nút gọi 115) với mã "failed"', (t) async {
      await mountRouter(t);
      safety.fail = true;
      await t.runAsync(() => c.read(voiceActionsProvider).fireSos());
      await t.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/sos/failed');
    });
  });

  group('Thẻ đếm ngược', () {
    Future<void> show(WidgetTester t, VyCard card) => t.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: VyCardView(card: card, onAction: (a) => a.run()))),
    );

    testWidgets('SOS: 5 → 1 rồi báo ĐÚNG MỘT LẦN', (t) async {
      var fired = 0;
      await show(t, SosCard(seconds: 5, onFire: () => fired++));
      expect(find.byKey(const Key('vy-sos-count')), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      for (var i = 4; i >= 1; i--) {
        await t.pump(const Duration(seconds: 1));
        expect(find.text('$i'), findsOneWidget);
        expect(fired, 0);
      }
      await t.pump(const Duration(seconds: 1));
      expect(fired, 1);
      expect(find.text('Đã báo SOS'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      expect(fired, 1);
    });

    testWidgets('SOS: thẻ bị gỡ giữa chừng (đóng Vy, nói việc khác) thì KHÔNG báo', (t) async {
      var fired = 0;
      await show(t, SosCard(seconds: 5, onFire: () => fired++));
      await t.pump(const Duration(seconds: 3));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
      expect(fired, 0);
    });

    testWidgets('SOS: bấm Huỷ chạy đúng hành động Huỷ', (t) async {
      var cancelled = 0;
      await show(t, SosCard(seconds: 5, onFire: () {}, actions: [VyCardAction(label: 'Huỷ', primary: true, run: () => cancelled++)]));
      await t.tap(find.text('Huỷ'));
      expect(cancelled, 1);
    });
  });
}
